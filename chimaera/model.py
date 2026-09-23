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


class ReferenceModel:
    """Model one compiled protocol context at synchronized-clock granularity."""

    def __init__(self, compilation: _HasIR, protocol: str):
        matches = [item for item in compilation.ir["protocols"] if item["name"] == protocol]
        if not matches:
            raise CompileError(f"compiled program has no protocol {protocol!r}")
        if compilation.ir["mutations"]:
            raise CompileError("mutation execution is not implemented in the Phase 5 checkpoint model")
        self.protocol = matches[0]
        self.states = {state["id"]: state for state in self.protocol["states"]}
        self.pin_indexes = {pin["name"]: pin["index"] for pin in self.protocol["pins"]}
        self.state_id = int(self.protocol["entry_state"])
        self.timer = int(self.states[self.state_id]["timeout_cycles"])
        self.previous_inputs = 0
        self.drive_value = 0
        self.drive_enable = 0
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

    def step(self, synchronized_inputs: int) -> StepResult:
        """Advance one clock using the already-synchronized 8-bit input sample."""

        if not 0 <= synchronized_inputs <= 0xFF:
            raise ValueError("synchronized_inputs must fit in 8 bits")
        state = self.states[self.state_id]
        before = str(state["name"])
        event_match = self._event_matches(state, synchronized_inputs)
        from_timeout = (not event_match) and self.timer == 1
        fired = event_match or from_timeout

        if fired:
            action_mask = int(state["action_mask"])
            oe_mask = int(state["oe_mask"])
            self.drive_value = (
                (self.drive_value & ~action_mask) | (int(state["action_value"]) & action_mask)
            ) & 0xFF
            self.drive_enable = (
                (self.drive_enable & ~oe_mask) | (int(state["oe_value"]) & oe_mask)
            ) & 0xFF
            for action in state["actions"]:
                if action["kind"] == "sample":
                    bit = (synchronized_inputs >> self.pin_indexes[action["pin"]]) & 1
                    old = self.variables.get(action["variable"], 0)
                    self.variables[action["variable"]] = ((old << 1) | bit) & 0xFFFF
                elif action["kind"] == "count":
                    name = action["variable"]
                    self.variables[name] = (self.variables.get(name, 0) + 1) & 0xFFFF
                elif action["kind"] == "reset":
                    self.variables[action["variable"]] = 0

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

    def step(self, synchronized_inputs: int) -> ChipStepResult:
        rearming = self.pending_context
        context_results = {
            name: (
                context.rearm_step(synchronized_inputs)
                if name == rearming
                else context.step(synchronized_inputs)
            )
            for name, context in self.contexts.items()
        }
        fired = [name for name, result in context_results.items() if result.fired]
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
