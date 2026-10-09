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

## 2026-10-03 — Clean regression after targeted P&R adjustment

Commit `8cab614e857874c35bad333fccd39b23a0effe52` changes only the hosted/local
placement target density from 60 to 70 plus the evidence logs. The clean local
regression passed at this commit: 30 host tests, all five Phase 6 demos, six
standalone RTL benches, Phase 4 smoke simulation, Verilator lint, and generic
Yosys elaboration. No RTL source changed. The hosted GDS/precheck/gate-level
flow still needs to be rerun from this commit before any physical conclusion is
updated.

## 2026-10-04 — Latest hosted GDS reports after density adjustment

The retained `GDS_logs_latest` artifact is for commit
`c1e860c1498d267341c8efe7e9fb16e985b06941` and hosted workflow
`37123217138`. The 20 ns clock and `PL_TARGET_DENSITY_PCT=70` are present in
the resolved flow configuration. The final physical metrics are: die bbox
`0.0 0.0 1289.28 710.64` µm, die area `916214` µm² (`0.916214` mm²),
core/instance area `902417` µm² (`0.902417` mm²), standard-cell area
`699614` µm², and instance utilization `0.775267` (`77.5267%`). The die
envelope remains the configured `6x4` / 24-tile allocation, so the tile-fit
gate passes.

At the slow `nom_slow_1p08V_125C` corner, setup WNS is `-5.1042833627` ns,
setup TNS is `-446.3203550849` ns, and there are `252` setup violations.
Hold WNS/TNS are zero; fast and typical setup WNS/TNS are zero. Relative to
the prior density-60 run, setup WNS improved by `2.8489176269` ns and setup
TNS improved by `676.5756005` ns, but the worst-corner setup requirement is
still not met for 50 MHz / 20 ns.

The manufacturability report now passes antenna, LVS, and DRC. The antenna
reports contain zero net and pin violations, Magic DRC reports zero errors,
route DRC is zero in final metrics, and netgen reports `Final result: Circuits
match uniquely` with zero LVS mismatches. The hosted workflows and the clean
same-commit regression are green, but physical timing is still open; RTL is
not frozen and no submission package is ready.

## 2026-10-04 — Replace the input broadcast with preserved consumer banks

The extracted timing diagnosis identified the remaining setup blocker as a
fanout topology rather than a hold-repair margin: `sync_value[3]` reaches the
loaded runtime action path at `25.926 ns` against a `20.641 ns` requirement.
The placement-only hold-margin experiment was therefore restored to
`PL_RESIZER_HOLD_SLACK_MARGIN=0.10`, and the RTL input frontend was changed to
feed three independent consumer banks. Loaded runtime, legacy reaction cells,
and the execution engine each receive a complete two-flop synchronizer plus
bank-local edge history, preserving the previous synchronized-event latency.

The first implementation duplicated registers in one module, but the initial
Yosys netlist check caught equivalent-register merging back into one broadcast.
That was corrected with explicit `chimaera_input_bank` instances and preserved
hierarchy attributes. An explicit flattened Yosys run then retained the three
instances `input_frontend.legacy_bank`, `input_frontend.loaded_bank`, and
`input_frontend.execution_bank`. The focused bank-latency test and full local
verification passed: 30 host tests, five Phase 6 demos, standalone RTL benches,
Phase 4 smoke, Verilator lint, and generic synthesis (`35347` hierarchy cells).

This is a new RTL checkpoint, not physical closure. The retained GDS reports are
from the prior commit, so the new fanout fix still needs a hosted GDS/precheck/
gate-level rerun and exact-commit timing, area, utilization, DRC/LVS, antenna,
and tile-fit extraction.

## 2026-10-05 — Trace the remaining setup failure to the descriptor-rearm path

The retained report from `4343ee9` and workflow `37219827449` establishes the
result of the three input-bank change: slow-corner WNS improves to
`-3.6422794700 ns`, TNS to `-248.1556363971 ns`, with 249 setup violations.
Standard-cell area is `705103 µm²`, utilization is `78.1349%`, and the 24-tile
die still fits. Hold, antenna, route/Magic DRC, and LVS remain clean, although
345 slow-corner slew violations and 409 fanout violations remain.

Tracing the final worst path clarified that `reaction_cell_1.action_value[3]`
is an active-descriptor register, not the output-drive register. The path runs
from loaded-bank edge history through event matching, shared rearm selection,
and the 32-entry asynchronous descriptor read. Its 15 fanout-buffer output
arcs account for `9.608169 ns` of the `24.359962 ns` arrival time. The
post-CTS repair log loads all three corners; typical-only intermediate reports
must not be mistaken for typical-only optimization.

The flow then explicitly skips post-global-route timing repair because
`RUN_POST_GRT_RESIZER_TIMING` is false. The next correction enables that one
step, allowing setup/hold repair using routed parasitic estimates. RTL,
density 70, the 20 ns period, and the existing hold margins remain unchanged.
This replaces the proposed density-65 experiment with a change directed at a
confirmed missing flow stage. The local gate passed 30 host tests, all five
Phase 6 demos, seven standalone RTL benches, Phase 4 smoke, Verilator lint,
and generic Yosys synthesis (35,347 hierarchy cells). Configuration and
source-diff checks confirm that the routed-repair switch is the sole
flow-parameter change and RTL matches `4343ee9`. A new exact-commit physical
report is still required; enabling repair alone does not establish closure,
and Phase 7 remains open.

## 2026-10-05 — Routed timing-repair rerun still misses slow setup

The hosted GDS build for exact commit `922824e4a68a5ad210c46bb571526b53a2af9047`
completed successfully in workflow `37285614053`. The retained report confirms
`CLOCK_PERIOD=20`, target density 70, `RUN_POST_GRT_RESIZER_TIMING=true`, and
the existing `0.10` placement / `0.05` global-route hold margins. The final die
remains `1289.28 × 710.64 µm` within the configured 24-tile envelope.

Enabling routed timing repair improved the slow-corner result from the exact
`4343ee9` report: setup WNS moved from `-3.6422794700 ns` to
`-3.1490615451 ns`, TNS from `-248.1556363971 ns` to `-129.9196733635 ns`,
and setup violations from 249 to 159. Hold has zero violations. Standard-cell
area is `705168 µm²`, utilization is `78.1422%`, and the timing-repair buffer
count remains 10,921. Final route DRC, Magic DRC, LVS, and antenna metrics are
clean; KLayout DRC is skipped/unreported. The artifact also records 1,001
`EST-0026` missing-route warnings and four disconnected pins, of which zero are
critical. Max slew remains at 287 violations and max fanout at 419.

The remaining worst path starts at `input_frontend.loaded_bank/_098_`
(`sync_value[2]`), travels through `loaded_rise_edges[2]` and the loaded
runtime's event/rearm logic, and ends at
`loaded_runtime.reaction_cell_1.action_value[3]`. Its arrival is `23.859707 ns`
against a `20.710646 ns` requirement, for `-3.149061 ns` slack. The post-GRT
resizer log reported no estimated setup violations before detailed routing, so
the final residual remains a routed manifestation of the loaded event/rearm
topology. Phase 7 remains open and RTL remains unfrozen; the next session
should evaluate a per-cell event-path fanout change before another blind P&R
knob trial.

## 2026-10-05 — Trace the remaining failures through the descriptor read

The user clarified that the GDS build had passed but its downstream precheck
was still running, with an estimated three hours remaining. That check remains
pending; local timing analysis can proceed without cancelling or replacing it.

Mapping the retained worst path into the final netlist showed that cell 0's
event match feeds arbitration, the descriptor request address, the shared
32-entry memory read, and cell 1's next action register. Fifteen fanout buffers
on that path account for `9.015922 ns` of cell delay. All 159 reported setup
failures start at three loaded-bank registers, predominantly ending at descriptor
reload/control fields, with some current output/fault-state endpoints. This
narrows the next experiment beyond simply adding more input synchronizer banks.

An exhaustive 32,768-combination check verified a proposed address simplification:
keep a candidate request address on the read port while idle, instead of selecting
zero, and retain the existing load/arbitration signals. All 15,360 combinations
where a read is consumed retain exactly the original address. The next proposed
experiment is a single-port read split into local decoder/output slices, with
simulation and mapped-netlist inspection before any hosted physical comparison.
Neither experiment has been applied to RTL, and neither has physical results yet.

The warning review also clarified the previous entry: all 1,001 `EST-0026`
warnings belong to intermediate post-GRT repair. The four disconnected pins
are the explicitly unused `ena` and reserved `ui_in[5:7]`, rather than internal
functional disconnections. Final slew, capacitance, fanout, and setup violations
still require attention. Precheck results must be assessed when available;
Phase 7 stays open.

## 2026-10-05 — Implement and screen the descriptor-read remedy

Hausen approved implementing the proposed remedy after raising the area risk.
The runtime now keeps a candidate request address selected while idle and uses
the existing load enables to consume it. This passed the standalone simulations
before the descriptor-read experiments were synthesized.

The read experiment initially used eight preserved 16-bit read slices. It passed
simulation, but preserving the entire read blocks retained 64 descriptor bits
that the original top-level synthesis discarded as unused. The implementation
was refined to preserve only the decoder boundaries. Both 16-bit and 32-bit
variants passed the RTL benches, and the four 32-bit slices were selected for
their smaller mapped logic count. The storage, one logical read port, descriptor
ABI, same-edge actions, and existing rearm schedule remain unchanged.

In a consistent full-top Yosys/ABC simple-gate comparison excluding scope
metadata, the final candidate maps to 27,713 cells versus 28,423 for the original
sources, about 2.50% fewer. Both have 5,831 pre-ABC register bits. The pre-ABC
generic count increases, and the ordinary unflattened local gate reports 39,810
hierarchy cells; these figures describe different gate mixes/pipelines rather
than physical area. All measured alternatives are recorded in `decisions.md`.
The absence of the IHP PDK and OpenROAD prevents a local routed area/timing claim.

The final local verification passed 30 host tests, five Phase 6 demos, seven RTL
benches, the Phase 4 smoke test, lint, synthesis, and the new topology/proof gate.
The loader test now covers 512 word writes and 64 full-row reads across the entire
memory. The topology check confirms four separate decoders with distinct select
nets and maximum select fanout 32, including after ABC mapping. A SAT proof checks
the new combinational slice against the original indexed read for all addresses
and arbitrary data; simulation covers uninitialized-memory behavior. Cocotb was
unavailable, so that optional suite was skipped.

No workflow was altered or pushed, and the existing precheck was left running.
The next step is an exact-commit hosted physical comparison of the implemented
candidate. Area, utilization, slow setup closure, and final electrical/signoff
checks remain unverified for this RTL; Phase 7 is still open.

## 2026-10-06 — Local routed screen validates the descriptor remedy

The descriptor-read candidate completed a matched local OpenROAD placement,
CTS, hold-repair, and global-route screen using the IHP standard-cell libraries
and the retained 20 ns SDC. The candidate finished global routing with setup
WNS `+2.83 ns`, TNS `0 ns`, and hold slack `+0.04 ns`; the baseline finished at
setup WNS `-0.70 ns`, TNS `-6.03 ns`, and hold slack `+0.01 ns`. Candidate
post-hold area was `717,388 µm²` versus `690,697 µm²` for the baseline, so the
timing gain carries a measured local area increase. Both screens report a
global-routing congestion warning.

This is comparative evidence, not a replacement for the hosted flow: the local
screen uses a different OpenROAD/LibreLane container and stops after global
routing without detailed-route extraction, final SPEF STA, PDN, antenna, Magic
DRC, LVS, or KLayout DRC. The exact-commit hosted workflow must be run on the
committed RTL before Phase 7 can close.

The implementation and proof gates pass: full `scripts/local-verify.sh`, the
descriptor topology/SAT gate, standalone selector tests, Verilator strict lint,
and generic synthesis. The next action is to checkpoint the focused RTL/test
change and dispatch the manual GDS workflow for that exact commit.

## 2026-10-06 — Hosted run rejects four-bank replication; screen two-bank candidate

The exact hosted GDS workflow for commit `934ea8b33cee80192481affa9ea672b5c9c76739`
completed GDS and gate-level simulation successfully. Its retained slow-corner
metrics are WNS `-7.04375 ns`, TNS `-647.88482 ns`, and `280` setup violations;
hold has zero violations. The worst path starts at
`input_frontend.loaded_bank/_098_/Q`. This is a physical regression from the
prior exact commit, so the four-selector candidate is rejected despite its
positive matched local screen.

The follow-up candidate shares the eight early decoders in two banks, each
feeding two 32-bit slices. Full local verification passes, and the matched
global-route screen reports WNS `+0.65 ns`, TNS `0 ns`, hold `+0.03 ns`, and
`702,469 µm²` area at `78%` utilization. The screen still warns about routing
congestion and is not signoff evidence. Commit and hosted rerun this two-bank
candidate before making any Phase 7 closure claim; precheck for `37435108709`
remains separate and was still running when these metrics were reported.

## 2026-10-07 — Keep production unchanged while evaluating independent reads

The exact hosted run for `dc2287144c0042ecdfc21a243ac17d616a9dcac0` completed
successfully at the workflow level, but its final slow-corner report rejected
the current shared-read production candidate: WNS was `-6.7110816581 ns`, TNS
was `-1086.7175058528 ns`, and there were `281` setup violations. Hold was
clean, as were the final DRC, LVS, antenna, and power-grid checks. The critical
routed path shows `select_request_1` at `15.292 ns`, followed by the shared
selector/read network and an endpoint arrival at `27.560 ns`.

The isolated `/tmp/chimaera-read-diagnosis.xclGdS` prototype was rechecked. Its
simulation passed all 128 decision patterns, and the Yosys SAT miter proved
reload-data equivalence. The mapped read-cone comparison is `48,092 → 81,278
µm²`, or `+33,185 µm²`, which remains screening evidence because it does not
include the integrated runtime or routing. Production RTL remains unchanged.
The next candidate checkpoint is a full runtime integration and local gate
before any commit or hosted physical run; Phase 7 remains open.

## 2026-10-07 — Complete the isolated two-read runtime gate

The independent-read candidate under `experiments/two_read_runtime/` now has a
full local gate. `bash experiments/two_read_runtime/local-verify.sh` passed all
30 host tests, all five Phase 6 demos against the candidate source root, the
candidate loader/host/fault benches, the per-context selector bench, the full
runtime bench, the production-vs-candidate runtime miter, the Phase 4 smoke
test, strict Verilator lint, Yosys synthesis, topology checks, and the SAT
read-equivalence proof. The production Phase 6 demo replay also remained green
after the replay generator learned the candidate's two-bus interface.

The runtime miter compares outputs and internal pending/active/cell/shift state
on every cycle for 260 cycles. Its deterministic directed plus saturated
stimulus recorded `54` simultaneous fires, `54` deferred reloads, `160`
timeout fires, `205` true and `64` false branch fires, `106` dynamic-selector
fires, and `244` saturated-run cycles. This proves behavioral equivalence for
the exercised runtime state and action/rearm cases; it is not a formal proof
over all sequential traces.

The candidate netlist retains four context selector banks, four early decoders
per bank, 128 distinct row-select nets, and maximum row-select fanout `64`.
All candidate address inputs are register-driven, the selector module has no
storage, the SAT miter proves both private 128-bit buses equal the corresponding
production context read for arbitrary decisions and descriptor data, and the
topology check confirms cross-context arbitration is absent from the loader.
The remaining arbitration is still structurally present only in the runtime's
`service_0`/`select_request_1` to `load_0`/`load_1` path. No routed report was
available to quantify whether that path is the next physical bottleneck.

Using one identical full-top Yosys proc/opt/memory-map/techmap/flatten plus
ABC(simple) and `stat` flow, production maps to `32,633` generic cells and the
candidate to `40,369`, a `+7,736` / `+23.71%` screening increase. These are
generic mapped-cell counts, not IHP area, utilization, slack, congestion, or
signoff evidence. Production RTL and workflow files remain unchanged; nothing
was committed or pushed. The candidate is functionally locally proven but is
not adopted and still requires an exact-commit hosted physical comparison.

## 2026-10-07 — Build the private reads from the production source manifest

Inspection of `GDS_logs_231c021` showed that the last push never changed the
GDS-selected RTL: its source snapshot, final netlist, and final metrics are
byte-identical to `dc22871`. It repeats the slow setup failure of `-6.711 ns`
WNS, `-1086.718 ns` TNS, and 281 violations. The independent-read candidate
was committed only under `experiments/`; the build continued to consume `src/`.

Hausen requested the work needed to fix the issue. The loader, host interface,
runtime, and top under `src/` now connect two private combinational descriptor
buses over the same shared memory and write port. Each bus uses only its own
context's successor decisions; arbitration remains on reload enables. The
20 ns clock, 32 x 128-bit loader ABI, same-edge actions, and pending-first rearm
schedule retain their behavior. The architecture documentation now describes
the actual topology.

Production verification passes 30 host tests, all five Phase 6 demos, ten
standalone benches, Phase 4 smoke, strict lint, synthesis, topology inspection,
and the two-bus universal SAT proof. The original bounded-rearm bench remains,
and the 260-cycle runtime comparison now uses a frozen shared-read reference
so adopting the candidate cannot change both sides of that comparison. The
new context selector bench also checks isolation of selected and unselected
unknown memory rows. Six Cocotb UART/I2C/SPI pin-level tests pass at 20 ns.

A matched local IHP screen reaches global routing at setup `+2.20 ns`, TNS
`0`, hold `+0.04 ns`, area `737374 µm²`, and `82%` utilization. The retained
shared-read screen had `+0.65 ns` setup and `702469 µm²` area. Congestion remains.
These are comparative screens with different tool versions and flow steps from
hosted signoff. Detailed-route/extracted timing and an additional screen using
the hosted AREA 0 synthesis settings are running under
`/tmp/chimaera-two-read-pnr.Od9KEg/`; Phase 7 remains open. The next remote run
must use the production source fix and be checked by commit identity and final
metrics. No workflow or clock configuration was changed.

The production source change and local gates are committed as `7d6e04c`.
The additional `AREA 0` map reports `567788.1300 µm²` and passes the mapped
topology checks. Functional gate-level simulation with the fixed-PDK IHP cell
models passes the top-level serial load, commit/resume, event-action, and
timeout bench at 20 ns, without delay annotation. This map reaches CTS/hold
repair at `724978 µm²`, `81%` utilization, setup `+3.97 ns`, hold `+0.10 ns`,
and setup TNS `0`; its global routing remains in progress. The first map's
detailed route is also still running. The local containers and evidence are
retained at the path above. Hosted verification awaits explicit push approval
under `agent-docs/AGENTS.md` §9. No push has been made.

## 2026-10-08 — Hybrid shared-final-bus candidate

The current private-read implementation improves local logical timing by
removing arbitration from each descriptor data tree, but its four context
selectors and duplicated 128-bit read buses raise the local screen to about
`737374 µm²` and `82%` utilization. The exact hosted `dc22871` report shows why
that tradeoff matters: the shared-read path has slow setup WNS
`-6.7110816581 ns`, TNS `-1086.7175058528 ns`, 281 violations, and a routed
critical path through loaded input synchronization, event/rearm logic,
`select_request_1`, shared row/data selection, and a reaction action endpoint.
The private-read hosted attempt timed out before yielding a routed report.

The selected candidate changes `src/chimaera_program_loader.v` to use two local
`chimaera_context_selector` instances, one per context, followed by one shallow
final row mux controlled by `descriptor_select_1` and one shared 128-bit read
tree. `src/chimaera_program_runtime.v` exports the existing pending-first winner
as that final-row control; `src/chimaera_host_interface.v` and `src/project.v`
carry it to the loader. The result is duplicated only into the existing 256-bit
runtime interface, so the runtime's fixed same-edge load behavior is preserved.
The input frontend's three CDC banks and the reaction-cell fire/timeout/rearm
semantics were not changed. The arbitration Boolean equations were not changed.

The full generic top screen reports `40419` hierarchy cells for the candidate,
versus `49388` for the private-read baseline, a reduction of `18.16%`. A
one-selector-per-context/private-bus intermediate measured `48452` cells and
row-select fanout `126`, so it was rejected in favor of the shared final bus.
`test/descriptor_hybrid_read_equiv.v` proves the hybrid shared read against the
original selector for all candidate/decision/descriptor values on one 32-bit
slice; the production generate repeats that wiring for all four slices.

`bash scripts/local-verify.sh` passes after the final source and checker edits.
Native IHP synthesis/P&R cannot run in this workspace because `ihp-sg13cmos5l`
is not installed. Therefore this entry records no candidate IHP area,
utilization, WNS/TNS, hold, fanout/slew, congestion, detailed-route, DRC, LVS,
antenna, or tile-fit result. The candidate remains pending exact hosted
commit-identity validation; no commit or push was made.

## 2026-10-08 — Trace 39c1395 SS failure and precompute branches

The latest artifact really contains the hybrid shared-final-bus source despite
its private-read commit subject. FF/TT setup passes, but SS is `-7.130902 ns`
with 283 violations. An exact PDK-library/netlist/SDC/SPEF replay reproduces the
worst path. All failing paths launch from synchronized input bit 7; the sample
feeds mutation comparisons and corruption XORs before byte-branch selection,
then the descriptor bus. This identifies a specific upstream serial cone to
remove instead of another speculative loader rewrite.

The zero-valued resizer layer RC table was investigated as a possible cause.
Primary OpenROAD code and a controlled reroute show that zero overrides fall
back to the technology LEF; explicit equal RC values do not change the result.
Those overrides were removed. The local global-route estimate remains much
more optimistic than extracted SS, so the candidate must reach extraction.

The execution engine now computes both sampled-bit branch outcomes before the
live sample arrives. A retained dual-output predicate per context avoids the
four parameterized modules rejected by the first local mapped-cell checker.
The final form passes synthesis and mapped topology checks. A universal branch
miter and frozen pre-change execution reference guard functional behavior. The
local gate passes 30 host tests, five demos, standalone benches, runtime miter,
smoke, strict lint, generic synthesis, and both formal/topology checks. A
functional-only mapped IHP simulation passes load, commit/resume, event action,
and timeout without delay annotation. Optional Cocotb was not run.

A matched local baseline measures a `1.60%` mapped-area increase and no new
registers. Local routing/extraction runs in
`/tmp/chimaera-ss-fix.JiNkH8/runs/branch-lookahead-v2/` with exact artifact timing
libraries, LEFs, extraction rules, and the 6x4 floorplan, but an older
LibreLane/OpenROAD version. It is screening, not exact hosted signoff. The
production configuration now reports and checks SS instead of allowing a
typical-only setup gate. Final extracted results are pending; no push was made.

### 2026-10-09 — Functional checkpoint while detailed routing runs

The local flow's intermediate STA script reports only its first corner even
when multiple libraries are loaded. SS is now first in the production PNR
corner list, with the final setup checker still covering every corner. An
actual checker regression accepts the baseline's 283 SS failures under the old
typical-only setting and rejects them under the new override.

The frozen-engine change also required one compile-list addition in the isolated
private-read runner. Its full tests, runtime miter, lint, synthesis, topology,
SAT, and flat generic ABC screen pass. The existing descriptor miter referenced
by the production gate was untracked; the checkpoint includes it unchanged so
verification does not depend on a missing file after checkout.

Detailed routing is still running. Post-GRT area is `694027.96 um2`, core
utilization `76.9077%`; repair saw estimated setup `-1.914 ns` at 21 endpoints
and reached `+0.114 ns` with two upsizes, one buffer, and one pin swap before
rerouting. Two intermediate FF hold violations remain (`-0.0216684 ns`).
Neither setup nor hold is claimed closed until extraction. No push was made.

## 2026-10-09 — Restore frontend alignment and require physical signoff

The completed branch-lookahead screen does not close timing: extracted SS
setup is -6.309755 ns with TNS -599.086280 ns and 300 violations; FF hold is
-0.047645 ns with four violations. FF/TT setup and TT/SS hold pass. There are
89 SS slew violations, 21 TT slew violations and ten capacitance violations
at every corner. Standard-cell area is 694344 um2 at 76.9426% utilization;
routing DRC and antenna counts are zero, but the screen omitted full signoff.

An uncommitted input pipeline also failed the existing frontend alignment
test on reset and added a cycle to loaded/execution observations. It was backed
up under `/tmp/chimaera-status-backup/` and replaced with the committed aligned
two-flop frontend. The full functional gate passes again: 30 host tests, five
demos, standalone benches, runtime comparison, smoke, lint, synthesis and SAT.

The local and production configurations now require all-corner slew and
capacitance checks as well as setup, and explicitly enable Magic DRC, KLayout
DRC and LVS. Actual LibreLane checker methods reject the failing extracted
metrics and accept clean metrics under both configurations. `RUN_LVS` is the
supported LVS flag; the removed `RUN_NETGEN_LVS` edit was not that flag.

The worst extracted path now starts at synchronized input bit 2, with heavy
loads on the rising-edge detector and the final descriptor read reduction.
An isolated repair reads those extracted loads, makes cell sizing/pin-swap
changes and inserts electrical/hold buffers without adding registers. Before
rerouting, area is 695478 um2, about 0.16% above the input route. Functional
mapped simulation passes load, commit/resume, event action and timeout. The
checked-in `scripts/repair-extracted.tcl` reproduces the trial's netlist hash.

The first restart retained old signal wiring and incorrectly reduced GRT
resources. That run was stopped; the corrected script removes regular wires
while retaining the power grid before a fresh route. The separate corrected
screen is `/tmp/chimaera-ss-fix.JiNkH8/runs/extracted-repair-v2/`. Its final
extraction and exact hosted validation remain required. See
`agent-docs/EXTRACTED_REPAIR.md` for the evidence and reproducible procedure.

## 2026-10-09 — Finish setup repair, pursue remaining physical gates

The fresh `extracted-repair-v2` route confirms that the major SS setup failure
is repaired: SS worst slack is +0.273237 ns, with FF/TT/SS setup WNS/TNS and
violation counts all zero. FF still has two hold failures (-0.036307 ns WNS,
-0.049251 ns TNS), SS has 22 slew failures, and each corner has five
capacitance failures. Standard-cell area is 696071 um2 at 77.1341%
utilization; the 902417 um2 instance metric includes fillers. The run omitted
final DRC/LVS and timing/electrical checker stages, so Phase 7 remains open.

The remaining hold endpoints are two loaded shift-register inputs. Six logic
drivers account for the SS slew failures and five buffer outputs exceed
0.300000 pF, with a maximum measured load of 0.329483 pF. Applying the existing
repair script to this fresh extraction resizes 11 cells and inserts 17
electrical buffers plus 30 hold buffers. Pre-route area is 696733 um2
(+0.095%), with no added sequential state or effective constraint change.
The repaired mapped netlist passes serial load, commit, resume, event action
and timeout.

The first restart's JSON-looking CLI list overrides were parsed as literal
strings. That run was stopped during global routing. A corrected JSON
overlay verifies actual `["*"]` corner coverage in `resolved.json` and enables
Magic DRC, KLayout DRC and LVS. Fresh routing/full signoff runs in
`/tmp/chimaera-ss-fix.JiNkH8/runs/extracted-closure-v3-all/`, without a final
stage limit. The only skipped repair is the estimate-based post-GRT timing
repair. Final extraction and physical checker results are pending.

An artifact audit now reports PASS, FAIL or INCOMPLETE from final per-corner
metrics, completed physical stages, checker coverage, footprint and output
views. Its first checks correctly reject the previous run's hold/electrical
violations and missing DRC/LVS, and flag the stopped restart as incomplete.

## 2026-10-09 — Save a rollback point before the next timing change

V3's detailed route and fresh extraction completed with SS setup at
-0.038121 ns (one failure), clean hold across FF/TT/SS, 15 SS slew failures,
and FF/TT/SS capacitance counts 4/3/3. Area is 697169 um2 at 77.2557%
utilization, with zero routed DRC and antenna counts. Magic streamout was
stopped before full physical signoff because timing/electrical gates already
fail. No subsequent layout repair has been applied.

Before further changes, Hausen requested a commit to make rollback possible.
The complete physical experiment and matched PDK are archived on the workspace
filesystem, outside volatile `/tmp`; `tar --diff` confirms the backup matches
the originals. Both v2's +0.273237 ns SS setup result and v3's clean hold result
are retained. The checkpoint records all-corner metrics, tool identity, hashes
and restoration instructions in `agent-docs/PHYSICAL_CHECKPOINT_2026-10-09.md`.
The existing uncommitted evidence documentation and audit helper are included
in the Git checkpoint; the 783 MB physical archive remains local and ignored.
