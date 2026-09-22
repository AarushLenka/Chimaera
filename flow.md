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
