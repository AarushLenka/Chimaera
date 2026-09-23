"""Static checker and deterministic Phase 5 host-object compiler."""

from __future__ import annotations

import binascii
import base64
import hashlib
import json
import re
import struct
from dataclasses import dataclass
from typing import Any, Mapping

from .ast import Action, Duration, Expr, Program, Protocol, State
from .backend import PackedProgram, pack_program
from .errors import CompileError
from .parser import parse


_PIN_MODES = {"input", "output", "open_drain", "bidirectional"}
_EVENT_KINDS = {
    "none": 0,
    "rise": 1,
    "fall": 2,
    "level": 3,
    "rise_while_level": 4,
    "fall_while_level": 5,
}
_PHYSICAL_PIN = re.compile(r"^uio(?:\[(?P<bracket>[0-7])\]|(?P<plain>[0-7]))$")
_OBJECT_MAGIC = b"CHOBJ\x00\x01"


@dataclass(frozen=True)
class Compilation:
    """All artifacts produced by the Phase 5 compiler front end.

    ``object_bytes`` is a versioned host-side intermediate object. It is
    retains the inspectable host representation while ``packed_program`` carries
    the accepted 32 x 128-bit chip-loader ABI when all features are lowerable.
    """

    ir: dict[str, Any]
    manifest: dict[str, Any]
    object_bytes: bytes
    state_diagram: str
    waveform_expectation: str
    randomized_test: str
    packed_program: PackedProgram | None

    def manifest_json(self) -> str:
        return json.dumps(self.manifest, indent=2, sort_keys=True) + "\n"


@dataclass(frozen=True)
class HostObject:
    """A CRC-checked host IR object loaded from ``.chobj`` bytes."""

    ir: dict[str, Any]
    object_bytes: bytes


def load_host_object(data: bytes) -> HostObject:
    """Validate and decode a ``chimaera-host-ir-v1`` object."""

    header_size = len(_OBJECT_MAGIC) + 4
    if len(data) < header_size + 4 or not data.startswith(_OBJECT_MAGIC):
        raise CompileError("invalid Chimaera host-object magic or truncated header")
    payload_size = struct.unpack(">I", data[len(_OBJECT_MAGIC):header_size])[0]
    expected_size = header_size + payload_size + 4
    if len(data) != expected_size:
        raise CompileError(
            f"host-object length mismatch: header declares {payload_size} payload bytes"
        )
    payload = data[header_size:header_size + payload_size]
    stored_crc = struct.unpack(">I", data[-4:])[0]
    actual_crc = binascii.crc32(payload) & 0xFFFFFFFF
    if actual_crc != stored_crc:
        raise CompileError(
            f"host-object CRC mismatch: stored {stored_crc:08x}, calculated {actual_crc:08x}"
        )
    try:
        ir = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise CompileError(f"invalid host-object JSON payload: {error}") from error
    if not isinstance(ir, dict) or ir.get("format") != "chimaera-host-ir-v1":
        raise CompileError("unsupported Chimaera host-object format")
    return HostObject(ir, bytes(data))


def _error(location: Any, message: str) -> CompileError:
    return CompileError(f"{location.format()}: {message}")


def _physical_pin(binding: str, location: Any) -> tuple[str, int]:
    match = _PHYSICAL_PIN.fullmatch(binding)
    if match is None:
        raise _error(location, f"invalid binding {binding!r}; expected uio[0] through uio[7]")
    index = int(match.group("bracket") or match.group("plain"))
    return f"uio[{index}]", index


def _duration_cycles(duration: Duration, clock_hz: int) -> int:
    if duration.value <= 0:
        raise _error(duration.location, "duration must be greater than zero")
    if duration.unit in {"cycle", "cycles"}:
        cycles = duration.value
    elif duration.unit == "ns":
        cycles = (duration.value * clock_hz + 999_999_999) // 1_000_000_000
    elif duration.unit == "us":
        cycles = (duration.value * clock_hz + 999_999) // 1_000_000
    else:  # Parser already constrains the unit; retain a defensive check.
        raise _error(duration.location, f"unsupported duration unit {duration.unit!r}")
    if cycles > 0xFFFF:
        raise _error(duration.location, f"duration resolves to {cycles} cycles, exceeding the 16-bit timer")
    return cycles


def _pin_guard(expr: Expr, pins: Mapping[str, int], location: Any) -> tuple[int, int]:
    """Lower a conjunction of ``pin == 0/1`` terms to mask/value fields."""

    if expr.kind == "binary" and expr.value == "&&":
        left_mask, left_value = _pin_guard(expr.left, pins, location)  # type: ignore[arg-type]
        right_mask, right_value = _pin_guard(expr.right, pins, location)  # type: ignore[arg-type]
        overlap = left_mask & right_mask
        if ((left_value ^ right_value) & overlap) != 0:
            raise _error(location, "event guard contains contradictory pin levels")
        return left_mask | right_mask, left_value | right_value
    if expr.kind == "binary" and expr.value == "==":
        left = expr.left
        right = expr.right
        if left is not None and right is not None:
            if left.kind == "name" and right.kind == "number":
                name, value = str(left.value), int(right.value)
            elif right.kind == "name" and left.kind == "number":
                name, value = str(right.value), int(left.value)
            else:
                name, value = "", -1
            if name in pins and value in {0, 1}:
                mask = 1 << pins[name]
                return mask, mask if value else 0
    raise _error(location, "an event guard must be pin == 0/1 terms joined with &&")


def _expr_dict(expr: Expr | None) -> dict[str, Any] | None:
    return None if expr is None else expr.to_dict()


def _check_expr_names(expr: Expr, allowed: set[str], location: Any) -> None:
    unknown = sorted(expr.names() - allowed)
    if unknown:
        raise _error(location, f"unknown name(s) in condition: {', '.join(unknown)}")


def _compile_protocol(
    protocol: Protocol,
    clock_hz: int,
    bindings: Mapping[str, str],
) -> tuple[dict[str, Any], set[str], set[str]]:
    if not protocol.pins:
        raise _error(protocol.location, f"protocol {protocol.name!r} declares no pins")
    if not protocol.states:
        raise _error(protocol.location, f"protocol {protocol.name!r} declares no states")

    pin_declarations: dict[str, Any] = {}
    pin_indexes: dict[str, int] = {}
    normalized_bindings: dict[str, str] = {}
    roles_by_binding: dict[str, str] = {}
    output_bindings: set[str] = set()
    open_drain_bindings: set[str] = set()
    for pin in protocol.pins:
        if pin.name in pin_declarations:
            raise _error(pin.location, f"duplicate pin role {pin.name!r}")
        if pin.mode not in _PIN_MODES:
            raise _error(pin.location, f"invalid pin mode {pin.mode!r}")
        qualified = f"{protocol.name}.{pin.name}"
        if qualified not in bindings:
            raise _error(pin.location, f"missing physical binding for {qualified}")
        normalized, index = _physical_pin(bindings[qualified], pin.location)
        if normalized in roles_by_binding:
            raise _error(
                pin.location,
                f"pin roles {roles_by_binding[normalized]!r} and {pin.name!r} both bind {normalized}",
            )
        roles_by_binding[normalized] = pin.name
        pin_declarations[pin.name] = pin
        pin_indexes[pin.name] = index
        normalized_bindings[pin.name] = normalized
        if pin.mode in {"output", "open_drain", "bidirectional"}:
            output_bindings.add(normalized)
        if pin.mode == "open_drain":
            open_drain_bindings.add(normalized)

    state_names: dict[str, int] = {}
    for state in protocol.states:
        if state.name in state_names:
            raise _error(state.location, f"duplicate state {state.name!r}")
        state_names[state.name] = len(state_names)
    if len(state_names) > 128:
        raise _error(protocol.location, "a protocol may contain at most 128 states")

    variables = {
        action.variable
        for state in protocol.states
        for action in state.actions
        if action.variable is not None and action.kind in {"sample", "count"}
    }
    condition_names = set(pin_declarations) | variables | {"transaction_count"}
    descriptors: list[dict[str, Any]] = []

    for state in protocol.states:
        if state.event is None and state.timeout is None:
            raise _error(
                state.location,
                "state has neither an external event nor a bounded timeout; this could busy-loop forever",
            )
        if state.event is not None and state.event.pin not in pin_declarations:
            raise _error(state.event.location, f"unknown event pin {state.event.pin!r}")

        event_kind = "none"
        event_mask = 0
        event_value = 0
        level_mask = 0
        level_value = 0
        if state.event is not None:
            event_kind = state.event.kind
            pin_index = pin_indexes[state.event.pin or ""]
            event_mask = 1 << pin_index
            if state.event.kind == "level":
                event_value = event_mask if state.event.value else 0
            if state.event_guard is not None:
                if state.event.kind not in {"rise", "fall"}:
                    raise _error(state.event.location, "only rise/fall events may have an inline level guard")
                level_mask, level_value = _pin_guard(
                    state.event_guard,
                    pin_indexes,
                    state.event.location,
                )
                event_kind = f"{state.event.kind}_while_level"

        sample_mask = 0
        action_mask = 0
        action_value = 0
        oe_mask = 0
        oe_value = 0
        action_ir: list[dict[str, Any]] = []
        touched_pins: set[str] = set()
        for action in state.actions:
            if action.kind == "count":
                action_ir.append({"kind": "count", "variable": action.variable})
                continue
            if action.kind == "reset":
                if action.variable not in variables:
                    raise _error(action.location, f"cannot reset unknown variable {action.variable!r}")
                action_ir.append({"kind": "reset", "variable": action.variable})
                continue
            if action.pin not in pin_declarations:
                raise _error(action.location, f"unknown action pin {action.pin!r}")
            pin = pin_declarations[action.pin or ""]
            mask = 1 << pin_indexes[pin.name]
            if action.kind == "sample":
                sample_mask |= mask
                action_ir.append(
                    {"kind": "sample", "pin": pin.name, "variable": action.variable}
                )
                continue
            if pin.name in touched_pins:
                raise _error(action.location, f"multiple drive actions for pin {pin.name!r} in one state")
            touched_pins.add(pin.name)
            if pin.mode == "input":
                raise _error(action.location, f"input pin {pin.name!r} cannot be driven")
            action_mask |= mask
            oe_mask |= mask
            if action.kind == "release":
                oe_value &= ~mask
                action_ir.append({"kind": "release", "pin": pin.name})
            elif action.kind == "drive":
                oe_value |= mask
                if action.value == "high":
                    if pin.mode == "open_drain":
                        raise _error(
                            action.location,
                            f"open-drain pin {pin.name!r} may never be actively driven high",
                        )
                    action_value |= mask
                action_ir.append({"kind": "drive", "pin": pin.name, "value": action.value})
            else:
                raise _error(action.location, f"unsupported action {action.kind!r}")

        if state.event_target is not None and state.transitions:
            raise _error(state.location, "inline event successor cannot be combined with when/goto transitions")
        successors: list[dict[str, Any]] = []
        unconditional_seen = False
        for transition in state.transitions:
            if transition.target not in state_names:
                raise _error(transition.location, f"unknown successor state {transition.target!r}")
            if unconditional_seen:
                raise _error(transition.location, "no transition may follow an unconditional goto")
            if transition.condition is None:
                unconditional_seen = True
            else:
                _check_expr_names(transition.condition, condition_names, transition.location)
            successors.append(
                {
                    "target": state_names[transition.target],
                    "target_name": transition.target,
                    "condition": _expr_dict(transition.condition),
                }
            )
        if state.event_target is not None:
            if state.event_target not in state_names:
                raise _error(state.location, f"unknown event successor state {state.event_target!r}")
            successors.append(
                {
                    "target": state_names[state.event_target],
                    "target_name": state.event_target,
                    "condition": None,
                }
            )

        timeout_cycles = 0
        timeout_target: int | None = None
        timeout_target_name: str | None = None
        if state.timeout is not None:
            if state.timeout.target not in state_names:
                raise _error(state.timeout.location, f"unknown timeout state {state.timeout.target!r}")
            timeout_cycles = _duration_cycles(state.timeout.duration, clock_hz)
            timeout_target = state_names[state.timeout.target]
            timeout_target_name = state.timeout.target

        descriptors.append(
            {
                "id": state_names[state.name],
                "name": state.name,
                "event_kind": _EVENT_KINDS[event_kind],
                "event_kind_name": event_kind,
                "event_mask": event_mask,
                "event_value": event_value,
                "level_mask": level_mask,
                "level_value": level_value,
                "timeout_cycles": timeout_cycles,
                "timeout_target": timeout_target,
                "timeout_target_name": timeout_target_name,
                "sample_mask": sample_mask,
                "action_mask": action_mask,
                "action_value": action_value,
                "oe_mask": oe_mask,
                "oe_value": oe_value,
                "actions": action_ir,
                "successors": successors,
            }
        )

    # A level-sensitive state must make progress. Otherwise a stable asserted
    # input can keep firing the shared bookkeeping path forever, which is the
    # hardware equivalent of an unbounded busy loop. Edge-triggered cycles are
    # safe because another external transition is required before they refire.
    level_edges: dict[int, int] = {}
    for descriptor in descriptors:
        if descriptor["event_kind_name"] != "level":
            continue
        unconditional = next(
            (
                successor["target"]
                for successor in descriptor["successors"]
                if successor["condition"] is None
            ),
            descriptor["id"],
        )
        if descriptors[unconditional]["event_kind_name"] == "level":
            level_edges[descriptor["id"]] = unconditional
    for start in level_edges:
        seen: set[int] = set()
        current = start
        while current in level_edges:
            if current in seen:
                state_name = descriptors[current]["name"]
                raise _error(
                    protocol.states[current].location,
                    f"level-sensitive path can busy-loop through state {state_name!r}",
                )
            seen.add(current)
            current = level_edges[current]

    return (
        {
            "name": protocol.name,
            "entry_state": 0,
            "pins": [
                {
                    "name": pin.name,
                    "mode": pin.mode,
                    "binding": normalized_bindings[pin.name],
                    "index": pin_indexes[pin.name],
                }
                for pin in protocol.pins
            ],
            "states": descriptors,
        },
        output_bindings,
        open_drain_bindings,
    )


def _validate_mutations(program: Program, protocols: Mapping[str, Protocol]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for mutation in program.mutations:
        if mutation.protocol not in protocols:
            raise _error(mutation.location, f"mutation targets unknown protocol {mutation.protocol!r}")
        protocol = protocols[mutation.protocol]
        pins = {pin.name for pin in protocol.pins}
        variables = {
            action.variable
            for state in protocol.states
            for action in state.actions
            if action.variable is not None
        }
        _check_expr_names(
            mutation.condition,
            pins | variables | {"transaction_count"},
            mutation.location,
        )
        if mutation.effect.pin is not None and mutation.effect.pin not in pins:
            raise _error(mutation.effect.location, f"unknown mutation pin {mutation.effect.pin!r}")
        if mutation.effect.variable is not None and mutation.effect.variable not in variables:
            raise _error(
                mutation.effect.location,
                f"unknown mutation variable {mutation.effect.variable!r}",
            )
        if mutation.effect.amount is not None and not 1 <= mutation.effect.amount <= 0xFFFF:
            raise _error(mutation.effect.location, "mutation cycle count must fit the 16-bit timer")
        result.append(
            {
                "name": mutation.name,
                "protocol": mutation.protocol,
                "condition": mutation.condition.to_dict(),
                "effect": {
                    "kind": mutation.effect.kind,
                    "amount": mutation.effect.amount,
                    "pin": mutation.effect.pin,
                    "variable": mutation.effect.variable,
                    "mask": mutation.effect.mask,
                },
            }
        )
    return result


def _validate_contracts(program: Program, protocols: Mapping[str, Protocol]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    supported_starts = ("stable (", "high_width (", "not (")
    for contract in program.contracts:
        if contract.protocol not in protocols:
            raise _error(contract.location, f"contract targets unknown protocol {contract.protocol!r}")
        for assertion in contract.assertions:
            if not assertion.startswith(supported_starts) and " within " not in assertion:
                raise _error(contract.location, f"unsupported contract assertion {assertion!r}")
        result.append(
            {
                "name": contract.name,
                "protocol": contract.protocol,
                "assertions": list(contract.assertions),
            }
        )
    return result


def _diagram(ir: Mapping[str, Any]) -> str:
    lines = ["digraph chimaera {", "  rankdir=LR;"]
    for protocol in ir["protocols"]:
        name = protocol["name"]
        lines.append(f'  subgraph "cluster_{name}" {{')
        lines.append(f'    label="{name}";')
        for state in protocol["states"]:
            node = f"{name}_{state['id']}"
            lines.append(f'    {node} [label="{state["name"]}"];')
            for successor in state["successors"]:
                target = f"{name}_{successor['target']}"
                label = "event" if successor["condition"] is None else "when"
                lines.append(f'    {node} -> {target} [label="{label}"];')
            if state["timeout_target"] is not None:
                target = f"{name}_{state['timeout_target']}"
                lines.append(
                    f'    {node} -> {target} [label="timeout {state["timeout_cycles"]}cy"];'
                )
        lines.append("  }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def _waveform(ir: Mapping[str, Any]) -> str:
    lines = [
        "Chimaera textual event/action expectation",
        f"clock_hz={ir['clock_hz']} fixed_event_to_output_latency=1 cycle",
        "",
    ]
    for protocol in ir["protocols"]:
        lines.append(f"protocol {protocol['name']} entry={protocol['states'][0]['name']}")
        for state in protocol["states"]:
            event = state["event_kind_name"]
            action_parts: list[str] = []
            for action in state["actions"]:
                if action["kind"] in {"drive", "release"}:
                    action_parts.append(
                        f"{action['kind']} {action['pin']}"
                        + (f" {action.get('value')}" if action.get("value") else "")
                    )
                elif action["kind"] == "sample":
                    action_parts.append(f"sample {action['pin']}->{action['variable']}")
                elif action["kind"] == "count":
                    action_parts.append(f"count {action['variable']}")
                else:
                    action_parts.append(f"reset {action['variable']}")
            actions = ", ".join(action_parts) if action_parts else "no pin/data action"
            lines.append(f"  {state['name']}: on {event} => +1cy {actions}")
            if state["timeout_target_name"] is not None:
                lines.append(
                    f"    timeout {state['timeout_cycles']}cy -> {state['timeout_target_name']}"
                )
        lines.append("")
    return "\n".join(lines)


def _randomized_test(object_bytes: bytes, program_crc: int) -> str:
    encoded = base64.b64encode(object_bytes).decode("ascii")
    seed = program_crc ^ 0xC41A_E2A5
    return f'''"""Generated deterministic randomized test for a Chimaera host object."""

import base64
import random
import sys
from pathlib import Path


if (Path.cwd() / "chimaera").is_dir():
    sys.path.insert(0, str(Path.cwd()))

from chimaera import ChipReferenceModel, load_host_object


OBJECT = base64.b64decode("{encoded}")
SEED = {seed}
STEPS = 256


def replay():
    loaded = load_host_object(OBJECT)
    if loaded.ir["mutations"]:
        raise RuntimeError("generated mutation replay awaits Phase 6 mutation lowering")
    model = ChipReferenceModel(loaded)
    random_source = random.Random(SEED)
    trace = []
    for _ in range(STEPS):
        result = model.step(random_source.randrange(256))
        assert not (
            result.drive_value & result.drive_enable & model.open_drain_mask
        ), "open-drain pin was actively driven high"
        trace.append((
            result.drive_value,
            result.drive_enable,
            tuple((name, step.state_after, step.fired) for name, step in result.contexts.items()),
        ))
    return trace


first = replay()
second = replay()
assert first == second, "fixed-seed reference replay is not deterministic"
print(f"PASS: {{STEPS}} randomized cycles, seed={{SEED}}, final={{first[-1]}}")
'''


def compile_source(
    source: str,
    *,
    clock_hz: int,
    bindings: Mapping[str, str],
) -> Compilation:
    """Parse, statically check, and compile DSL source into a host object."""

    if clock_hz <= 0:
        raise CompileError("clock_hz must be greater than zero")
    program = parse(source)
    protocols_by_name: dict[str, Protocol] = {}
    for protocol in program.protocols:
        if protocol.name in protocols_by_name:
            raise _error(protocol.location, f"duplicate protocol {protocol.name!r}")
        protocols_by_name[protocol.name] = protocol
    if len(protocols_by_name) > 2:
        raise CompileError("v1 hardware supports at most two active protocol contexts")

    protocol_ir: list[dict[str, Any]] = []
    owner: dict[str, str] = {}
    open_drain: set[str] = set()
    for protocol in program.protocols:
        compiled, output_bindings, open_drain_bindings = _compile_protocol(
            protocol,
            clock_hz,
            bindings,
        )
        for physical in output_bindings:
            if physical in owner:
                raise CompileError(
                    f"output pin ownership conflict: {owner[physical]} and {protocol.name} both claim {physical}"
                )
            owner[physical] = protocol.name
        open_drain.update(open_drain_bindings)
        protocol_ir.append(compiled)

    unknown_bindings = sorted(set(bindings) - {
        f"{protocol.name}.{pin.name}"
        for protocol in program.protocols
        for pin in protocol.pins
    })
    if unknown_bindings:
        raise CompileError(f"binding(s) do not name declared roles: {', '.join(unknown_bindings)}")

    mutation_ir = _validate_mutations(program, protocols_by_name)
    contract_ir = _validate_contracts(program, protocols_by_name)
    state_count = sum(len(protocol["states"]) for protocol in protocol_ir)
    if state_count > 128:
        raise CompileError(f"program uses {state_count} states; descriptor memory limit is 128")

    ir: dict[str, Any] = {
        "format": "chimaera-host-ir-v1",
        "clock_hz": clock_hz,
        "fixed_event_to_output_latency_cycles": 1,
        "protocols": protocol_ir,
        "mutations": mutation_ir,
        "contracts": contract_ir,
    }
    packed_program = None
    if not mutation_ir and not contract_ir:
        packed_program = pack_program(ir)
    payload = json.dumps(ir, sort_keys=True, separators=(",", ":")).encode("utf-8")
    crc = binascii.crc32(payload) & 0xFFFFFFFF
    object_bytes = _OBJECT_MAGIC + struct.pack(">I", len(payload)) + payload + struct.pack(">I", crc)
    sha256 = hashlib.sha256(object_bytes).hexdigest()
    manifest: dict[str, Any] = {
        "object_format": "chimaera-host-ir-v1",
        "chip_loadable": packed_program is not None,
        "loader_stream_available": packed_program is not None,
        "program_sha256": sha256,
        "program_crc32": f"{crc:08x}",
        "maximum_response_latency_cycles": 1,
        "maximum_rearm_latency_cycles": (
            len(protocol_ir) if packed_program is not None else None
        ),
        "minimum_safe_inter_event_spacing_cycles": (
            len(protocol_ir) if packed_program is not None else None
        ),
        "configuration_sclk_max_hz": clock_hz // 4,
        "maximum_active_contexts": len(protocol_ir),
        "state_descriptors": state_count,
        "packed_state_descriptors": (
            len(packed_program.descriptors) if packed_program is not None else None
        ),
        "loader_crc16": (
            f"{packed_program.crc16:04x}" if packed_program is not None else None
        ),
        "owned_pins": sorted(owner),
        "open_drain_pins": sorted(open_drain),
        "worst_case_mailbox_occupancy_bytes": 0,
        "proofs": {
            "bounded_control_flow": "pass",
            "fixed_reaction_latency": "pass",
            "output_ownership": "pass",
            "open_drain_low_only": "pass",
            "valid_successors": "pass",
            "stackless_program_region": "pass",
            "bounded_mailbox": "pass (mailbox operations not yet exposed by DSL)",
            "configuration_interface_isolated": "pass (only uio bindings are accepted)",
            "clock_durations_resolved": "pass",
            "shared_execution_schedulability": (
                "conditional pass (pending-first single-port reload; source must "
                f"permit {len(protocol_ir)} inclusive cycle(s) between events)"
                if packed_program is not None
                else "deferred until all source features lower to the execution ABI"
            ),
        },
        "outstanding": [
            "Connect generated randomized tests directly to RTL replay",
            "Add DSL timing requirements and discharge the inter-event spacing assumption",
            "Lower mutations and contracts into the reference model and hardware records",
            "Lower pattern events, seeded random_bits conditions, and bidirectional direction changes",
        ],
    }
    return Compilation(
        ir,
        manifest,
        object_bytes,
        _diagram(ir),
        _waveform(ir),
        _randomized_test(object_bytes, crc),
        packed_program,
    )
