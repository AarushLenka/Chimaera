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

## 2026-09-27 — Connect generated replay to the loaded RTL runtime

The next Phase 5 gap was addressed without changing the runtime ABI: generated
randomized tests now derive synchronized input, rising-edge, and falling-edge
traces, compare the reference model's two context outputs, and feed the same
trace into an Icarus simulation of `chimaera_program_runtime` with the packed
descriptors. A chip-loadable `loader_pulse` replay covers 256 deterministic
cycles; the existing contract-bearing `pulse_ack` artifact remains model-only
because contracts are intentionally deferred to Phase 6. The host suite and all
standalone Phase 5 RTL tests should remain the next verification gate. Hausen
still needs to write and compile a small DSL program personally before Phase 5's
documented completion criterion is met.

## 2026-09-27 — Restore the original test workflow’s Make default

The restored GitHub test workflow reported a failure in `Test Summary`, not in the
test command: `test/results.xml` was missing. The first target in `test/Makefile`
was the standalone `phase5` target, so an unqualified `make` ran the dependency-free
Verilog regressions and returned success without invoking cocotb. The Makefile now
sets `sim` as its explicit default goal; `make phase5` remains available for the
focused RTL regressions, while the unchanged workflow’s `make` produces the JUnit
results file expected by its summary and artifact steps.

## 2026-09-27 — Establish the local verification gate

The current checkout was verified without GitHub Actions: all 20 host-toolchain
tests passed, all five standalone Phase 5 Icarus benches passed, and the Phase 4
smoke bench reported UART baseline, I2C ACK/NACK, SPI response/abort, and two-cell
coverage. Verilator lint passed, and local Yosys synthesis completed with a
15,431-cell mapped hierarchy count; this remains a generic directional number.

The repository now has `scripts/local-verify.sh`, `config.local.json`, and
`scripts/local-harden.sh` so iteration can stay local until the final hosted gate.
The local machine has LibreLane itself but does not currently have the IHP SG13C5L
PDK or native OpenROAD/KLayout/Magic binaries, so the full local GDS run remains
blocked on those environment dependencies. Cocotb is also not installed in the
active Python environment; the script requires it explicitly when
`RUN_COCOTB=1` is requested instead of silently claiming that stage passed.

The GDS workflow is now manual-only. This keeps the full hosted IHP hardening,
precheck, gate-level simulation, and viewer chain available as a final independent
check without making every development push wait for it.

## 2026-09-28 — Return to push-based hosted verification

Hausen confirmed that the last push-triggered GDS workflow eventually completed
successfully after roughly four and a half hours. The project therefore returns
to push-based verification: the GDS workflow once again runs on every push, and
its hosted IHP hardening, precheck, gate-level simulation, and viewer results are
the authoritative gate for future commits. The local LibreLane entry point stays
available, but local hardening is no longer required for this work loop. Phase 5
still has one documented human gate—Hausen must personally write and compile a
small DSL program—before Phase 6 features should begin.

The successful baseline was run 18 (`36326526525`) on `ee9b64d`, before this
push-trigger restoration commit. Its `gds`, `gl_test`, `precheck`, and `viewer`
jobs all completed successfully. The GDS job took 2h19m55s, gate-level testing
took 44s, precheck took 2h12m23s, and viewer publication took 14s. This confirms
the hosted chain is viable, but it also explains why each push must carry a small,
focused change: the long wait is dominated by hosted GDS and precheck work.

## 2026-09-28 — Complete the human-written DSL gate

Hausen wrote and compiled `examples/phase5/hausen_pulse.chi`, a two-state
request/response protocol using explicit `uio[0]` and `uio[1]` bindings. The
compiler reported two states with program CRC32 `31d7d3a7`; the chip-loader
stream contained two descriptors with CRC16 `6886`. This closes the remaining
human-authored Phase 5 criterion. The generated `.chobj`, loader, manifest,
random-test, graph, and waveform files remain ignored build products. Phase 6
now starts at the unresolved mutation/fault-injection hardware ABI decision.

## 2026-09-28 — Implement the first Phase 6 fault slice

The descriptor ABI stayed at 32 fixed 128-bit records. The loader now accepts a
non-zero 16-bit fault seed and four separate 32-bit mutation records per
context. The compiler lowers a sampled-variable equality mutation into a
three-field record, the model applies the XOR after sampling, and the generic
RTL execution engine applies the same fault before successor-condition
evaluation. A targeted mutation trace matches the loaded runtime.

Verification passed locally: 24 dependency-free host tests, six standalone
Icarus benches including the new seed/mutation frame test, Verilator lint, and
Yosys elaboration/synthesis preparation. The generic Yosys result is directional
only; the hosted IHP workflow remains the physical gate after the eventual push.

## 2026-09-28 — Add bounded delayed-action mutation

The same four-record table now supports effect kind `2`: a one-to-255-cycle
delay of the predecoded output action. The reaction cell holds the action while
the normal state successor and descriptor reload continue, then commits the
action after the requested clocks. A targeted four-cycle model/RTL replay proves
the delayed output timing; the previous sampled-bit mutation behavior remains
covered.

The expanded local checks pass: 26 dependency-free host tests, six standalone
Icarus benches, and Verilator lint. No hosted push was made.

## 2026-09-28 — Implement remaining Phase 6 fault records and timing contracts

Phase 6 resumed with the five remaining requested fault forms: NACK/drop,
pin-low holds, duplicated actions, late release, and timing contracts. The
descriptor stayed at 128 bits. The compiler/backend now emits effect kinds
`3..7` through the existing four-record mutation table, with physical pin
selection in the low three bits for pin faults. A new `WRITE_CONTRACT` loader
opcode carries four compact timing records per context. The runtime monitor
evaluates stable-while, high-width minimum/maximum, event-within, and negative
conditions; it records a first violation ID/timestamp, increments a counter,
freezes a four-entry window, raises the loaded-path trigger on `uo_out[7]`, and
pulses output release for the violating cycle while execution continues.

The reference model and generated RTL replay were updated together. Focused
replays covered all five mutation effects; the contract-bearing pulse example
also replayed through RTL, and a deliberate high-width violation produced a
trigger, violation ID 0, count 1, and zero output-enable for that cycle. The
full local gate passed 29 host tests, all standalone Icarus benches, Phase 4
smoke simulation, Verilator lint, and top-level Yosys elaboration/synthesis.
Yosys reported 35,235 hierarchy cells including submodules, which is above the
rough 24,000-cell budget and is only directional generic evidence. Phase 6
feature behavior is covered in simulation, but the phase is not physically
closed: IHP place-and-route and the remaining transducer/demo evidence are next.

## 2026-09-28 — Tighten timing-contract failure boundaries

The follow-up host test covers a late event-within target, a second contract
failure, and sticky first-failure ID/timestamp behavior. The corrected local
gate remains green with 29 host tests, all standalone Icarus benches, Phase 4
smoke simulation, Verilator lint, and 35,235 directional generic hierarchy
cells. No hosted push was made.

## 2026-09-28 — Local physical-gate attempt

`scripts/local-harden.sh` was invoked and stopped before synthesis because
`PDK_ROOT` does not contain `ihp-sg13cmos5l`. Local cocotb is unavailable as
well. No workflow changes were made; hosted IHP hardening remains the next
physical checkpoint.

## 2026-09-28 — Add hosted synthesis diagnostics

The pinned IHP Liberty source was checked directly and contains
`sg13cmos5l_buf_4/X`; the local pre-synthesis Yosys check also reports zero
problems. A rough local technology-mapped reproduction still showed the ABC
driving-cell format warning, but its legacy output warnings also appeared on the
known Phase 5 baseline, so it was not sufficient evidence for an RTL rewrite.
Because the hosted job report is not readable in this environment, the GDS job
now always emits `pre_synth_chk.rpt` and `chk.rpt` warning lines as annotations.
The next step is to use those exact warnings for the smallest RTL or tool
configuration fix, then remove this diagnostic once the physical gate is green.

The first diagnostic run (21, commit `2b15deb`) confirmed that the two Yosys
errors occur in `06-yosys-synthesis/reports/pre_synth_chk.rpt`: one constant
`1'b0` driver conflict and one constant `1'b1` driver conflict. The final
`chk.rpt` reported zero problems, so the ABC driving-cell message is not the
cause of the checker failure. The annotations initially exposed only the
warning headers; the diagnostic now includes the following driver-detail lines
on the next run.

## 2026-09-28 — Fix hosted pre-synthesis driver conflicts

Run 22 annotations identified both conflicts as the shared `record_index`
integer in `src/chimaera_contract_monitor.v`: its combinational violation scan
and clocked update loops drove the same synthesized loop-counter register.
The loop indices are now separate. Local all-module Yosys reproduction no
longer reports either constant-driver conflict, and `make -C test phase5`
passes all standalone Icarus benches. Cocotb and the IHP PDK remain hosted
validation dependencies.

## 2026-10-02 — Hosted physical checkpoint passes

Hausen reported that the push containing the contract-monitor loop-counter fix
passed all GitHub Actions. The public run for commit `dca4ff7` confirms four GDS
workflow jobs succeeded: IHP GDS hardening, gate-level simulation, Tiny Tapeout
precheck, and viewer publication. The GDS job completed in 5h42m57s and the
precheck in 3h12m33s. Numerical area and timing margins were not included in the
checkout or public run summary, so this is recorded as a successful hosted
physical-flow checkpoint, not as a quantified area/slack result.

The next work remains Phase 6 completion: the current RTL/compiler evidence
covers endpoint programs, seeded fault records, and timing contracts, but does
not yet provide simulation evidence for the specified proxy, translation,
rewrite, and firewall transducer modes or the full five-demo script. The next
session should choose and implement one narrowly specified forwarding/rewrite
slice, with its configuration path and simulation evidence, before calling Phase
6 complete or moving to submission preparation.

## 2026-10-02 — First loaded transparent-proxy slice

After the hosted physical checkpoint, the next Phase 6 gap was narrowed to a
forwarding behavior that does not require a new configuration ABI. Added
`examples/phase6/wire_proxy.chi`, binding Port A `uio[0]` to Port B `uio[4]`.
The loaded program mirrors a synchronized rise and fall through two fixed
descriptor reactions. Its explicit trace is `00 -> 10 -> 10 -> 00 -> 00` for
`drive_value/drive_enable`, where `0x10` is Port B high and enabled, followed by
Port B low while remaining enabled.

The reference-model result and generated Icarus runtime replay match. The local
gate now reports 30 host tests, six standalone Phase 5 Icarus benches, Phase 4
smoke coverage, clean Verilator lint, and the same 35,235-cell directional
generic hierarchy. This is the first transducer evidence, not full Phase 6
closure: protocol-level proxying, translation, SPI identity rewrite, firewall
policy, and the complete five-demo simulation script remain to be built and
tested.

## 2026-10-02 — Five-demo Phase 6 simulation gate passes

Added loadable DSL examples for a basic UART/SPI endpoint pair, an I2C sensor
slice, SPI flash identity rewrite, SPI firewall policy, and one-bit clock-domain
translation. The sensor captures a second byte after address `0x84`; its two
seed-independent mutations hold SCL low for two cycles and delay the ACK action
by two cycles. The rewrite recognizes `0x9f` and emits the patched byte `0xef`,
while non-ID commands release MISO. The firewall classifies `0x03` as allowed
and releases MISO for writes/unknown commands.

`python3 scripts/phase6_demos.py` now runs five end-to-end scenarios: basic
UART/SPI/I2C compliance, I2C sensor impersonation, SPI identity rewrite,
same-seed fault replay, and the new wire protocol with translation/firewall
checks. Each scenario compiles through the host proof checks, runs the reference
model, and compares its synchronized trace with generated Icarus RTL replay.
The runner passed all five scenarios. `scripts/local-verify.sh` invokes it before
the standalone RTL benches, so the complete Phase 6 simulation gate is now part
of the normal local verification path.

This closes the Phase 6 simulation criterion. It does not claim silicon behavior,
physical area, or timing margin; the next step is a focused commit followed by
the hosted IHP GDS/gate-level/precheck/viewer workflow.

## 2026-10-03 — Current-commit physical-flow extraction and clean regression

The hosted IHP workflow for commit `8e278b014e82798a49bd886998278e25b77a265c`
completed successfully as run 24 (`36910900661`). Its GDS hardening, Tiny Tapeout
precheck, gate-level test, and viewer jobs all passed. The public viewer deployment
also exposes the current `tt_um_chimaera` OAS: the top-cell envelope is
`1289.28 × 710.64 µm`, or `916213.9392 µm²` (`0.916213939 mm²`), consistent with
the configured `6x4` / 24-tile submission rectangle. This is die-envelope and
tile-allocation evidence, not routed-cell utilization.

The public run metadata does not expose the numeric contents of the protected
`GDS_logs` artifact. Therefore routed area, utilization, WNS/TNS slack, and
standalone DRC/LVS results could not be extracted. The repository configuration
also has `RUN_KLAYOUT_DRC=0` and `RUN_KLAYOUT_XOR=0`; a green precheck is not being
represented as a DRC/LVS report. The 50 MHz / 20 ns target is configured and the
hosted build is green, but timing closure cannot be claimed without the actual
slack report.

The exact-commit local regression passed: 30 host tests, all five Phase 6 demos,
six standalone Icarus benches, the Phase 4 smoke simulation, Verilator lint, and
generic Yosys elaboration/synthesis (`35235` hierarchy cells, directional only).
The same SHA's hosted test run 23 also passed its cocotb-backed `Run tests` step
and JUnit summary. No RTL or P&R fix was made because the missing physical reports
do not identify a failing metric. The next session must obtain authenticated
access to `GDS_logs` (or equivalent numeric reports), then either freeze/package
the RTL if all limits are demonstrated or make one targeted physical fix and
rerun the hosted flow.

## 2026-10-03 — Extract final GDS reports and identify the physical blocker

The locally available `GDS_logs` tree contains the final LibreLane metrics for
the same RTL commit `8e278b014e82798a49bd886998278e25b77a265c` and hosted run 24
(`36910900661`). Final physical numbers are: die bbox `0.0 0.0 1289.28 710.64`
µm, die area `916214 µm²` (`0.916214 mm²`), core/instance area `902417 µm²`
(`0.902417 mm²`), standard-cell area `700603 µm²`, and instance utilization
`0.776363` (`77.6363%`). The die rectangle matches the declared `6x4` / 24-tile
allocation, so the tile-envelope gate passes.

The final 20 ns clock analysis passes hold (`WNS=0`, `TNS=0`) but fails setup at
the slow `nom_slow_1p08V_125C` corner: setup WNS `-7.9532009896 ns`, setup TNS
`-1122.8959556 ns`, and 255 setup violations. Fast and typical setup WNS/TNS
are zero in the final metrics, but the slow-corner failure governs the 50 MHz
gate. Magic DRC reports `0` errors and the final metrics report route DRC `0`;
netgen reports `Final result: Circuits match uniquely` and the LVS mismatch
counters are all zero. However, the manufacturability report fails antenna
checking with `3` pin violations and `3` net violations, so signoff is not yet
clean despite DRC/LVS passing.

The same-SHA clean local regression and hosted cocotb regression were already
verified before this report extraction. Because the physical timing and antenna
gates fail, RTL remains unfrozen and no submission package is declared ready.
The flow emitted `GPL-0302` (`Target density 0.6000 is too low for the available
free area`), so the next hosted attempt uses the targeted P&R-only change
`PL_TARGET_DENSITY_PCT: 60 -> 70` in both hosted and local configurations. The
20 ns clock target and RTL are unchanged; the next run must re-check timing,
antenna, DRC/LVS, utilization, and the 24-tile envelope.
