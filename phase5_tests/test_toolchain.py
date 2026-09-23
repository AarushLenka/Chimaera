from __future__ import annotations

import contextlib
import io
import unittest
from pathlib import Path

from chimaera import (
    ChipReferenceModel,
    CompileError,
    ReferenceModel,
    compile_source,
    crc16_ccitt,
    load_host_object,
    parse,
)


EXAMPLE = Path(__file__).parents[1] / "examples" / "phase5" / "pulse_ack.chi"
I2C_EXAMPLE = Path(__file__).parents[1] / "examples" / "phase5" / "i2c_ack.chi"
LOADER_EXAMPLE = Path(__file__).parents[1] / "examples" / "phase5" / "loader_pulse.chi"
BINDINGS = {
    "pulse_ack.request": "uio[0]",
    "pulse_ack.response": "uio[1]",
}


class ParserTests(unittest.TestCase):
    def test_parses_example_structure(self) -> None:
        program = parse(EXAMPLE.read_text(encoding="utf-8"))
        self.assertEqual([protocol.name for protocol in program.protocols], ["pulse_ack"])
        self.assertEqual([state.name for state in program.protocols[0].states], ["idle", "wait_release"])
        self.assertEqual(program.contracts[0].protocol, "pulse_ack")

    def test_parses_attached_mutation(self) -> None:
        source = EXAMPLE.read_text(encoding="utf-8") + """
mutation delay_every_17th for pulse_ack {
    when requests % 17 == 0
    delay next action by 3 cycles
}
"""
        program = parse(source)
        self.assertEqual(program.mutations[0].effect.kind, "delay")
        self.assertEqual(program.mutations[0].effect.amount, 3)

    def test_drive_release_alias_parses_as_release_action(self) -> None:
        source = """
protocol releaser {
    pin line open_drain
    state idle {
        on rise(line) {
            drive line release
            goto idle
        }
    }
}
"""
        program = parse(source)
        self.assertEqual(program.protocols[0].states[0].actions[0].kind, "release")

    def test_contract_exception_continuations_attach_to_assertion(self) -> None:
        source = EXAMPLE.read_text(encoding="utf-8") + """
contract stable_request for pulse_ack {
    assert stable(request) while response == 1
        except start_condition
        except stop_condition
}
"""
        program = parse(source)
        assertion = program.contracts[-1].assertions[0]
        self.assertIn("except start_condition except stop_condition", assertion)


class CompilerTests(unittest.TestCase):
    def compile_example(self):
        return compile_source(
            EXAMPLE.read_text(encoding="utf-8"),
            clock_hz=50_000_000,
            bindings=BINDINGS,
        )

    def test_emits_deterministic_proof_manifest_and_host_object(self) -> None:
        first = self.compile_example()
        second = self.compile_example()
        self.assertEqual(first.object_bytes, second.object_bytes)
        self.assertTrue(first.object_bytes.startswith(b"CHOBJ\x00\x01"))
        self.assertFalse(first.manifest["chip_loadable"])
        self.assertEqual(first.manifest["maximum_response_latency_cycles"], 1)
        self.assertEqual(first.manifest["owned_pins"], ["uio[1]"])
        self.assertEqual(first.manifest["proofs"]["open_drain_low_only"], "pass")
        self.assertIn('pulse_ack_0 [label="idle"]', first.state_diagram)
        self.assertIn("+1cy drive response high", first.waveform_expectation)

    def test_host_object_round_trip_and_crc_validation(self) -> None:
        compilation = self.compile_example()
        loaded = load_host_object(compilation.object_bytes)
        self.assertEqual(loaded.ir, compilation.ir)

        corrupted = bytearray(compilation.object_bytes)
        corrupted[-5] ^= 0x01
        with self.assertRaisesRegex(CompileError, "CRC mismatch"):
            load_host_object(bytes(corrupted))

    def test_generated_randomized_model_test_replays_deterministically(self) -> None:
        compilation = self.compile_example()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exec(compilation.randomized_test, {"__name__": "__generated_test__"})
        self.assertIn("PASS: 256 randomized cycles", output.getvalue())

    def test_resolves_physical_time_to_clock_cycles(self) -> None:
        source = """
protocol timed {
    pin line input
    state wait {
        on rise(line) -> wait
        within 100 ns else -> wait
    }
}
"""
        compilation = compile_source(
            source,
            clock_hz=50_000_000,
            bindings={"timed.line": "uio[3]"},
        )
        self.assertEqual(compilation.ir["protocols"][0]["states"][0]["timeout_cycles"], 5)

    def test_packs_protocol_into_fixed_descriptor_loader_frames(self) -> None:
        compilation = compile_source(
            LOADER_EXAMPLE.read_text(encoding="utf-8"),
            clock_hz=50_000_000,
            bindings={
                "loader_pulse.request": "uio[0]",
                "loader_pulse.response": "uio[1]",
            },
        )
        packed = compilation.packed_program
        self.assertIsNotNone(packed)
        assert packed is not None
        self.assertTrue(compilation.manifest["chip_loadable"])
        self.assertEqual(compilation.manifest["maximum_rearm_latency_cycles"], 1)
        self.assertEqual(
            compilation.manifest["minimum_safe_inter_event_spacing_cycles"], 1
        )
        self.assertEqual(compilation.manifest["configuration_sclk_max_hz"], 12_500_000)
        self.assertIn(
            "pending-first",
            compilation.manifest["proofs"]["shared_execution_schedulability"],
        )
        self.assertEqual(len(packed.descriptors), 2)
        self.assertEqual(len(packed.loader_frames), 21)
        self.assertEqual(len(packed.loader_bytes), 84)
        self.assertEqual(crc16_ccitt(packed.descriptor_bytes), packed.crc16)

        idle = packed.descriptors[0]
        self.assertEqual((idle >> 0) & 0x7, 1)  # rising edge
        self.assertEqual((idle >> 3) & 0xFF, 0x01)
        self.assertEqual((idle >> 59) & 0xFF, 0x02)
        self.assertEqual((idle >> 67) & 0xFF, 0x02)
        self.assertEqual((idle >> 75) & 0xFF, 0x02)
        self.assertEqual((idle >> 83) & 0xFF, 0x02)
        self.assertEqual((idle >> 91) & 0x1F, 1)
        self.assertEqual((idle >> 120) & 1, 1)

    def test_condition_chain_lowers_to_helper_descriptor(self) -> None:
        protocol_only = I2C_EXAMPLE.read_text(encoding="utf-8").split("contract", 1)[0]
        compilation = compile_source(
            protocol_only,
            clock_hz=50_000_000,
            bindings={"i2c_ack.sda": "uio[4]", "i2c_ack.scl": "uio[5]"},
        )
        packed = compilation.packed_program
        self.assertIsNotNone(packed)
        assert packed is not None
        self.assertEqual(len(packed.descriptors), 6)

        address = packed.descriptors[1]
        helper = packed.descriptors[5]
        self.assertEqual((address >> 91) & 0x1F, 2)  # matching address -> ACK
        self.assertEqual((address >> 96) & 0x1F, 5)  # otherwise evaluate bits == 8
        self.assertEqual((address >> 106) & 1, 1)
        self.assertEqual((address >> 107) & 0xF, 8)
        self.assertEqual((address >> 111) & 1, 1)
        self.assertEqual((address >> 112) & 0xFF, 0x84)
        self.assertEqual((helper >> 91) & 0x1F, 4)  # wrong completed byte -> ignore
        self.assertEqual((helper >> 96) & 0x1F, 1)  # incomplete byte -> address

    def test_rejects_open_drain_high_drive(self) -> None:
        source = """
protocol unsafe {
    pin sda open_drain
    state idle {
        on fall(sda) {
            drive sda high
            goto idle
        }
    }
}
"""
        with self.assertRaisesRegex(CompileError, "may never be actively driven high"):
            compile_source(source, clock_hz=50_000_000, bindings={"unsafe.sda": "uio[4]"})

    def test_rejects_conflicting_output_ownership(self) -> None:
        source = """
protocol left {
    pin tx output
    state idle { on rise(tx) -> idle }
}
protocol right {
    pin tx output
    state idle { on rise(tx) -> idle }
}
"""
        with self.assertRaisesRegex(CompileError, "ownership conflict"):
            compile_source(
                source,
                clock_hz=50_000_000,
                bindings={"left.tx": "uio[2]", "right.tx": "uio[2]"},
            )

    def test_rejects_invalid_successor(self) -> None:
        source = """
protocol broken {
    pin rx input
    state idle { on rise(rx) -> missing }
}
"""
        with self.assertRaisesRegex(CompileError, "unknown event successor"):
            compile_source(source, clock_hz=50_000_000, bindings={"broken.rx": "uio[0]"})

    def test_rejects_unbounded_internal_state(self) -> None:
        source = """
protocol stuck {
    pin rx input
    state idle { goto idle }
}
"""
        with self.assertRaisesRegex(CompileError, "neither an external event nor a bounded timeout"):
            compile_source(source, clock_hz=50_000_000, bindings={"stuck.rx": "uio[0]"})

    def test_rejects_level_sensitive_busy_loop(self) -> None:
        source = """
protocol stuck_high {
    pin ready input
    state idle { on level(ready, 1) -> idle }
}
"""
        with self.assertRaisesRegex(CompileError, "level-sensitive path can busy-loop"):
            compile_source(
                source,
                clock_hz=50_000_000,
                bindings={"stuck_high.ready": "uio[0]"},
            )


class ReferenceModelTests(unittest.TestCase):
    def test_event_action_and_timeout_are_cycle_exact(self) -> None:
        compilation = compile_source(
            EXAMPLE.read_text(encoding="utf-8"),
            clock_hz=50_000_000,
            bindings=BINDINGS,
        )
        model = ReferenceModel(compilation, "pulse_ack")

        idle = model.step(0x00)
        self.assertFalse(idle.fired)

        edge = model.step(0x01)
        self.assertTrue(edge.fired)
        self.assertEqual((edge.drive_value, edge.drive_enable), (0x02, 0x02))
        self.assertEqual(edge.state_after, "wait_release")
        self.assertEqual(edge.variables["requests"], 1)

        for _ in range(3):
            waiting = model.step(0x01)
            self.assertFalse(waiting.fired)
        timeout = model.step(0x01)
        self.assertTrue(timeout.fired)
        self.assertTrue(timeout.from_timeout)
        self.assertEqual((timeout.drive_value, timeout.drive_enable), (0x00, 0x02))
        self.assertEqual(timeout.state_after, "idle")

    def test_two_context_chip_model_merges_disjoint_outputs(self) -> None:
        source = """
protocol left {
    pin trigger input
    pin response output
    state idle {
        on rise(trigger) {
            drive response high
            goto wait_low
        }
    }
    state wait_low {
        on fall(trigger) {
            drive response low
            goto idle
        }
    }
}
protocol right {
    pin trigger input
    pin response output
    state idle {
        on rise(trigger) {
            drive response high
            goto wait_low
        }
    }
    state wait_low {
        on fall(trigger) {
            drive response low
            goto idle
        }
    }
}
"""
        compilation = compile_source(
            source,
            clock_hz=50_000_000,
            bindings={
                "left.trigger": "uio[0]",
                "left.response": "uio[1]",
                "right.trigger": "uio[4]",
                "right.response": "uio[5]",
            },
        )
        model = ChipReferenceModel(compilation)
        result = model.step(0x11)
        self.assertEqual((result.drive_value, result.drive_enable), (0x22, 0x22))
        self.assertEqual(set(result.contexts), {"left", "right"})
        self.assertEqual(model.pending_context, "right")

        handoff = model.step(0x00)
        self.assertTrue(handoff.contexts["left"].fired)
        self.assertFalse(handoff.contexts["right"].fired)
        self.assertEqual((handoff.drive_value, handoff.drive_enable), (0x20, 0x22))
        self.assertEqual(model.pending_context, "left")

        rearmed = model.step(0x00)
        self.assertFalse(rearmed.contexts["left"].fired)
        self.assertIsNone(model.pending_context)

    def test_i2c_example_recognizes_address_and_drives_low_only_ack(self) -> None:
        compilation = compile_source(
            I2C_EXAMPLE.read_text(encoding="utf-8"),
            clock_hz=50_000_000,
            bindings={"i2c_ack.sda": "uio[4]", "i2c_ack.scl": "uio[5]"},
        )
        self.assertEqual(compilation.manifest["open_drain_pins"], ["uio[4]"])
        model = ReferenceModel(compilation, "i2c_ack")

        sda = 1 << 4
        scl = 1 << 5
        model.step(sda | scl)
        start = model.step(scl)
        self.assertEqual(start.state_after, "address")

        for bit in (1, 0, 0, 0, 0, 1, 0, 0):
            model.step(sda if bit else 0)
            sampled = model.step((sda if bit else 0) | scl)
        self.assertEqual(sampled.variables["address_shift"], 0x84)
        self.assertEqual(sampled.state_after, "ack_low")

        ack = model.step(0)
        self.assertEqual(ack.state_after, "ack_release")
        self.assertEqual((ack.drive_value, ack.drive_enable), (0x00, sda))
        model.step(scl)
        released = model.step(0)
        self.assertEqual(released.state_after, "idle")
        self.assertEqual(released.drive_enable & sda, 0)


if __name__ == "__main__":
    unittest.main()
