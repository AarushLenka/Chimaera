"""Lower checked host IR into the accepted 32 x 128-bit descriptor ABI."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from .errors import CompileError


MAX_DESCRIPTORS = 32
DESCRIPTOR_BITS = 128
WORDS_PER_DESCRIPTOR = 8

OP_BEGIN = 0x0
OP_WRITE_DESCRIPTOR = 0x1
OP_SET_CONTEXT = 0x2
OP_CONTROL = 0x3
OP_SET_PIN_MODES = 0x4
OP_SET_FAULT_SEED = 0x5
OP_WRITE_MUTATION = 0x6
OP_WRITE_CONTRACT = 0x7
OP_COMMIT = 0xE

EVENT_LEVEL = 3
SERIAL_NONE = 0
SERIAL_SAMPLE_LEFT = 1


class PackingError(CompileError):
    """The checked host IR uses a feature not representable by this ABI."""


@dataclass(frozen=True)
class PackedProgram:
    descriptors: tuple[int, ...]
    context_entries: tuple[int, ...]
    open_drain_mask: int
    crc16: int
    fault_seed: int
    mutation_config: tuple[int, int]
    contract_config: tuple[int, int]
    loader_frames: tuple[int, ...]

    @property
    def loader_bytes(self) -> bytes:
        return b"".join(frame.to_bytes(4, "big") for frame in self.loader_frames)

    @property
    def descriptor_bytes(self) -> bytes:
        result = bytearray()
        for descriptor in self.descriptors:
            for word_index in range(WORDS_PER_DESCRIPTOR):
                word = (descriptor >> (word_index * 16)) & 0xFFFF
                result.extend(word.to_bytes(2, "big"))
        return bytes(result)


def crc16_ccitt(data: bytes, initial: int = 0xFFFF) -> int:
    crc = initial
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def _frame(
    opcode: int,
    *,
    context: int = 0,
    address: int = 0,
    word: int = 0,
    data: int = 0,
) -> int:
    return (
        ((opcode & 0xF) << 28)
        | ((context & 0x1) << 27)
        | ((address & 0x1F) << 22)
        | ((word & 0x7) << 19)
        | (data & 0xFFFF)
    )


def _protocol_variables(protocol: Mapping[str, Any]) -> tuple[str | None, str | None]:
    shift_variables = {
        action["variable"]
        for state in protocol["states"]
        for action in state["actions"]
        if action["kind"] == "sample"
    }
    count_variables = {
        action["variable"]
        for state in protocol["states"]
        for action in state["actions"]
        if action["kind"] == "count"
    }
    if len(shift_variables) > 1:
        raise PackingError(
            f"protocol {protocol['name']!r} uses multiple sampled variables; v1 ABI has one shift register"
        )
    if len(count_variables) > 1:
        raise PackingError(
            f"protocol {protocol['name']!r} uses multiple counters; v1 ABI has one counter"
        )
    shift_name = next(iter(shift_variables), None)
    count_name = next(iter(count_variables), None)
    if shift_name is not None and shift_name == count_name:
        raise PackingError("one variable cannot be both the shift register and counter")
    return shift_name, count_name


def _condition_fields(
    expression: Mapping[str, Any] | None,
    *,
    shift_variable: str | None,
    count_variable: str | None,
) -> tuple[int, int, int, int]:
    """Return count-enable/value and shift-enable/value for an AND expression."""

    if expression is None:
        return 0, 0, 0, 0
    terms: list[Mapping[str, Any]] = []

    def flatten(node: Mapping[str, Any]) -> None:
        if node["kind"] == "binary" and node.get("value") == "&&":
            flatten(node["left"])
            flatten(node["right"])
        else:
            terms.append(node)

    flatten(expression)
    count_enable = 0
    count_value = 0
    shift_enable = 0
    shift_value = 0
    for term in terms:
        if term["kind"] != "binary" or term.get("value") != "==":
            raise PackingError("descriptor conditions support only equality terms joined by &&")
        left = term["left"]
        right = term["right"]
        if left["kind"] == "name" and right["kind"] == "number":
            name, value = str(left["value"]), int(right["value"])
        elif right["kind"] == "name" and left["kind"] == "number":
            name, value = str(right["value"]), int(left["value"])
        else:
            raise PackingError("descriptor equality must compare a variable with an integer")
        if name == count_variable:
            if count_enable and count_value != value:
                raise PackingError("condition compares the counter with conflicting values")
            if not 0 <= value <= 0xF:
                raise PackingError("counter comparison does not fit four ABI bits")
            count_enable, count_value = 1, value
        elif name == shift_variable:
            if shift_enable and shift_value != value:
                raise PackingError("condition compares the shift register with conflicting values")
            if not 0 <= value <= 0xFF:
                raise PackingError("shift comparison does not fit eight ABI bits")
            shift_enable, shift_value = 1, value
        else:
            raise PackingError(f"condition variable {name!r} has no v1 execution-engine register")
    return count_enable, count_value, shift_enable, shift_value


def _pack_descriptor(fields: Mapping[str, int]) -> int:
    descriptor = 0
    layout = (
        ("event_kind", 0, 3),
        ("event_mask", 3, 8),
        ("event_value", 11, 8),
        ("level_mask", 19, 8),
        ("level_value", 27, 8),
        ("timeout_cycles", 35, 16),
        ("sample_mask", 51, 8),
        ("action_mask", 59, 8),
        ("action_value", 67, 8),
        ("oe_mask", 75, 8),
        ("oe_value", 83, 8),
        ("true_target", 91, 5),
        ("false_target", 96, 5),
        ("timeout_target", 101, 5),
        ("condition_count_enable", 106, 1),
        ("condition_count_value", 107, 4),
        ("condition_shift_enable", 111, 1),
        ("shift_literal", 112, 8),
        ("count_increment", 120, 1),
        ("count_reset", 121, 1),
        ("shift_reset", 122, 1),
        ("shift_load", 123, 1),
        ("serial_mode", 124, 2),
    )
    for name, offset, width in layout:
        value = int(fields.get(name, 0))
        if not 0 <= value < (1 << width):
            raise PackingError(f"descriptor field {name}={value} does not fit {width} bits")
        descriptor |= value << offset
    return descriptor


def _mutation_condition(expression: Mapping[str, Any]) -> tuple[str, int]:
    if expression.get("kind") != "binary" or expression.get("value") != "==":
        raise PackingError(
            "Phase 6 mutation conditions currently support one variable == integer term"
        )
    left = expression.get("left")
    right = expression.get("right")
    if not isinstance(left, Mapping) or not isinstance(right, Mapping):
        raise PackingError("mutation equality must compare a variable with an integer")
    if left.get("kind") == "name" and right.get("kind") == "number":
        return str(left["value"]), int(right["value"])
    if right.get("kind") == "name" and left.get("kind") == "number":
        return str(right["value"]), int(left["value"])
    raise PackingError("mutation equality must compare a variable with an integer")


def _pack_mutations(
    ir: Mapping[str, Any],
    protocols: list[Mapping[str, Any]],
    variables: Mapping[str, tuple[str | None, str | None]],
) -> tuple[int, tuple[int, int]]:
    """Pack the first hardware mutation slice into two-context fault tables.

    Each context has four 32-bit records, represented as two 16-bit loader
    words. The low byte is a deterministic LFSR threshold for data/action
    effects. Pin-targeted effects use its low three bits as the physical pin
    index; those effects are deterministic and do not consume a random gate.
    """

    seed = int(ir.get("fault_seed", 1))
    if not 1 <= seed <= 0xFFFF:
        raise PackingError("fault seed must be a non-zero 16-bit value")
    protocol_index = {str(protocol["name"]): index for index, protocol in enumerate(protocols)}
    records = [[0 for _ in range(4)] for _ in protocols]
    for mutation in ir.get("mutations", []):
        protocol_name = str(mutation["protocol"])
        context = protocol_index[protocol_name]
        slots = records[context]
        slot = next((index for index, value in enumerate(slots) if value == 0), None)
        if slot is None:
            raise PackingError(
                f"protocol {protocol_name!r} exceeds the four-record mutation table"
            )
        effect = mutation["effect"]
        effect_kind = str(effect.get("kind"))
        effect_codes = {
            "flip_bits": 1,
            "delay": 2,
            "nack": 3,
            "drop_byte": 4,
            "hold_low": 5,
            "duplicate_edge": 6,
            "late_release": 7,
        }
        if effect_kind not in effect_codes:
            raise PackingError(f"unsupported mutation effect {effect_kind!r}")
        shift_variable, _ = variables[protocol_name]
        if effect_kind == "flip_bits" and (
            shift_variable is None or effect.get("variable") != shift_variable
        ):
            raise PackingError(
                "flip bits mutations must target the protocol's sampled shift variable"
            )
        condition_name, condition_value = _mutation_condition(mutation["condition"])
        if condition_name != shift_variable:
            raise PackingError(
                "mutation conditions must compare the sampled shift variable"
            )
        if not 0 <= condition_value <= 0xFF:
            raise PackingError("mutation condition value must fit eight bits")
        amount = int(effect.get("amount") or 0)
        if effect_kind == "flip_bits":
            mask = int(effect.get("mask") or 0)
            if not 1 <= mask <= 0xFF:
                raise PackingError("flip bits mutation mask must fit a non-zero byte")
            effect_code = effect_codes[effect_kind]
            effect_payload = mask
            threshold = 0xFF
        elif effect_kind == "delay":
            if not 1 <= amount <= 0xFF:
                raise PackingError("delay mutation amount must fit one to 255 cycles")
            effect_code = effect_codes[effect_kind]
            effect_payload = amount
            threshold = 0xFF
        elif effect_kind in {"nack", "drop_byte"}:
            effect_code = effect_codes[effect_kind]
            effect_payload = 0
            threshold = 0
        else:
            pin_name = effect.get("pin")
            pin_index = next(
                (
                    int(pin["index"])
                    for pin in protocols[context]["pins"]
                    if pin["name"] == pin_name
                ),
                None,
            )
            if pin_index is None:
                raise PackingError(f"mutation pin {pin_name!r} has no physical binding")
            if effect_kind == "hold_low":
                if not 1 <= amount <= 0xFF:
                    raise PackingError("pin hold duration must fit one to 255 cycles")
                effect_payload = amount
            elif effect_kind == "late_release":
                if not 1 <= amount <= 0xFF:
                    raise PackingError("late release duration must fit one to 255 cycles")
                effect_payload = amount
            else:
                effect_payload = 0
            effect_code = effect_codes[effect_kind]
            threshold = pin_index
        # word 0: enable, effect kind, condition kind 1 (shift equality),
        # and the post-sample comparison value.
        word0 = 0x8000 | (effect_code << 12) | (1 << 8) | condition_value
        # word 1: effect payload and either an inclusive LFSR threshold or the
        # physical pin index for a pin-targeted effect.
        word1 = (effect_payload << 8) | threshold
        slots[slot] = (word0 << 16) | word1

    packed = tuple(
        sum(record << (slot * 32) for slot, record in enumerate(context_records))
        for context_records in records
    )
    return seed, (packed[0] if packed else 0, packed[1] if len(packed) > 1 else 0)


def _pack_contracts(
    ir: Mapping[str, Any], protocols: list[Mapping[str, Any]]
) -> tuple[int, int]:
    """Pack four compact temporal-contract records per protocol context.

    Record format (MSB first): enable, kind, two four-bit pin fields, two
    two-bit edge/level fields, and a sixteen-bit cycle bound.  The monitor is
    deliberately separate from the 128-bit reaction descriptor.
    """

    protocol_index = {str(protocol["name"]): index for index, protocol in enumerate(protocols)}
    packed = [[0 for _ in range(4)] for _ in protocols]
    kind_codes = {"stable": 1, "high_width_min": 2, "high_width_max": 3, "event_within": 4, "not": 5}
    edge_codes = {"rise": 1, "fall": 2}
    for contract in ir.get("contracts", []):
        context = protocol_index[str(contract["protocol"])]
        records = packed[context]
        for assertion in contract.get("records", []):
            slot = next((index for index, value in enumerate(records) if value == 0), None)
            if slot is None:
                raise PackingError(
                    f"protocol {contract['protocol']!r} exceeds the four-record contract table"
                )
            kind = str(assertion["kind"])
            if kind not in kind_codes:
                raise PackingError(f"unsupported contract record kind {kind!r}")
            pin_a = int(assertion.get("pin", assertion.get("target_pin", 0)))
            pin_b = int(assertion.get("guard_pin", assertion.get("source_pin", 0)))
            if not 0 <= pin_a <= 0xF or not 0 <= pin_b <= 0xF:
                raise PackingError("contract pin index must fit four bits")
            edge_a = str(assertion.get("target_edge", ""))
            edge_b = str(assertion.get("source_edge", ""))
            edge_a_code = edge_codes.get(edge_a, int(assertion.get("guard_value", assertion.get("value", 0))) & 0x3)
            edge_b_code = edge_codes.get(edge_b, 0)
            duration = int(assertion.get("cycles", 0))
            if not 0 <= duration <= 0xFFFF:
                raise PackingError("contract cycle bound must fit sixteen bits")
            record = (
                (1 << 31)
                | (kind_codes[kind] << 28)
                | (pin_a << 24)
                | (pin_b << 20)
                | (edge_a_code << 18)
                | (edge_b_code << 16)
                | duration
            )
            records[slot] = record
    packed_contexts = tuple(
        sum(record << (slot * 32) for slot, record in enumerate(context_records))
        for context_records in packed
    )
    return (
        packed_contexts[0] if packed_contexts else 0,
        packed_contexts[1] if len(packed_contexts) > 1 else 0,
    )


def pack_program(ir: Mapping[str, Any]) -> PackedProgram:
    """Lower protocol-only IR to loader frames for the fixed descriptor ABI."""

    protocols = list(ir["protocols"])
    if not 1 <= len(protocols) <= 2:
        raise PackingError("the v1 ABI requires one or two protocol contexts")

    variables = {
        protocol["name"]: _protocol_variables(protocol)
        for protocol in protocols
    }
    fault_seed, mutation_config = _pack_mutations(ir, protocols, variables)
    contract_config = _pack_contracts(ir, protocols)
    global_ids: dict[tuple[str, int], int] = {}
    next_id = 0
    for protocol in protocols:
        for state in protocol["states"]:
            global_ids[(protocol["name"], int(state["id"]))] = next_id
            next_id += 1

    helpers: dict[tuple[str, int], list[int]] = {}
    for protocol in protocols:
        for state in protocol["states"]:
            conditional_count = sum(
                successor["condition"] is not None for successor in state["successors"]
            )
            helper_ids: list[int] = []
            for _ in range(max(0, conditional_count - 1)):
                helper_ids.append(next_id)
                next_id += 1
            helpers[(protocol["name"], int(state["id"]))] = helper_ids
    if next_id > MAX_DESCRIPTORS:
        raise PackingError(
            f"program needs {next_id} descriptors after condition lowering; ABI limit is {MAX_DESCRIPTORS}"
        )

    packed: list[int] = [0] * next_id
    for protocol in protocols:
        protocol_name = protocol["name"]
        shift_variable, count_variable = variables[protocol_name]
        for state in protocol["states"]:
            local_id = int(state["id"])
            state_global = global_ids[(protocol_name, local_id)]
            state_helpers = helpers[(protocol_name, local_id)]
            conditional = [item for item in state["successors"] if item["condition"] is not None]
            unconditional = next(
                (item for item in state["successors"] if item["condition"] is None),
                None,
            )
            default_target = (
                global_ids[(protocol_name, int(unconditional["target"]))]
                if unconditional is not None
                else state_global
            )
            timeout_target = (
                global_ids[(protocol_name, int(state["timeout_target"]))]
                if state["timeout_target"] is not None
                else state_global
            )

            action_kinds = {action["kind"] for action in state["actions"]}
            serial_mode = SERIAL_SAMPLE_LEFT if "sample" in action_kinds else SERIAL_NONE
            if serial_mode == SERIAL_SAMPLE_LEFT:
                sample_mask = int(state["sample_mask"])
                if sample_mask == 0 or sample_mask & (sample_mask - 1):
                    raise PackingError("v1 serial sampling requires exactly one sampled pin per state")
            fields = {
                "event_kind": int(state["event_kind"]),
                "event_mask": int(state["event_mask"]),
                "event_value": int(state["event_value"]),
                "level_mask": int(state["level_mask"]),
                "level_value": int(state["level_value"]),
                "timeout_cycles": int(state["timeout_cycles"]),
                "sample_mask": int(state["sample_mask"]),
                "action_mask": int(state["action_mask"]),
                "action_value": int(state["action_value"]),
                "oe_mask": int(state["oe_mask"]),
                "oe_value": int(state["oe_value"]),
                "timeout_target": timeout_target,
                "count_increment": int("count" in action_kinds),
                "count_reset": int(
                    any(
                        action["kind"] == "reset" and action["variable"] == count_variable
                        for action in state["actions"]
                    )
                ),
                "shift_reset": int(
                    any(
                        action["kind"] == "reset" and action["variable"] == shift_variable
                        for action in state["actions"]
                    )
                ),
                "serial_mode": serial_mode,
            }

            chain_ids = [state_global] + state_helpers
            if not conditional:
                fields["true_target"] = default_target
                fields["false_target"] = default_target
                packed[state_global] = _pack_descriptor(fields)
                continue

            for condition_index, successor in enumerate(conditional):
                descriptor_id = chain_ids[condition_index]
                false_target = (
                    chain_ids[condition_index + 1]
                    if condition_index + 1 < len(chain_ids)
                    else default_target
                )
                count_enable, count_value, shift_enable, shift_value = _condition_fields(
                    successor["condition"],
                    shift_variable=shift_variable,
                    count_variable=count_variable,
                )
                condition_fields = {
                    "true_target": global_ids[(protocol_name, int(successor["target"]))],
                    "false_target": false_target,
                    "condition_count_enable": count_enable,
                    "condition_count_value": count_value,
                    "condition_shift_enable": shift_enable,
                    "shift_literal": shift_value,
                }
                if condition_index == 0:
                    descriptor_fields = dict(fields)
                else:
                    descriptor_fields = {
                        "event_kind": EVENT_LEVEL,
                        "true_target": descriptor_id,
                        "false_target": descriptor_id,
                        "timeout_target": descriptor_id,
                    }
                descriptor_fields.update(condition_fields)
                packed[descriptor_id] = _pack_descriptor(descriptor_fields)

    entries = tuple(
        global_ids[(protocol["name"], int(protocol["entry_state"]))]
        for protocol in protocols
    )
    descriptor_bytes = bytearray()
    frames = [_frame(OP_BEGIN)]
    for state_id, descriptor in enumerate(packed):
        for word_index in range(WORDS_PER_DESCRIPTOR):
            word = (descriptor >> (word_index * 16)) & 0xFFFF
            descriptor_bytes.extend(word.to_bytes(2, "big"))
            frames.append(
                _frame(
                    OP_WRITE_DESCRIPTOR,
                    address=state_id,
                    word=word_index,
                    data=word,
                )
            )
    crc = crc16_ccitt(bytes(descriptor_bytes))
    for context, entry in enumerate(entries):
        frames.append(_frame(OP_SET_CONTEXT, context=context, data=0x20 | entry))
    if ir.get("mutations") or fault_seed != 1:
        frames.append(_frame(OP_SET_FAULT_SEED, data=fault_seed))
        for context, config in enumerate(mutation_config):
            for slot in range(4):
                record = (config >> (slot * 32)) & 0xFFFFFFFF
                if record == 0:
                    continue
                frames.append(
                    _frame(
                        OP_WRITE_MUTATION,
                        context=context,
                        address=slot,
                        word=0,
                        data=(record >> 16) & 0xFFFF,
                    )
                )
                frames.append(
                    _frame(
                        OP_WRITE_MUTATION,
                        context=context,
                        address=slot,
                        word=1,
                        data=record & 0xFFFF,
                    )
                )
    for context, config in enumerate(contract_config):
        for slot in range(4):
            record = (config >> (slot * 32)) & 0xFFFFFFFF
            if record == 0:
                continue
            frames.append(
                _frame(
                    OP_WRITE_CONTRACT,
                    context=context,
                    address=slot,
                    word=0,
                    data=(record >> 16) & 0xFFFF,
                )
            )
            frames.append(
                _frame(
                    OP_WRITE_CONTRACT,
                    context=context,
                    address=slot,
                    word=1,
                    data=record & 0xFFFF,
                )
            )
    open_drain_mask = 0
    for protocol in protocols:
        for pin in protocol["pins"]:
            if pin["mode"] == "open_drain":
                open_drain_mask |= 1 << int(pin["index"])
    frames.append(_frame(OP_SET_PIN_MODES, data=open_drain_mask))
    frames.append(
        _frame(
            OP_COMMIT,
            address=len(packed) - 1,
            data=crc,
        )
    )
    frames.append(_frame(OP_CONTROL, data=1))
    return PackedProgram(
        tuple(packed),
        entries,
        open_drain_mask,
        crc,
        fault_seed,
        mutation_config,
        contract_config,
        tuple(frames),
    )
