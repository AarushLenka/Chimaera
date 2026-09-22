<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## Chimaera

Chimaera is an event-driven programmable protocol transducer ASIC project. The
functional design is specified in `agent-docs/SPEC.md`; the current Phase 4 build
contains the UART baseline plus selectable I2C and SPI programs.

## How it works

The RTL contains two descriptor-driven reaction cells and one shared execution
engine. Cell 0 receives and echoes UART 8-N-1 on `uio[0:1]`. Cell 1 is selected
with `ui_in[1:0]`: `00` is an I2C target at address `0x42` on `uio[4:5]`, and
`01` is an SPI mode-0 target on `uio[4:7]` that returns `0x3c`. I2C SDA/SCL
outputs are structurally low-only. The last received byte appears on `uo_out`.

## How to test

GitHub CI runs the cocotb tests in `test/test.py`. They cover UART receive/echo
and false-start rejection, I2C ACK/NACK and data capture, and SPI response,
capture, and CS-abort behavior. A dependency-free local smoke test is also
available:

```sh
iverilog -g2012 -s smoke_phase4 -o /tmp/chimaera-smoke \
  src/*.v test/smoke_phase4.v
vvp /tmp/chimaera-smoke
```

For UART, hold `uio[0]` high when idle and send an 8-N-1 frame at one bit per 16
input clocks. For I2C, select `ui_in[1:0]=00`; for SPI, select `01`.

## External hardware

No external hardware is required for simulation. Real hardware will require
3.3 V-compatible serial interfacing appropriate to the Tiny Tapeout carrier.
