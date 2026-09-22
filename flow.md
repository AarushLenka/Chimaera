# Chimaera development flow

## 2026-09-22 — Repository and naming audit

Inspected the agent instructions, specification documents, Tiny Tapeout metadata,
RTL scaffold, and test harness. The repository is still at the Phase 0/1 setup
stage: basic RTL tools are present, but the full Tiny Tapeout toolchain and the
actual Chimaera implementation are not yet present. Renamed the project references
to Chimaera and aligned the template top-level module with that name. The next
session should verify the template simulation environment and then lock the spec.

## 2026-09-22 — Phase 2 UART slice started

The local template cocotb run could not start because cocotb is not installed;
Hausen clarified that the full toolchain is expected to run in GitHub CI. Work
therefore moved to the first hardware slice with local Icarus checks as a fast
fallback. The scaffold adder was replaced by a two-flop input synchronizer, one
descriptor-driven reaction cell, a shared shift/count execution engine, and a
UART RX/echo-TX program. Cocotb coverage now checks a normal `0xA5` frame and a
rejected false start, with a dependency-free Verilog smoke test for local use.
The first smoke run falsely reported a short stop bit because concurrent Verilog
tasks shared a non-reentrant loop counter; making the testbench tasks automatic
fixed the checker rather than changing the RTL. The resulting waveform passed
with RX `0xA5`, TX `0xA5`, 16 clocks per bit, and the short false-start pulse
rejected; Verilator lint and Yosys structural checks also passed. The next step is
GitHub CI. Phase 2 is not complete until the cocotb UART TX/RX tests pass there.
Hausen also established the repository policy that work must be split into
focused local commits without AI contributor attribution, and that the agent must
stop and announce when those commits are ready rather than pushing automatically.

## 2026-09-22 — Repair CI metadata and cocotb signal trigger

The first Phase 2 push reached all three workflows but failed in two independent
ways: the cocotb test indexed the packed `uio_out` handle directly, which the CI
simulator rejects, and `info.yaml` still had an empty author. The GDS lint-log
error was a downstream symptom of metadata validation stopping the build before
that artifact could be generated. The testbench now exposes TX as a scalar edge
trigger while the test still extracts the bit from the output bus, and the
metadata names the repository author.
The Python 3.11 CI-equivalent cocotb run then passed both tests, and the local
smoke simulation plus Verilator lint remained clean. The focused fix is ready
for review and push.

## 2026-09-22 — Add IHP functional models to gate-level test

The remote GDS hardening, viewer, and precheck completed successfully, but the
gate-level simulation stopped during Icarus elaboration because the IHP
`ihp_dff_r` and `ihp_mux2` primitives were missing from the simulator inputs.
The gate-level Makefile now explicitly includes the IHP functional standard-cell
model before the regular standard-cell model. The next check is a fresh GDS
workflow run; local RTL checks remain available, but the IHP PDK is only
installed in the CI runner.

The pinned CI PDK does not contain the assumed `_func.v` file. Inspection of its
Verilog sources showed that `sg13cmos5l_stdcell.v` instantiates `ihp_dff_r` and
`ihp_mux2`, while `sg13cmos5l_udp.v` defines them. The gate-level setup therefore
uses the UDP model followed by the standard-cell model, with parse-time checks
for both paths.

## 2026-09-22 — Phase 3 synthesis and hardening checkpoint

The Phase 2 UART slice was synthesized before any Phase 4 feature work. The local
Yosys run mapped the complete `tt_um_chimaera` hierarchy to 488 generic cells,
with 380 wires and 888 wire bits; this is a technology-independent directional
baseline, not an IHP area estimate. The dependency-free RTL smoke test still
passed with `RX=0xA5`, `TX=0xA5`, 16 clocks per bit, and the rejected short false
start.

The official Tiny Tapeout workflow for commit `6800e58` then completed the IHP
SG13C5L GDS hardening, viewer generation, precheck, and gate-level test
successfully at the configured 50 MHz / 20 ns target. The generated GDS and
reports are retained as workflow artifacts; the exact technology-mapped cell
table and numerical slack are not present in this checkout, so the generic count
is deliberately not presented as physical area. Phase 3's go/no-go result is
positive: the real-PDK hardening checkpoint passed, and the next session can add
the second reaction cell plus I2C/SPI while preserving this baseline.

## 2026-09-22 — Phase 4 two-cell I2C/SPI slice

Started Phase 4 after the Phase 3 hardening checkpoint. Cell 0 remains the
descriptor-driven UART context; cell 1 now shares the execution-engine module
and selects a temporary I2C or SPI descriptor program from `ui_in[1:0]`. The I2C
program accepts address `0x42`, ACKs one write byte, and records that byte. The
SPI mode-0 program captures one command and returns `0x3c`. I2C SDA/SCL outputs
are clamped to low-only, and an incomplete SPI transaction releases MISO when
CS returns high.

The dependency-free `smoke_phase4` simulation passed UART baseline behavior,
valid I2C ACK/data capture, wrong-address NACK, SPI response/capture, and SPI
CS abort. Verilator lint, Yosys structural checks, and Python syntax checks also
passed. The full generic Yosys hierarchy count is 1,747 cells, versus 488 for
the Phase 3 baseline; this is a directional generic comparison, not an IHP area
or timing result. The local cocotb command could not run because `cocotb-config`
is not installed, so the CI cocotb result remains outstanding. The temporary
bootstrap selector and fixed demo values need Hausen's confirmation before this
checkpoint is treated as a final Phase 4 decision.

## 2026-09-22 — Repair cocotb simulator-phase writes

The first CI run of the Phase 4 tests failed before exercising I2C or SPI: their
helpers ended in `ReadOnly`, then assigned the next bus value while the simulator
was still in that read-only phase. The repair imports `ReadWrite` and enters it
before reset, I2C, and SPI input assignments; output checks remain explicitly in
`ReadOnly`. Python syntax and the dependency-free Phase 4 smoke test pass after
the repair. A fresh CI run is still needed to verify both RTL and gate-level
jobs, since cocotb and the PDK are not installed locally.

The first repair exposed a second scheduling mistake: the helpers themselves
still returned in `ReadOnly`, so a caller's next `ReadWrite` was an illegal
backward transition. The final repair leaves helpers writable after their settle
clocks and places `ReadOnly` only before output assertions. Local syntax, smoke
simulation, and diff checks pass; CI must be rerun for the definitive RTL and GL
result.
