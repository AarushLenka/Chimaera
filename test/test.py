# SPDX-FileCopyrightText: 2026 Chimaera contributors
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, with_timeout


CLOCK_NS = 20
BIT_CYCLES = 16
RX_PIN = 0
TX_PIN = 1


def pin(value, index):
    return (int(value) >> index) & 1


async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0xFF
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def drive_uart_byte(dut, value):
    # 8-N-1, least-significant bit first.
    dut.uio_in.value = 0xFE
    await ClockCycles(dut.clk, BIT_CYCLES)
    for bit_index in range(8):
        bit_value = (value >> bit_index) & 1
        dut.uio_in.value = 0xFF if bit_value else 0xFE
        await ClockCycles(dut.clk, BIT_CYCLES)
    dut.uio_in.value = 0xFF
    await ClockCycles(dut.clk, BIT_CYCLES)


async def decode_uart_tx(dut):
    await FallingEdge(dut.uio_out[TX_PIN])

    # Check the middle of the start bit, then each data bit and the stop bit.
    await ClockCycles(dut.clk, BIT_CYCLES // 2)
    await ReadOnly()
    assert pin(dut.uio_out.value, TX_PIN) == 0, "TX start bit ended early"

    value = 0
    for bit_index in range(8):
        await ClockCycles(dut.clk, BIT_CYCLES)
        await ReadOnly()
        value |= pin(dut.uio_out.value, TX_PIN) << bit_index

    await ClockCycles(dut.clk, BIT_CYCLES)
    await ReadOnly()
    assert pin(dut.uio_out.value, TX_PIN) == 1, "TX stop bit is not high"
    return value


@cocotb.test()
async def uart_receive_and_echo_has_exact_bit_timing(dut):
    """Receive 0xA5, expose it on uo_out, and transmit the same 8-N-1 frame."""
    cocotb.start_soon(Clock(dut.clk, CLOCK_NS, unit="ns").start())
    await reset_dut(dut)

    assert int(dut.uio_oe.value) == (1 << TX_PIN), "Only UART TX may drive"
    assert pin(dut.uio_out.value, TX_PIN) == 1, "UART TX must idle high"

    tx_decoder = cocotb.start_soon(decode_uart_tx(dut))
    await drive_uart_byte(dut, 0xA5)
    echoed_value = await with_timeout(tx_decoder, 10, "us")

    assert int(dut.uo_out.value) == 0xA5
    assert echoed_value == 0xA5


@cocotb.test()
async def uart_false_start_is_rejected(dut):
    """A low pulse shorter than half a bit must not become a received byte."""
    cocotb.start_soon(Clock(dut.clk, CLOCK_NS, unit="ns").start())
    await reset_dut(dut)

    dut.uio_in.value = 0xFE
    await ClockCycles(dut.clk, BIT_CYCLES // 4)
    dut.uio_in.value = 0xFF
    await ClockCycles(dut.clk, BIT_CYCLES * 3)

    assert int(dut.uo_out.value) == 0x00
    assert pin(dut.uio_out.value, TX_PIN) == 1
    assert int(dut.uio_oe.value) == (1 << TX_PIN)
