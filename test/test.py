# SPDX-FileCopyrightText: 2026 Chimaera contributors
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import (
    ClockCycles,
    FallingEdge,
    ReadOnly,
    ReadWrite,
    with_timeout,
)


CLOCK_NS = 20
BIT_CYCLES = 16
RX_PIN = 0
TX_PIN = 1
I2C_SDA_PIN = 4
I2C_SCL_PIN = 5
SPI_SCLK_PIN = 4
SPI_MOSI_PIN = 5
SPI_MISO_PIN = 6
SPI_CS_PIN = 7


def pin(value, index):
    return (int(value) >> index) & 1


async def reset_dut(dut, protocol_select=0):
    await ReadWrite()

    dut.ena.value = 1
    dut.ui_in.value = protocol_select
    dut.uio_in.value = 0xFF
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)

    await ReadWrite()
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def drive_uio_lines(dut, value, settle):
    # Sampling helpers may leave their caller in the final ReadOnly phase of a
    # timestep.  Advance to the falling clock edge before driving so the write
    # always happens in a new, writable simulator phase and is stable before
    # the DUT samples it on the next rising edge.
    await FallingEdge(dut.clk)
    dut.uio_in.value = value
    await ReadWrite()
    await ClockCycles(dut.clk, settle)


async def set_i2c_lines(dut, sda, scl, settle=3):
    value = 0xFF
    if not sda:
        value &= ~(1 << I2C_SDA_PIN)
    if not scl:
        value &= ~(1 << I2C_SCL_PIN)

    await drive_uio_lines(dut, value, settle)


async def i2c_start(dut):
    await set_i2c_lines(dut, 1, 1)
    await set_i2c_lines(dut, 0, 1)


async def i2c_send_byte(dut, value):
    for bit_index in range(8):
        bit_value = (value >> bit_index) & 1
        await set_i2c_lines(dut, bit_value, 0)
        await set_i2c_lines(dut, bit_value, 1)
        await set_i2c_lines(dut, bit_value, 0)


async def i2c_ack_cycle(dut):
    # The target asserts SDA low after seeing SCL fall, holds it through the
    # high phase, and releases it on the next falling edge.
    await set_i2c_lines(dut, 1, 0)
    await ReadOnly()
    assert int(dut.uio_oe.value) & (1 << I2C_SDA_PIN), "I2C target did not ACK"
    await set_i2c_lines(dut, 0, 1)
    await ReadOnly()
    assert pin(dut.uio_out.value, I2C_SDA_PIN) == 0
    await set_i2c_lines(dut, 0, 0)
    await set_i2c_lines(dut, 1, 0)
    await ReadOnly()
    assert not (int(dut.uio_oe.value) & (1 << I2C_SDA_PIN)), "I2C SDA not released"


async def set_spi_lines(dut, sclk, mosi, cs, settle=3):
    value = 0xFF
    for enabled, index in ((sclk, SPI_SCLK_PIN), (mosi, SPI_MOSI_PIN), (cs, SPI_CS_PIN)):
        if not enabled:
            value &= ~(1 << index)

    await drive_uio_lines(dut, value, settle)


async def spi_transaction(dut, value):
    await set_spi_lines(dut, 0, 0, 0)
    await ReadOnly()
    assert int(dut.uio_oe.value) & (1 << SPI_MISO_PIN), "SPI MISO not enabled"
    response = 0
    for bit_index in range(8):
        bit_value = (value >> bit_index) & 1
        await set_spi_lines(dut, 0, bit_value, 0, settle=2)
        await set_spi_lines(dut, 1, bit_value, 0)
        await ReadOnly()
        response |= pin(dut.uio_out.value, SPI_MISO_PIN) << bit_index
        await set_spi_lines(dut, 0, bit_value, 0)
    await ReadOnly()
    assert not (int(dut.uio_oe.value) & (1 << SPI_MISO_PIN)), "SPI MISO not released"
    await set_spi_lines(dut, 0, 0, 1)
    return response


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
    # Icarus/cocotb exposes packed vectors as non-indexable handles, and
    # FallingEdge requires a scalar signal.  The testbench provides uart_tx as
    # a scalar observation point for this pin.
    await FallingEdge(dut.uart_tx)

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


@cocotb.test()
async def i2c_target_acknowledges_address_and_data(dut):
    """The second reaction cell accepts 0x42 writes and ACKs both bytes."""
    cocotb.start_soon(Clock(dut.clk, CLOCK_NS, unit="ns").start())
    await reset_dut(dut, protocol_select=0)
    await set_i2c_lines(dut, 1, 1)

    await i2c_start(dut)
    await i2c_send_byte(dut, 0x84)  # 7-bit address 0x42, write direction.
    await i2c_ack_cycle(dut)
    await i2c_send_byte(dut, 0x5A)
    await i2c_ack_cycle(dut)

    assert int(dut.uo_out.value) == 0x5A
    assert not (int(dut.uio_oe.value) & (1 << I2C_SDA_PIN))


@cocotb.test()
async def i2c_wrong_address_is_nacked_and_never_drives_high(dut):
    """An address mismatch leaves SDA released; the open-drain path cannot drive high."""
    cocotb.start_soon(Clock(dut.clk, CLOCK_NS, unit="ns").start())
    await reset_dut(dut, protocol_select=0)
    await set_i2c_lines(dut, 1, 1)

    await i2c_start(dut)
    await i2c_send_byte(dut, 0x86)
    await set_i2c_lines(dut, 1, 0)
    await ReadOnly()
    assert not (int(dut.uio_oe.value) & (1 << I2C_SDA_PIN)), "Wrong address was ACKed"
    assert pin(dut.uio_out.value, I2C_SDA_PIN) == 0


@cocotb.test()
async def spi_target_shifts_response_and_captures_command(dut):
    """The second reaction cell speaks SPI mode 0 and returns the 0x3c demo response."""
    cocotb.start_soon(Clock(dut.clk, CLOCK_NS, unit="ns").start())
    await reset_dut(dut, protocol_select=1)
    await set_spi_lines(dut, 0, 0, 1)

    response = await spi_transaction(dut, 0xA5)

    await ReadOnly()
    assert response == 0x3C
    assert int(dut.uo_out.value) == 0xA5
    assert not (int(dut.uio_oe.value) & (1 << SPI_MISO_PIN))


@cocotb.test()
async def spi_chip_select_abort_releases_miso(dut):
    """A truncated SPI frame releases MISO when CS returns high."""
    cocotb.start_soon(Clock(dut.clk, CLOCK_NS, unit="ns").start())
    await reset_dut(dut, protocol_select=1)
    await set_spi_lines(dut, 0, 0, 1)
    await set_spi_lines(dut, 0, 0, 0)
    await set_spi_lines(dut, 1, 0, 0)
    await set_spi_lines(dut, 0, 0, 0)
    await ReadOnly()
    assert int(dut.uio_oe.value) & (1 << SPI_MISO_PIN)

    await set_spi_lines(dut, 0, 0, 1)
    await ReadOnly()
    assert not (int(dut.uio_oe.value) & (1 << SPI_MISO_PIN)), "Aborted SPI frame kept MISO driven"
