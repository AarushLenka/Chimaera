<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## Chimaera

Chimaera is an event-driven programmable protocol transducer ASIC project. The
functional design is specified in `agent-docs/SPEC.md`; the current Phase 2 build
is the first UART reaction-cell slice.

## How it works

The Phase 2 RTL contains one descriptor-driven reaction cell, a shared serial
shift/count execution-engine slice, and a UART 8-N-1 program. A byte received on
`uio[0]` is exposed on `uo_out[7:0]` and echoed on push-pull `uio[1]`; each UART
bit lasts 16 clocks at the current 50 MHz simulation target.

## How to test

GitHub CI runs the cocotb tests in `test/test.py`. They send `0xA5`, check the
received byte and echoed waveform, and verify that a false start pulse is
rejected. A dependency-free local smoke test is also available:

```sh
iverilog -g2012 -s smoke_uart -o /tmp/chimaera-smoke \
  src/*.v test/smoke_uart.v
vvp /tmp/chimaera-smoke
```

Hold `uio[0]` high when idle and send an 8-N-1 frame at one bit per 16 input
clocks. After a valid stop bit, read the byte on `uo_out`; the same byte is echoed
as an 8-N-1 frame on `uio[1]`.

## External hardware

No external hardware is required for simulation. Real hardware will require
3.3 V-compatible serial interfacing appropriate to the Tiny Tapeout carrier.
