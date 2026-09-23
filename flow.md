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

## 2026-09-23 — Phase 4 closes in CI

Commit `7a0f415` completed the Phase 4 checkpoint. The clean Python 3.11/Icarus
cocotb run passed all six UART, I2C, and SPI tests, including wrong-address I2C
NACK and aborted-SPI release behavior. GitHub Actions also passed the test, docs,
precheck, IHP hardening, gate-level simulation, and viewer jobs. This supplies the
real-PDK evidence that was missing from the local 1,747-cell generic synthesis
comparison.

The next phase is the host-side DSL/compiler toolchain and reference model. The
current RTL exposes the descriptor fields needed for an initial compiler IR, but
the packed microcode encoding and SPI-like loader command format are intentionally
still undecided; they must be confirmed before compiler binaries and loader RTL
are built around them.

## 2026-09-23 — Phase 5 host toolchain starts

Phase 5 began on the software track without changing the verified Phase 4 RTL. A
dependency-free Python front end now tokenizes and parses protocol, mutation, and
contract blocks; resolves named pin roles and physical-time durations; rejects
invalid targets, conflicting output ownership, active-high open-drain drives,
unbounded internal states, and level-sensitive busy loops; and emits a deterministic
host object with a proof manifest, state diagram, and textual event/action timing
expectation. A cycle-step reference model executes the same checked IR.

Twelve initial unit tests passed, including negative electrical-safety and ownership
cases. The sample `pulse_ack` program asserted `uio[1]` at the fixed one-cycle
reaction point after the synchronized `uio[0]` rise and released it on the bounded four-cycle timeout;
its initial host object CRC was `b5843f37`. This starts but does not complete Phase
5. The host object is deliberately not chip-loadable until the packed
descriptor-memory and SPI-like loader ABI are confirmed; scheduler proof,
mutation/contract execution, generated randomized cocotb, and Hausen's own
hand-written DSL compile also remain.

Hausen confirmed the versioned-host-IR staging decision. The compiler checkpoint
then gained a CRC-validating object reader, a two-context model that merges only
disjoint output enables, and a generated fixed-seed randomized test. The first
standalone generated test failed because an absolute script path placed `/tmp`, not
the repository, on Python's import path; the generator now discovers a repository
package from its working directory. The corrected artifact replayed 256 randomized
cycles twice with seed `1906236818` and produced identical traces.

A five-state I2C DSL example also compiled and ran through the reference model. It
recognized wire byte `0x84`, drove only low for ACK on open-drain `uio[4]`, and
released SDA on the following falling SCL edge. Sixteen host-toolchain tests passed
after this addition.

The first loader-memory sizing experiment exposed the cost of the architecture's
128-descriptor starting point. A simulated 128-bit record memory passed eight-word
write/read, then generic Yosys synthesis measured 8,743 cells for 32 entries,
17,232 for 64, and 34,203 for 128. Because the original depth alone exceeds the
rough raw budget under standard-cell inference, a 32 × 128-bit fixed descriptor
ABI is now proposed for confirmation. Production RTL and chip-loadable packing
remain unchanged pending that decision.

## 2026-09-23 — The compiler stream reaches the loaded reaction cells

Hausen accepted the 32 × 128-bit direction and delegated the remaining area/timing
choices against the 24-tile budget. The compiler backend now freezes the exact
descriptor fields, lowers condition chains through helper states, emits an
MSB-first 32-bit loader stream, and marks protocol-only manifests chip-loadable.
The two-state `loader_pulse` example produces 21 frames (84 bytes) with descriptor
CRC `ca08`. Mutation and contract sources intentionally remain host-only for Phase
6 rather than pretending unsupported records can run on the chip.

The RTL now synchronizes the three configuration inputs, rejects partial and
out-of-order frames, writes the 32-entry memory in eight 16-bit words per state,
checks CRC, entry points, complete records, and every successor target, and keeps
execution halted until an explicit valid resume. A top-level serial test loads the
compiler's exact frame stream, observes the request action, and observes the
four-cycle timeout action. Open-drain values are clamped low in the final output
stage, including on the loaded path.

The first two-context arbitration assertion failed for a testbench reason: it
sampled `fire_1` after the firing edge, by which point that cell had correctly made
itself inactive while awaiting reload. Moving the match check before the edge made
the intended behavior visible. The final test proves both actions commit together,
the losing context becomes pending, and pending-first arbitration rearms it on the
following edge. This removes starvation while keeping one descriptor read port and
a two-inclusive-cycle worst-case rearm bound.

All 18 Python 3.11 toolchain tests pass. Standalone RTL tests pass for the loader,
serial sampler, combined host interface, loaded runtime, and full top-level stream;
the Phase 4 UART/I2C/SPI smoke regression also still passes. Full `-Wall` Verilator
lint is clean. Local Yosys synthesis reports 12,344 generic cells, with 9,214 in
the loader and 4,096 descriptor storage flip-flops. This is encouraging directional
evidence, not a physical-fit claim; IHP hardening remains the next hardware check.

The inherited metadata still requested `1x1`. The current official IHP tile table
supports `6x4`, so `info.yaml` now requests that 24-tile rectangle instead of
silently hardening against the template default.

A final model/RTL consistency audit caught that the two-context reference model
still rearmed both contexts immediately after a simultaneous fire. It now models
the same single pending reload as RTL. The audit also narrowed the scheduling
claim: pending-first arbitration proves a two-cycle bound and no starvation, but a
deferred cell cannot capture an event on its reload edge. Manifests now state the
minimum safe inter-event spacing as an explicit assumption, and adding DSL timing
requirements to discharge that assumption remains open.

Phase 5 is not yet complete under `IMPLEMENTATION.md`: Hausen still needs to write
and compile a small DSL program personally. Direct randomized-test replay against
RTL also remains a useful strengthening task, while mutations/contracts belong to
Phase 6.
