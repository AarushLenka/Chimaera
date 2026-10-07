#!/usr/bin/env python3
"""Run the five Phase 6 demo simulations through model and generated RTL."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from chimaera import ChipReferenceModel, Compilation, compile_source, run_runtime_replay


CLOCK_HZ = 50_000_000
EXAMPLES = ROOT / "examples"
_REPLAY_SOURCE_ROOT: Path | None = None


def _compile(
    relative_path: str,
    bindings: dict[str, str],
    *,
    fault_seed: int = 1,
    strip_contracts: bool = False,
) -> Compilation:
    source_path = EXAMPLES / relative_path
    source = source_path.read_text(encoding="utf-8")
    if strip_contracts:
        source = source.split("\ncontract", 1)[0]
    compilation = compile_source(
        source,
        clock_hz=CLOCK_HZ,
        bindings=bindings,
        fault_seed=fault_seed,
    )
    if compilation.packed_program is None:
        raise AssertionError(f"{relative_path} did not lower to the chip-loader ABI")
    return compilation


def _replay(
    compilation: Compilation,
    inputs: Iterable[int],
    *,
    source_root: Path | None = None,
) -> list:
    """Replay synchronized inputs and compare every cycle with generated RTL."""

    source_root = source_root or _REPLAY_SOURCE_ROOT
    model = ChipReferenceModel(compilation)
    previous = 0
    results = []
    rtl_trace = []
    for value in inputs:
        rising = (~previous & value) & 0xFF
        falling = (previous & ~value) & 0xFF
        result = model.step(value)
        context = next(iter(result.contexts.values()))
        results.append(result)
        rtl_trace.append(
            (
                value,
                rising,
                falling,
                context.drive_value,
                context.drive_enable,
                0,
                0,
            )
        )
        previous = value
    assert compilation.packed_program is not None
    output = run_runtime_replay(
        compilation.packed_program,
        rtl_trace,
        source_root=source_root,
    )
    if "PASS: generated runtime replay" not in output:
        raise AssertionError(output)
    return results


def _i2c_byte(
    value: int,
    *,
    sda_pin: int = 4,
    scl_pin: int = 5,
    include_start: bool = True,
) -> list[int]:
    scl = 1 << scl_pin
    trace: list[int] = [scl | (1 << sda_pin), scl] if include_start else []
    for bit_index in range(8):
        bit = (value >> (7 - bit_index)) & 1
        sda = (1 << sda_pin) if bit else 0
        trace.extend((sda, sda | scl))
    return trace


def _spi_command(
    value: int,
    *,
    cs_pin: int = 7,
    sclk_pin: int = 4,
    mosi_pin: int = 5,
) -> list[int]:
    cs = 1 << cs_pin
    sclk = 1 << sclk_pin
    mosi = 1 << mosi_pin
    trace = [cs, 0]
    for bit_index in range(8):
        bit = (value >> (7 - bit_index)) & 1
        low = mosi if bit else 0
        trace.extend((low, low | sclk))
    return trace


def demo_basic_compliance() -> None:
    uart = _compile(
        "phase6/basic_uart.chi",
        {"basic_uart.rx": "uio[0]", "basic_uart.tx": "uio[1]"},
    )
    uart_results = _replay(uart, (0x00, 0x01, 0x01, 0x00))
    assert uart_results[1].contexts["basic_uart"].state_after == "stop"
    assert (uart_results[1].drive_value, uart_results[1].drive_enable) == (0x00, 0x02)
    assert (uart_results[-1].drive_value, uart_results[-1].drive_enable) == (0x02, 0x02)

    spi = _compile(
        "phase6/basic_spi.chi",
        {
            "basic_spi.cs": "uio[7]",
            "basic_spi.sclk": "uio[4]",
            "basic_spi.miso": "uio[6]",
        },
    )
    spi_results = _replay(spi, (0x80, 0x00, 0x10, 0x00, 0x10, 0x00, 0x10, 0x00, 0x10, 0x80))
    assert spi_results[2].drive_value & 0x40
    assert not (spi_results[4].drive_value & 0x40)
    assert spi_results[-1].drive_enable == 0

    i2c = _compile(
        "phase5/i2c_ack.chi",
        {"i2c_ack.sda": "uio[4]", "i2c_ack.scl": "uio[5]"},
        strip_contracts=True,
    )
    i2c_inputs = _i2c_byte(0x84)
    i2c_inputs.extend((0x00, 0x20, 0x00))
    i2c_results = _replay(i2c, i2c_inputs)
    assert any(result.contexts["i2c_ack"].drive_enable & 0x10 for result in i2c_results)
    assert i2c.manifest["open_drain_pins"] == ["uio[4]"]
    print("PASS demo 1: UART, SPI, and I2C loaded endpoint compliance")


def demo_i2c_sensor() -> None:
    sensor = _compile(
        "phase6/i2c_sensor.chi",
        {"i2c_sensor.sda": "uio[4]", "i2c_sensor.scl": "uio[5]"},
        fault_seed=0xACE1,
    )
    address_trace = _i2c_byte(0x84)
    address_trace.extend((0x00, 0x20, 0x00))
    first = _replay(sensor, address_trace)
    assert first[-4].contexts["i2c_sensor"].state_after == "ack"
    ack_index = next(
        index
        for index, result in enumerate(first)
        if result.contexts["i2c_sensor"].state_after == "ack_hold"
    )
    assert first[ack_index].drive_enable & 0x20

    register_trace = _i2c_byte(0x5A, include_start=False)
    register_trace.extend((0x00, 0x20, 0x00))
    register_results = _replay(sensor, address_trace + register_trace)
    register_state = register_results[-1].contexts["i2c_sensor"]
    assert register_state.variables["address"] & 0xFF == 0x5A
    print("PASS demo 2: I2C sensor ACK, writable byte capture, stretch, and delay")


def demo_spi_identity_rewrite() -> None:
    rewrite = _compile(
        "phase6/spi_flash_rewrite.chi",
        {
            "spi_flash_rewrite.cs": "uio[7]",
            "spi_flash_rewrite.sclk": "uio[4]",
            "spi_flash_rewrite.mosi": "uio[5]",
            "spi_flash_rewrite.miso": "uio[6]",
        },
    )
    trace = _spi_command(0x9F)
    for _ in range(7):
        trace.extend((0x10, 0x00))
    trace.extend((0x10, 0x00, 0x80))
    results = _replay(rewrite, trace)
    id_bits = [
        bool(results[index].drive_value & 0x40)
        for index in range(len(results))
        if results[index].contexts["spi_flash_rewrite"].fired
        and results[index].contexts["spi_flash_rewrite"].state_before in {
            "id0",
            "id1",
            "id2",
            "id3",
            "id4",
            "id5",
            "id6",
            "id7",
        }
    ]
    assert id_bits[:8] == [True, True, True, False, True, True, True, True]
    assert results[-1].drive_enable == 0

    passthrough = _replay(rewrite, _spi_command(0x03) + [0x10, 0x00, 0x80])
    assert passthrough[-2].drive_enable == 0
    print("PASS demo 3: SPI flash JEDEC identity rewrite and normal-command release")


def demo_reproducible_fault() -> None:
    fault = _compile(
        "phase5/fault_flip.chi",
        {"sampled_fault.data": "uio[0]", "sampled_fault.response": "uio[1]"},
        fault_seed=0xACE1,
    )
    inputs = (0x00, 0x01, 0x00, 0x00)
    first = _replay(fault, inputs)
    second = _replay(fault, inputs)
    first_signature = [
        (result.drive_value, result.drive_enable, result.contexts["sampled_fault"].state_after)
        for result in first
    ]
    second_signature = [
        (result.drive_value, result.drive_enable, result.contexts["sampled_fault"].state_after)
        for result in second
    ]
    assert first_signature == second_signature
    assert first[1].contexts["sampled_fault"].state_after == "corrupted"
    print("PASS demo 4: seeded fault replay is identical after reset")


def demo_new_protocol_and_transducers() -> None:
    proxy = _compile(
        "phase6/wire_proxy.chi",
        {"wire_proxy.side_a": "uio[0]", "wire_proxy.side_b": "uio[4]"},
    )
    proxy_results = _replay(proxy, (0x00, 0x01, 0x01, 0x00, 0x00))
    assert [
        (result.drive_value, result.drive_enable)
        for result in proxy_results
    ] == [(0, 0), (0x10, 0x10), (0x10, 0x10), (0, 0x10), (0, 0x10)]

    translate = _compile(
        "phase6/bit_order_translate.chi",
        {
            "bit_order_translate.source": "uio[0]",
            "bit_order_translate.source_clock": "uio[1]",
            "bit_order_translate.destination_clock": "uio[2]",
            "bit_order_translate.destination": "uio[3]",
        },
    )
    translate_results = _replay(translate, (0x00, 0x03, 0x07, 0x03, 0x07, 0x03))
    assert translate_results[-1].drive_value & 0x08

    firewall = _compile(
        "phase6/spi_firewall.chi",
        {
            "spi_firewall.cs": "uio[7]",
            "spi_firewall.sclk": "uio[4]",
            "spi_firewall.mosi": "uio[5]",
            "spi_firewall.miso": "uio[6]",
        },
    )
    allowed = _replay(firewall, _spi_command(0x03) + [0x10, 0x00, 0x80])
    blocked = _replay(firewall, _spi_command(0x02) + [0x10, 0x00, 0x80])
    assert allowed[-2].contexts["spi_firewall"].state_before == "allowed"
    assert blocked[-2].contexts["spi_firewall"].state_before == "blocked"
    assert blocked[-2].drive_enable == 0
    print("PASS demo 5: new wire protocol plus translation and firewall policy")


def main(source_root: Path | None = None) -> int:
    # Keep the default production gate unchanged, while allowing the same
    # model-vs-RTL replay to be run against an isolated source tree.
    global _REPLAY_SOURCE_ROOT
    _REPLAY_SOURCE_ROOT = source_root
    demo_basic_compliance()
    demo_i2c_sensor()
    demo_spi_identity_rewrite()
    demo_reproducible_fault()
    demo_new_protocol_and_transducers()
    print("PASS: all five Phase 6 demos and transducer slices")
    return 0


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-root",
        type=Path,
        help="RTL source root to use for generated runtime replays",
    )
    args = parser.parse_args()
    raise SystemExit(main(args.source_root))
