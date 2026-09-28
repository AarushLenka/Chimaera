"""Cycle-step reference model for compiler-emitted reaction descriptors."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Protocol

from .errors import CompileError


class _HasIR(Protocol):
    ir: Mapping[str, Any]


@dataclass(frozen=True)
class StepResult:
    fired: bool
    from_timeout: bool
    state_before: str
    state_after: str
    drive_value: int
    drive_enable: int
    variables: Mapping[str, int]


@dataclass(frozen=True)
class ChipStepResult:
    contexts: Mapping[str, StepResult]
    drive_value: int
    drive_enable: int


def _eval_expr(expression: Mapping[str, Any], values: Mapping[str, int]) -> int:
    kind = expression["kind"]
    if kind == "number":
        return int(expression["value"])
    if kind == "name":
        name = str(expression["value"])
        if name not in values:
            raise CompileError(f"reference model has no value for {name!r}")
        return int(values[name])
    if kind == "unary":
        operand = _eval_expr(expression["left"], values)
        if expression["value"] == "!":
            return int(not operand)
        raise CompileError(f"unsupported unary operator {expression['value']!r}")
    if kind == "binary":
        left = _eval_expr(expression["left"], values)
        right = _eval_expr(expression["right"], values)
        operator = expression["value"]
        if operator == "||":
            return int(bool(left) or bool(right))
        if operator == "&&":
            return int(bool(left) and bool(right))
        if operator == "==":
            return int(left == right)
        if operator == "!=":
            return int(left != right)
        if operator == "<":
            return int(left < right)
        if operator == "<=":
            return int(left <= right)
        if operator == ">":
            return int(left > right)
        if operator == ">=":
            return int(left >= right)
        if operator == "%":
            if right == 0:
                raise CompileError("modulo-by-zero reached in reference model")
            return left % right
        raise CompileError(f"unsupported binary operator {operator!r}")
    raise CompileError(f"unsupported expression kind {kind!r}")


def _advance_lfsr(value: int) -> int:
    """Advance the shared 16-bit x^16+x^14+x^13+x^11+1 LFSR."""

    feedback = ((value >> 15) ^ (value >> 13) ^ (value >> 12) ^ (value >> 10)) & 1
    return ((value << 1) & 0xFFFF) | feedback


class ReferenceModel:
    """Model one compiled protocol context at synchronized-clock granularity."""

    def __init__(self, compilation: _HasIR, protocol: str):
        matches = [item for item in compilation.ir["protocols"] if item["name"] == protocol]
        if not matches:
            raise CompileError(f"compiled program has no protocol {protocol!r}")
        self.protocol = matches[0]
        self.states = {state["id"]: state for state in self.protocol["states"]}
        self.pin_indexes = {pin["name"]: pin["index"] for pin in self.protocol["pins"]}
        self.mutations = [
            mutation
            for mutation in compilation.ir.get("mutations", [])
            if mutation["protocol"] == protocol
        ]
        self.fault_lfsr = int(compilation.ir.get("fault_seed", 1))
        if self.fault_lfsr == 0:
            raise CompileError("fault seed must be non-zero")
        self.state_id = int(self.protocol["entry_state"])
        self.timer = int(self.states[self.state_id]["timeout_cycles"])
        self.previous_inputs = 0
        self.drive_value = 0
        self.drive_enable = 0
        self.pending_action: tuple[int, int, int, int] | None = None
        self.pending_delay = 0
        self.variables: dict[str, int] = {"transaction_count": 0}

    @property
    def state_name(self) -> str:
        return str(self.states[self.state_id]["name"])

    def _condition_values(self, inputs: int) -> dict[str, int]:
        values = dict(self.variables)
        for name, index in self.pin_indexes.items():
            values[name] = (inputs >> index) & 1
        return values

    def _event_matches(self, state: Mapping[str, Any], inputs: int) -> bool:
        kind = state["event_kind_name"]
        event_mask = int(state["event_mask"])
        rising = (~self.previous_inputs & inputs) & 0xFF
        falling = (self.previous_inputs & ~inputs) & 0xFF
        if kind == "none":
            return False
        if kind == "rise":
            matched = bool(rising & event_mask)
        elif kind == "fall":
            matched = bool(falling & event_mask)
        elif kind == "level":
            matched = (inputs & event_mask) == (int(state["event_value"]) & event_mask)
        elif kind == "rise_while_level":
            matched = bool(rising & event_mask)
        elif kind == "fall_while_level":
            matched = bool(falling & event_mask)
        else:
            raise CompileError(f"reference model cannot evaluate event kind {kind!r}")
        if matched and int(state["level_mask"]):
            level_mask = int(state["level_mask"])
            matched = (inputs & level_mask) == (int(state["level_value"]) & level_mask)
        return matched

    def _commit_action(self, action: tuple[int, int, int, int]) -> None:
        action_mask, action_value, oe_mask, oe_value = action
        self.drive_value = (self.drive_value & ~action_mask) | (action_value & action_mask)
        self.drive_enable = (self.drive_enable & ~oe_mask) | (oe_value & oe_mask)
        self.drive_value &= 0xFF
        self.drive_enable &= 0xFF

    def _tick_delayed_output(self) -> None:
        if self.pending_action is None:
            return
        if self.pending_delay <= 1:
            self._commit_action(self.pending_action)
            self.pending_action = None
            self.pending_delay = 0
        else:
            self.pending_delay -= 1

    def step(self, synchronized_inputs: int, *, advance_fault: bool = True) -> StepResult:
        """Advance one clock using the already-synchronized 8-bit input sample."""

        if not 0 <= synchronized_inputs <= 0xFF:
            raise ValueError("synchronized_inputs must fit in 8 bits")
        self._tick_delayed_output()
        state = self.states[self.state_id]
        before = str(state["name"])
        event_match = self._event_matches(state, synchronized_inputs)
        from_timeout = (not event_match) and self.timer == 1
        fired = event_match or from_timeout

        if fired:
            action_mask = int(state["action_mask"])
            oe_mask = int(state["oe_mask"])
            output_action = (
                action_mask,
                int(state["action_value"]),
                oe_mask,
                int(state["oe_value"]),
            )
            for state_action in state["actions"]:
                if state_action["kind"] == "sample":
                    bit = (synchronized_inputs >> self.pin_indexes[state_action["pin"]]) & 1
                    old = self.variables.get(state_action["variable"], 0)
                    self.variables[state_action["variable"]] = ((old << 1) | bit) & 0xFFFF
                elif state_action["kind"] == "count":
                    name = state_action["variable"]
                    self.variables[name] = (self.variables.get(name, 0) + 1) & 0xFFFF
                elif state_action["kind"] == "reset":
                    self.variables[state_action["variable"]] = 0

            # The first hardware fault slice mutates the sampled shift
            # register after the normal action update. This ordering makes a
            # captured byte reproducible while keeping output actions at the
            # original fixed one-cycle reaction point.
            mutation_values = self._condition_values(synchronized_inputs)
            delay_cycles = 0
            for mutation in self.mutations:
                effect = mutation["effect"]
                if effect["kind"] not in {"flip_bits", "delay"}:
                    raise CompileError(
                        f"reference model cannot execute mutation effect {effect['kind']!r}"
                    )
                if _eval_expr(mutation["condition"], mutation_values):
                    if effect["kind"] == "flip_bits":
                        variable = effect["variable"]
                        if variable not in self.variables:
                            raise CompileError(
                                f"reference model has no mutation variable {variable!r}"
                            )
                        self.variables[variable] = (
                            self.variables[variable] ^ int(effect["mask"] or 0)
                        ) & 0xFFFF
                    else:
                        delay_cycles = max(delay_cycles, int(effect["amount"] or 0))
            if delay_cycles:
                self.pending_action = output_action
                self.pending_delay = delay_cycles
            else:
                self._commit_action(output_action)
            if advance_fault:
                self.fault_lfsr = _advance_lfsr(self.fault_lfsr)

            next_state = self.state_id
            if from_timeout:
                if state["timeout_target"] is not None:
                    next_state = int(state["timeout_target"])
            else:
                values = self._condition_values(synchronized_inputs)
                for successor in state["successors"]:
                    condition = successor["condition"]
                    if condition is None or _eval_expr(condition, values):
                        next_state = int(successor["target"])
                        break
            if next_state == int(self.protocol["entry_state"]) and self.state_id != next_state:
                self.variables["transaction_count"] += 1
            self.state_id = next_state
            self.timer = int(self.states[self.state_id]["timeout_cycles"])
        elif self.timer > 0:
            self.timer -= 1

        self.previous_inputs = synchronized_inputs
        return StepResult(
            fired=fired,
            from_timeout=from_timeout,
            state_before=before,
            state_after=self.state_name,
            drive_value=self.drive_value,
            drive_enable=self.drive_enable,
            variables=dict(self.variables),
        )

    def rearm_step(self, synchronized_inputs: int) -> StepResult:
        """Consume a clock used only to reload this context's next descriptor."""

        if not 0 <= synchronized_inputs <= 0xFF:
            raise ValueError("synchronized_inputs must fit in 8 bits")
        self._tick_delayed_output()
        state_name = self.state_name
        self.previous_inputs = synchronized_inputs
        return StepResult(
            fired=False,
            from_timeout=False,
            state_before=state_name,
            state_after=state_name,
            drive_value=self.drive_value,
            drive_enable=self.drive_enable,
            variables=dict(self.variables),
        )


class ChipReferenceModel:
    """Run all compiled contexts against the same synchronized input sample."""

    def __init__(self, compilation: _HasIR):
        self.contexts = {
            protocol["name"]: ReferenceModel(compilation, protocol["name"])
            for protocol in compilation.ir["protocols"]
        }
        self.open_drain_mask = 0
        for protocol in compilation.ir["protocols"]:
            for pin in protocol["pins"]:
                if pin["mode"] == "open_drain":
                    self.open_drain_mask |= 1 << int(pin["index"])
        self.pending_context: str | None = None
        self.fault_lfsr = int(compilation.ir.get("fault_seed", 1))

    def step(self, synchronized_inputs: int) -> ChipStepResult:
        rearming = self.pending_context
        context_results = {
            name: (
                context.rearm_step(synchronized_inputs)
                if name == rearming
                else self._step_context(context, synchronized_inputs)
            )
            for name, context in self.contexts.items()
        }
        fired = [name for name, result in context_results.items() if result.fired]
        if fired:
            self.fault_lfsr = _advance_lfsr(self.fault_lfsr)
            for context in self.contexts.values():
                context.fault_lfsr = self.fault_lfsr
        if rearming is not None:
            # The pending reload owns this edge's single descriptor read. With
            # two contexts, at most the other context can generate new work.
            self.pending_context = fired[0] if fired else None
        else:
            # In declaration/context order, the first fire reloads immediately;
            # a simultaneous second fire is the bounded deferred request.
            self.pending_context = fired[1] if len(fired) > 1 else None
        drive_value = 0
        drive_enable = 0
        for result in context_results.values():
            overlap = drive_enable & result.drive_enable
            if overlap:
                raise CompileError(f"reference contexts drive overlapping mask 0x{overlap:02x}")
            drive_value |= result.drive_value & result.drive_enable
            drive_enable |= result.drive_enable
        if drive_value & drive_enable & self.open_drain_mask:
            raise CompileError("reference model attempted an active-high open-drain drive")
        return ChipStepResult(context_results, drive_value & 0xFF, drive_enable & 0xFF)

    def _step_context(self, context: ReferenceModel, synchronized_inputs: int) -> StepResult:
        context.fault_lfsr = self.fault_lfsr
        return context.step(synchronized_inputs, advance_fault=False)
