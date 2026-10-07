# Chimaera decisions

## 2026-09-22 — Rename project from ChronoWeave to Chimaera

**Context:** The project name was changed by the owner.
**Decision:** Use `Chimaera` in project documentation and `tt_um_chimaera` as the Tiny Tapeout top-level module name.
**Alternatives considered:** Keeping the old name would leave repository metadata and implementation instructions inconsistent.
**Consequences:** Documentation, metadata, and the template testbench now use the new project name; no hardware behavior was changed.
**Status:** confirmed by Hausen

## 2026-09-28 — Close the Phase 5 human DSL checkpoint

**Context:** The Phase 5 implementation requires a human-authored DSL program
to compile successfully, not only compiler fixtures written during development.
Hausen wrote `examples/phase5/hausen_pulse.chi` and compiled it with a 50 MHz
clock and explicit `uio[0]`/`uio[1]` bindings. The compiler produced two states,
CRC32 `31d7d3a7`, two loader descriptors, and CRC16 `6886`.
**Decision:** Accept the human DSL usability gate and close the Phase 5
compiler/loader checkpoint. Track the handwritten source and leave its
reproducible compiler outputs ignored and local.
**Alternatives considered:** Reusing an existing example would not demonstrate
that the DSL is usable by the project owner. Committing generated binaries and
manifests would add stale build outputs without adding source-level intent.
**Consequences:** Phase 6 feature work may begin. The current 128-bit descriptor
ABI remains unchanged until the mutation/fault-injection encoding and control
interface are explicitly chosen.
**Status:** confirmed by Hausen

## 2026-09-22 — Use a descriptor-driven Phase 2 UART slice

**Context:** Phase 2 needs to prove one reaction cell, the shared execution path,
and UART TX/RX before committing to the final compiler-visible instruction
encoding.
**Decision:** Build a parameterized reaction cell whose active event, deadline,
sample, and pin-action fields are locally stored. Use a separate temporary UART
descriptor decoder and a shared shift/count engine. A synchronized event commits
the already-decoded action one clock later. Use a 50 MHz clock, 16 clocks per UART
bit for simulation, `uio[0]` for Port A RX, and `uio[1]` for Port A TX.
**Alternatives considered:** Hard-wiring a UART controller would violate the
programmable architecture; freezing a packed microinstruction format now would
prematurely constrain the Phase 5 compiler before Phase 3 area data exists.
**Consequences:** The fast path is generic and its fixed reaction latency is
directly testable. The UART descriptor decoder and 16-cycle divisor are temporary
Phase 2 program/configuration choices, not the final program-memory encoding.
**Status:** proposed

## 2026-09-22 — Phase 3 synthesis checkpoint

**Context:** Phase 3 requires an early area/timing check before adding the second reaction cell or additional protocols.
**Decision:** Keep the Phase 2 one-cell UART slice unchanged after synthesis. Local Yosys synthesis reports 488 generic cells for `tt_um_chimaera` (including submodules); the technology-specific Tiny Tapeout/IHP hardening run for commit `6800e58` also completed successfully at the configured 20 ns clock period. Record the generic count as a directional baseline, not as an IHP cell-area equivalent.
**Alternatives considered:** Proceeding directly to Phase 4 without a synthesis checkpoint would hide area growth; reporting the generic Yosys count as a physical IHP area would be misleading.
**Consequences:** The Phase 2 architecture has a small enough generic baseline to continue, and the official hardening flow has exercised the real PDK before adding scope. A future checkpoint must compare against the technology-mapped IHP report/artifact when it is available locally.
**Status:** confirmed by Hausen

## 2026-09-22 — Phase 4 two-cell protocol checkpoint

**Context:** Phase 4 requires the second reaction cell and I2C/SPI coverage while preserving the fixed-latency reaction path and the open-drain safety property.
**Decision:** Keep cell 0 as the UART context and use cell 1 as a Port B protocol context selected by the temporary `ui_in[1:0]` bootstrap strap (`00` = I2C, `01` = SPI, `10`/`11` = disabled). The temporary I2C program accepts write address `0x42` and one data byte; the temporary SPI mode-0 program captures one command and returns `0x3c`. Both descriptor sources feed one execution-engine instance. I2C output enable is clamped to low-only, and SPI MISO is released when synchronized CS is high.
**Alternatives considered:** Adding separate fixed UART/I2C/SPI hardware blocks would violate the chosen generic descriptor architecture. Implementing the full host loader before the second-cell checkpoint would mix Phase 5 scope into the required Phase 4 area experiment. A compile-time protocol choice would not exercise a reusable second context.
**Consequences:** The Phase 4 demonstrations are deterministic and testable, and Port B pin ownership is now explicit. The bootstrap selector and fixed demo values are temporary and must be replaced or confirmed when the Phase 5 loader is designed; they are not claimed as the final v1 configuration interface.
**Status:** proposed

## 2026-09-22 — Make cocotb bus writes phase-safe

**Context:** The RTL and gate-level cocotb jobs failed when I2C/SPI helpers assigned to DUT inputs after awaiting `ReadOnly`; cocotb correctly rejected those writes as occurring outside a writable simulator phase.
**Decision:** Enter `ReadWrite` before every I2C/SPI bus assignment and before reset input setup/release, while retaining `ReadOnly` for output checks after settling clocks.
**Alternatives considered:** Removing `ReadOnly` would hide the scheduling boundary and make checks race-prone. Moving all checks to arbitrary delays would be less explicit and less portable between RTL and gate-level simulators.
**Consequences:** The same testbench can drive RTL and gate-level DUTs without illegal-phase writes; CI must rerun to confirm both jobs pass.
**Status:** confirmed by Hausen

## 2026-09-22 — Keep reusable cocotb drive helpers writable

**Context:** The first phase-safety repair still ended the I2C/SPI drive helpers in `ReadOnly`, so a caller's next `ReadWrite` caused an illegal backward phase transition.
**Decision:** Drive helpers enter `ReadWrite` only for assignments and return after `ClockCycles`; callers enter `ReadOnly` immediately before each output observation.
**Alternatives considered:** Re-entering `ReadWrite` from every caller would still fail if the helper had already entered `ReadOnly`. Removing output synchronization would reintroduce read races.
**Consequences:** Helper composition is legal under cocotb 2.0, and output checks remain deterministic for RTL and gate-level simulations.
**Status:** confirmed by Hausen

## 2026-09-22 — Phase 4 generic synthesis checkpoint

**Context:** The second reaction cell and two protocol descriptor sources needed an area-growth measurement before higher-level transducer features.
**Decision:** Record the full generic Yosys hierarchy count as 1,747 cells, compared with the Phase 3 baseline of 488 cells. Treat both as technology-independent directional counts; do not infer IHP physical area or routing margin from them.
**Alternatives considered:** Reporting only local top-level cells would hide the cost of the reaction cells and shared engine. Calling the generic count an IHP area number would be misleading because the technology mapping and place-and-route report are not present locally.
**Consequences:** The design remains far below the rough 24,000-cell competition ceiling as a generic estimate, but the 3.6x growth is large enough that the next real-PDK hardening run is required before Phase 5/6 scope is added.
**Status:** proposed

## 2026-09-23 — Accept the Phase 4 CI checkpoint

**Context:** Phase 4 could not close until the repaired cocotb suite and the real-PDK workflow both passed with the two-cell UART/I2C/SPI design.
**Decision:** Accept commit `7a0f415` as the Phase 4 checkpoint. Its six RTL cocotb tests pass, and the Tiny Tapeout workflow passes precheck, IHP hardening, gate-level simulation, and viewer generation. The bootstrap protocol selector and fixed demo values remain temporary Phase 4 mechanisms to be replaced in Phase 5; this decision does not freeze a loader or microcode encoding.
**Alternatives considered:** Keeping Phase 4 open after both simulation and real-PDK CI passed would add no new evidence and would delay the specified compiler phase.
**Consequences:** Phase 5 may begin from a verified hardware baseline. The exact descriptor encoding and host-loader command format still require a separate confirmed design decision before compiler binaries and loader RTL are coupled to them.
**Status:** confirmed by Hausen

## 2026-09-23 — Stage Phase 5 behind a versioned host IR

**Context:** Phase 5 needs a parser, proof checker, compiler, and reference model, but the packed descriptor-memory layout and SPI-like loader command ABI have not been confirmed. Coupling the first parser directly to an unreviewed hardware format would make both sides expensive to change.
**Decision:** Start Phase 5 with a dependency-free Python front end and a deterministic `chimaera-host-ir-v1` object explicitly marked as not chip-loadable. Require compile-time logical-to-physical pin bindings, make the first declared state the entry state, and use `mutation <name> for <protocol>` / `contract <name> for <protocol>` for unambiguous attachment. Edge-wait states may sleep without a timeout, but states with no event/timeout and level-sensitive cycles are rejected as unbounded busy loops.
**Alternatives considered:** Freezing a packed descriptor format immediately would decide memory width, transition encoding, and loader complexity without an area comparison. Emitting only an unchecked syntax tree would not exercise the proof-carrying-microcode claims. Requiring timeouts on idle edge-wait states would waste descriptors and conflate safe sleeping with active looping.
**Consequences:** Parser, safety-checker, artifact, and reference-model behavior can now be tested independently of loader RTL. The object cannot yet be loaded on-chip; shared-engine schedulability, mutation/contract lowering, randomized test generation, the packed ABI, and the loader remain open before Phase 5 can close.
**Status:** confirmed by Hausen

## 2026-09-23 — Use 32 fixed-width descriptors for the first loader checkpoint

**Context:** The architecture's 128-descriptor memory was explicitly a synthesis starting point. A runtime-writable 128-bit-wide standard-cell memory synthesized to 8,743 generic cells at 32 entries, 17,232 at 64 entries, and 34,203 at 128 entries; the Phase 4 design was already 1,747 generic cells before loader, trace, fault, and contract logic.
**Decision:** Use 32 entries × 128 bits for the first production compiler/loader ABI. Keep one-cycle indexed descriptor reads and five-bit state IDs; have the compiler reject post-lowering programs above 32 states. Write each descriptor as eight 16-bit host-interface words and keep the host object marked non-loadable until the exact bit packing is verified against RTL.
**Alternatives considered:** Sixty-four fixed entries preserve timing but leave little directional area margin. The original 128-entry starting point exceeds the rough raw cell budget under standard-cell inference. A compact variable-length 16-bit stream saves bits for simple states but adds pointer storage, variable decode/re-arm latency, and scheduler proof complexity.
**Consequences:** Fixed read latency and the current five-bit RTL IDs are preserved, while v1 programs receive a real 32-state limit. Full-program lowering, generic synthesis, and IHP place-and-route must validate that the remaining state and area margins are sufficient; failure reopens compact encoding rather than silently increasing depth.
**Status:** confirmed by Hausen (delegated implementation choice for the 24-tile budget)

## 2026-09-23 — Freeze the loader ABI and use pending-first descriptor rearm

**Context:** The accepted 32-entry depth still needed exact field positions, a
serial command format, and a scheduler that could share one descriptor read port
without making output reaction time depend on contention.
**Decision:** Freeze the 128-bit layout and 32-bit command frames documented in
`agent-docs/PHASE5_ABI_PROPOSAL.md`. Keep both cells' predecoded event/action paths
independent and use pending-first single-port rearm: simultaneous fires commit both
actions, one descriptor reloads immediately, and the deferred context reloads on
the following edge ahead of new work. Retain the small counter/shift successor
calculation per context so both successors are captured on the fire edge.
**Alternatives considered:** A dual-read descriptor memory would increase the
dominant memory mux cost. Fixed-priority arbitration could starve one context when
the other fires continuously. Serializing successor calculation as well as memory
read would require another queued sample/control record and a longer proof bound.
**Consequences:** Loaded programs retain the one-cycle synchronized-event-to-action
guarantee and receive a two-inclusive-cycle maximum rearm bound. Protocol-only
objects can now be marked chip-loadable; mutations/contracts remain host-only until
Phase 6. The 50 MHz synchronized configuration interface limits SCLK to below
12.5 MHz. A deferred context is unarmed on its reload edge, so two-context
manifests explicitly require at least two cycles between relevant events until the
DSL gains timing-requirement declarations. The reference chip model mirrors the
same pending-first behavior.
**Status:** confirmed by Hausen (delegated implementation choice for the 24-tile budget)

## 2026-09-23 — Phase 5 integrated generic synthesis checkpoint

**Context:** The accepted ABI needed a full-design area comparison after adding
the serial sampler, loader validation, 4,096-bit descriptor memory, loaded runtime,
and legacy regression fallback.
**Decision:** Record the local Yosys 0.63 hierarchy result of 12,344 generic cells.
The loader accounts for 9,214 cells, including 4,096 descriptor flip-flops; the
generic runtime local logic is 185 cells and its counter/shift engine is 276 cells.
Treat these as directional counts only.
**Alternatives considered:** Reusing the earlier 8,743-cell memory experiment would
omit command validation and integrated mux/control costs. Calling 12,344 a physical
fit result would ignore IHP mapping, clock trees, placement, routing, and utilization
overhead.
**Consequences:** The checkpoint is roughly half the raw 24,000-cell planning
ceiling, so the 32-entry design is reasonable to carry forward. Real IHP hardening
is still mandatory before claiming that it fits 24 tiles or meets 50 MHz.
**Status:** proposed

## 2026-09-23 — Declare the 24-tile allocation as 6x4

**Context:** Project specifications and Hausen's confirmed budget are 24 Tiny
Tapeout tiles, but the inherited `info.yaml` still requested the template default
`1x1`. The current official IHP support-tools table includes `6x4` as a valid
rectangular size.
**Decision:** Set `project.tiles` to `"6x4"`, representing all 24 allocated tiles.
**Alternatives considered:** Keeping `1x1` would harden against the wrong physical
budget. `8x4` is supported but requests 32 tiles, while the older template comment
omitted four-row sizes and was stale relative to the current support-tools table.
**Consequences:** The next GDS run will target the intended 24-tile die area and
will provide the first meaningful physical utilization/timing result for Phase 5.
**Status:** confirmed by Hausen

## 2026-09-27 — Replay chip-loadable randomized traces against RTL

**Context:** The Phase 5 compiler already generated deterministic randomized
reference-model traces, but its manifest still listed direct RTL replay as an
unverified gap.
**Decision:** Add a dependency-free Icarus bridge that drives the packed
descriptor runtime at its synchronized-input boundary and compares both context
outputs on every generated cycle. Keep asynchronous input synchronization and
serial loading covered by their existing focused RTL tests.
**Alternatives considered:** Rebuilding a full serial-loader and asynchronous
pin test for every randomized case would duplicate the existing top-level test,
make failures harder to localize, and add substantial simulation time. Comparing
only the reference model would leave the compiler-to-runtime ABI untested.
**Consequences:** Every generated randomized test for a chip-loadable program
now checks model-to-RTL behavior for 256 cycles, including timeout, edge, and
pending-reload paths when the seed reaches them. Mutations and contracts remain
host-only until their Phase 6 hardware records are defined.
**Status:** proposed

## 2026-09-27 — Use explicit local verification before hosted hardening

**Context:** The push-triggered GDS workflow runs the full IHP build, precheck,
gate-level test, and viewer jobs remotely, which makes short RTL/compiler
iterations unnecessarily slow.
**Decision:** Add a dependency-free `scripts/local-verify.sh` gate covering the
host tests, standalone RTL benches, smoke simulation, Verilator lint, and Yosys
synthesis. Add a separate `scripts/local-harden.sh` entry point and checked-in
LibreLane configuration for native IHP hardening; keep the hosted workflow as the
final remote gate after local work is complete.
**Alternatives considered:** Running every iteration through GitHub Actions would
preserve remote coverage but impose the current queue and hardening time on every
commit. Treating generic Yosys output as a substitute for IHP hardening would not
provide physical area, routing, or timing evidence.
**Consequences:** Local commits can be verified without pushing. Full local GDS
still depends on the IHP SG13C5L PDK and native OpenROAD/KLayout/Magic tools;
missing dependencies fail explicitly rather than being mistaken for RTL results.
**Status:** confirmed by Hausen

## 2026-09-27 — Make hosted GDS hardening manual-only

**Context:** The full hosted GDS, precheck, gate-level, and viewer chain is too
slow to run on every development push now that the local verification gate is
available.
**Decision:** Remove the `push` trigger from `.github/workflows/gds.yaml` and
retain `workflow_dispatch`; run the hosted chain manually after local hardening
has been reviewed.
**Alternatives considered:** Keeping the push trigger would continue imposing the
remote hardening delay on every commit. Removing the workflow entirely would lose
the final independent hosted check and its generated artifacts.
**Consequences:** Ordinary pushes do not start the long GDS workflow. The final
IHP-backed hosted check remains one deliberate manual action and is not replaced
by generic Yosys results.
**Status:** confirmed by Hausen

## 2026-09-28 — Restore push-triggered hosted hardening

**Context:** The first push-triggered GDS run completed successfully after its
long hosted queue and hardening time. Hausen chose to use pushes as the project
verification mechanism instead of relying on the unfinished local hardening
setup.
**Decision:** Restore the `push` trigger in `.github/workflows/gds.yaml` and treat
the hosted GDS, precheck, gate-level test, and viewer chain as the authoritative
gate for subsequent commits. Keep the local scripts available as optional tools,
but do not make them a phase prerequisite.
**Alternatives considered:** Keeping GDS manual-only would reduce wait time but
would no longer match the chosen push-based review loop. Requiring local
LibreLane would block progress on environment dependencies that are not needed
for the successful hosted path.
**Consequences:** Each pushed change starts the long hosted chain, so commits
should remain focused and small. The next feature work must still respect the
Phase 5 human DSL usability gate before Phase 6 scope is added.
**Status:** confirmed by Hausen

## 2026-09-28 — Add a separate Phase 6 mutation record path

**Context:** The Phase 5 descriptor uses all functional fields and must retain
its fixed-latency 128-bit ABI. Phase 6 needs a deterministic fault seed and
conditional mutation state without widening every descriptor or changing its
CRC stream.
**Decision:** Preserve the descriptor format and add loader opcode `0x5` for a
non-zero 16-bit shared LFSR seed plus opcode `0x6` for four 32-bit mutation
records per context. The first lowerable effect is conditional `flip bits` on a
sampled shift variable after its post-sample value matches an eight-bit literal.
The LFSR advances on each fired context edge; the compiler emits an always-pass
threshold for this deterministic source form.
**Alternatives considered:** Widening descriptors would change the accepted
loader ABI, CRC layout, runtime read path, and all existing streams. Encoding a
mutation in the two reserved descriptor bits cannot carry its condition and
effect mask. Implementing all DSL effects in one step would hide separate timing
and pin-safety risks behind an untestable large change.
**Consequences:** Mutation-bearing sources with this supported form are now
chip-loadable and replayed against the reference model and RTL. Delay,
NACK/drop, pin hold, edge duplication, late release, random conditions, and
contracts remain explicit Phase 6 work; their source information is not silently
discarded.
**Status:** proposed

## 2026-09-28 — Add bounded delayed-action mutation

**Context:** The separate mutation record has an effect payload byte and the
reaction cell already owns the predecoded action registers. A delay mutation can
therefore change output timing while leaving descriptor successor/reload timing
and the fixed descriptor ABI unchanged.
**Decision:** Interpret effect kind `2` as `delay_action`, using the payload byte
as a one-to-255-cycle delay. Apply it after a matching sampled-variable
condition, hold the predecoded action in a small pending register, and commit it
after the requested clocks. Keep the existing open-drain output mask after the
delay stage.
**Alternatives considered:** Rewriting the descriptor timeout or successor
fields would alter protocol control flow and make delay depend on descriptor
rearming. Supporting 16-bit delays in this first record would consume another
word before the timing semantics are proven; the compiler rejects values above
255 for this slice.
**Consequences:** `delay next action by N cycles` is now compiler-, model-, and
RTL-loadable for the same equality condition as sampled-value flips. Overlapping
delayed actions and the remaining pin-level effects still need explicit safety
checks and demos.
**Status:** proposed

## 2026-09-28 — Extend mutation records to refusal and pin-timing faults

**Context:** The remaining Phase 6 fault forms need to alter protocol output
behavior without widening the accepted 128-bit descriptor or changing the
descriptor CRC stream.
**Decision:** Keep mutation records at four 32-bit slots per context. Assign
effect kinds `3..7` to NACK, byte drop, pin hold, edge duplication, and late
release. Use the low three bits of the record's low byte for the bound physical
pin on pin-targeted effects; keep the existing seeded threshold behavior for
sample/data effects. NACK and drop suppress the current predecoded action,
hold forces a bounded low drive, duplicate reapplies the selected action one
cycle later, and late release preserves output-enable before clearing it.
**Alternatives considered:** Widening records would increase loader traffic and
fault storage; adding per-effect side tables would cost more state than the
unused low-byte encoding and complicate deterministic loading.
**Consequences:** All five remaining mutation forms are host-, model-, and
RTL-loadable for sampled-variable equality conditions. Pin effects remain
bounded to one-byte durations and preserve the top-level open-drain low-only
mask. More general address/transaction/random conditions remain future work.
**Status:** proposed

## 2026-09-28 — Add separate compact timing-contract records

**Context:** Runtime timing contracts must observe synchronized pins and fail
safe without entering the fixed-latency reaction descriptor path.
**Decision:** Add loader opcode `0x7` with four 32-bit contract records per
context. Implement stable-while, high-width minimum/maximum, event-within, and
negative pin-condition records in a compact monitor with a four-entry trace
window, sticky trigger, first violation ID/timestamp, counter, and one-cycle
output release pulse. Keep execution running after a violation.
**Alternatives considered:** Encoding assertions into reaction descriptors
would consume event/action fields and make the response path contract-dependent;
a large trace RAM would violate the deliberately small evidence-window goal.
**Consequences:** The checked-in pulse and I2C timing contracts are now
chip-loadable and replayable against RTL. Named `except` contract clauses are
parsed but rejected by lowering until state-aware exception handling is
specified. The monitor's generic synthesis cost must be evaluated by IHP
hardening before Phase 6 can be considered physically closed.
**Status:** proposed

## 2026-09-28 — Record Phase 6 generic synthesis pressure

**Context:** The full local verification gate now includes mutation controls and
the timing-contract monitor.
**Decision:** Record the Yosys hierarchy result of 35,235 cells including
submodules as directional evidence only. Treat it as an area-pressure warning,
not a physical fit claim, and require the IHP hardening flow before deciding
whether reduction is necessary.
**Alternatives considered:** Treating the count as final silicon area would
violate the project's generic-versus-physical evidence boundary; ignoring it
would hide a likely hardening risk.
**Consequences:** Simulation, lint, and host replay are green, but Phase 6 is
not physically closed. The next hardware checkpoint is IHP area/timing and
routeability evidence, with focused reductions if the real result confirms the
budget problem.
**Status:** proposed

## 2026-09-28 — Tighten timing-contract failure boundaries

**Context:** The timing-contract monitor needed exact deadline behavior for
event-within records and a stable first-failure report.
**Decision:** Treat a target arriving after an exhausted event window as a
violation, preserve the first violation ID and timestamp while continuing to
count later violations, and saturate the eight-bit count. Keep the reference
model and RTL monitor semantics identical.
**Consequences:** Contract edge cases now have explicit host-model coverage;
the monitor remains fail-safe for the violating cycle and keeps its trace
frozen after the first failure.
**Status:** proposed

## 2026-09-28 — Preserve hosted IHP hardening as the physical gate

**Context:** The local hardening entry point was invoked after the Phase 6
implementation, but this environment has no `PDK_ROOT` containing the IHP
SG13C5L PDK. Native cocotb tooling is also unavailable.
**Decision:** Do not alter the workflow or weaken the physical evidence claim.
Use the hosted GDS/precheck/gate-level/viewer chain after the focused change is
reviewed and pushed, or install the matching PDK/toolchain before retrying
`scripts/local-harden.sh` locally.
**Status:** proposed

## 2026-09-28 — Expose hosted synthesis check reports

**Context:** The IHP hardening job stopped at Yosys synthesis checks, but its
private job log and downloaded report artifact are not readable from the current
environment. The pinned PDK Liberty file does contain `sg13cmos5l_buf_4` with
output pin `X`, so changing the driving-cell name without the exact `chk.rpt`
would be speculative.
**Decision:** Add an always-run workflow diagnostic that locates
`pre_synth_chk.rpt` and `chk.rpt` and emits each Yosys warning as a GitHub
annotation. Keep the synthesis checker enabled and defer RTL/config changes
until the two actual warnings are visible.
**Alternatives considered:** Disabling `ERROR_ON_SYNTH_CHECKS`, removing the
`/X` driving-cell syntax, or rewriting the Phase 6 monitor would hide or guess
at the failure and could invalidate the physical gate.
**Consequences:** The next hosted run may still fail, but it will expose the
precise undriven-net or combinational-loop evidence needed for a focused fix.
**Status:** proposed

## 2026-09-28 — Separate contract-monitor loop indices

**Context:** Hosted run 22 identified two pre-synthesis check errors in
`chimaera_contract_monitor`: the clocked and combinational loops shared the
module-level `record_index`, producing conflicting constant drivers on the
Yosys loop-counter register.
**Decision:** Use distinct loop indices for the combinational contract scan
and the clocked state-update loops. Keep the synthesis checker enabled and
rerun the hosted IHP gate.
**Evidence:** The same two conflicts reproduce before this change with local
Yosys when all modules are checked, and disappear after the split. All
standalone Icarus Phase 5 benches remain green.
**Status:** implemented; hosted verification pending

## 2026-10-02 — Accept hosted physical checkpoint

**Context:** Hosted run 23 for commit `dca4ff7` completed the IHP GDS,
gate-level simulation, Tiny Tapeout precheck, and viewer jobs successfully after
the contract-monitor loop-counter repair.
**Decision:** Treat the hosted run as a passing physical-flow checkpoint and
continue Phase 6 demo work. Preserve the evidence boundary: the public run
metadata confirms successful completion, but no numerical area or timing report
was available in the checkout, so this entry does not claim a measured margin.
**Alternatives considered:** Treating generic Yosys counts as physical area or
assuming a timing margin from a green workflow would overstate the evidence.
Waiting for numerical extraction before any software/demo work would not improve
the already-passing physical gate.
**Consequences:** The design has an independent hosted hardening/precheck
checkpoint, while the Phase 6 "all five demos in simulation" criterion remains
open. Future feature commits must stay focused because each push reruns the long
hosted chain.
**Status:** confirmed by hosted run; Phase 6 completion pending

## 2026-10-02 — Use the existing ABI for the first proxy slice

**Context:** The generic loaded descriptor path already binds logical DSL pins to
physical `uio` pins and commits fixed-latency output actions, but no transducer
demo exercised a binding from one logical port to another.
**Decision:** Start transducer validation with a one-bit transparent A-to-B proxy
program using the existing descriptor ABI: `uio[0]` is the input and `uio[4]`
is the output. Preserve rise/fall behavior as two ordinary states and verify the
compiled program through both the reference model and generated RTL replay.
**Alternatives considered:** Adding a new mode opcode or a mailbox before
proving basic forwarding would enlarge the ABI and physical design without
isolating the first timing/ownership behavior. Calling the existing endpoint
examples proxy evidence would not demonstrate cross-port forwarding.
**Consequences:** The first proxy behavior is chip-loadable with no RTL or loader
format change and has an explicit cycle-level test. Multi-bit protocol
forwarding, rewrite policy, and the remaining translation/firewall semantics
remain open.
**Status:** implemented; Phase 6 completion pending

## 2026-10-02 — Complete the Phase 6 simulation gate with finite transducer slices

**Context:** The existing descriptor ABI can express fixed-latency edge actions,
sampled-byte comparisons, output release, and the already-implemented seeded
mutation/contract records. The five SPEC demos needed concrete simulation
evidence without adding a new mode opcode or widening the loader format.
**Decision:** Implement the remaining demo behaviors as small loadable DSL
programs: I2C address/register capture with stretch and delay mutations, SPI
JEDEC identity rewrite, SPI read-only firewall policy, and a one-bit clock-domain
translation slice. Add a single `scripts/phase6_demos.py` runner that compiles
each program, replays synchronized inputs in the reference model, and checks
the generated RTL runtime cycle by cycle. Keep the existing wire proxy as the
new-protocol demo.
**Alternatives considered:** Adding a general transducer-mode opcode or a
mailbox before the finite-state behavior is proven would enlarge the physical
design and make failures harder to localize. Calling host-only assertions
without generated RTL replay would not meet the simulation evidence requirement.
**Consequences:** All five demo scenarios and proxy/translation/rewrite/firewall
slices are now deterministic, chip-loadable simulation artifacts. The DSL still
does not claim arbitrary packet buffering or dynamic register storage; those
remain outside this finite Phase 6 slice.
**Status:** implemented; hosted physical validation pending

## 2026-10-03 — Quantify the current hosted physical-flow boundary

**Context:** Physical-flow closure requires actual routed area, utilization,
timing slack, DRC/LVS evidence, and confirmation against the 24-tile budget. The
current commit `8e278b014e82798a49bd886998278e25b77a265c` has a successful hosted
GDS run 24 (`36910900661`), but GitHub's public artifact API returns HTTP 401 for
the run's protected report bundles.

**Decision:** Record the evidence that is available without inventing missing
metrics. The current hosted GDS, precheck, gate-level, and viewer jobs all passed.
The viewer-deployed `tt_um_chimaera` OAS top cell measures `1289.28 × 710.64 µm`,
with an envelope area of `916213.9392 µm²` (`0.916213939 mm²`), and the checked-in
request is `6x4 = 24` tiles. Routed cell area, utilization, WNS/TNS slack, and
standalone DRC/LVS results remain **unavailable**, so the 50 MHz / 20 ns and
physical-fit gates remain open. The checked-in configuration explicitly sets
`RUN_KLAYOUT_DRC=0` and `RUN_KLAYOUT_XOR=0`, so hosted precheck success is not
relabelled as DRC/LVS closure.

**Alternatives considered:** Treating a green workflow as proof of timing margin
or treating the generic `35235`-cell Yosys count as physical area would violate
the project's generic-versus-IHP evidence boundary. Making an RTL or P&R change
without a failing physical metric would be speculative and could invalidate the
current green checkpoint.

**Consequences:** The exact-commit local gate and same-SHA hosted cocotb regression
are clean, but RTL is not frozen and the submission package is not yet declared
ready. Authenticated access to `GDS_logs` or equivalent numeric reports is the
next required action; only then can the project choose freeze/package versus a
targeted physical fix and hosted rerun.

**Status:** hosted flow passed; physical closure pending report extraction

## 2026-10-03 — Hold RTL freeze on extracted timing and antenna failures

**Context:** The extracted final reports for hosted run 24 and commit
`8e278b014e82798a49bd886998278e25b77a265c` provide the missing physical
numbers. The die is `916214 µm²` (`0.916214 mm²`) with `902417 µm²` core area
and `77.6363%` instance utilization; its `1289.28 × 710.64 µm` envelope matches
the declared `6x4 = 24` tiles. Magic DRC is zero, route DRC is zero, and netgen
LVS matches uniquely with zero mismatch counters. The final slow-corner setup
WNS is `-7.9532009896 ns` and setup TNS is `-1122.8959556 ns` at the 20 ns
target. The manufacturability report also records 3 antenna pin and 3 antenna
net violations.

**Decision:** Do not freeze RTL or prepare the submission package. Apply one
targeted P&R-only change: raise `PL_TARGET_DENSITY_PCT` from 60 to 70, retaining
the 20 ns clock, die size, tile allocation, and all RTL. Rerun the hosted flow
and judge closure using the worst-corner setup slack plus antenna, DRC, LVS,
utilization, and 24-tile results.

**Alternatives considered:** Relaxing `CLOCK_PERIOD` would hide the 50 MHz
requirement. Editing RTL before trying the flow's explicit `GPL-0302` density
warning would not be a targeted physical fix. Treating zero Magic DRC/LVS as
full manufacturability closure would ignore the reported antenna failures.

**Consequences:** The current physical result is recorded as a quantified
non-closure. The hosted rerun must be performed from the new configuration
commit; only a run with non-negative worst-corner setup slack and zero antenna,
DRC, and LVS failures can authorize RTL freeze and package preparation.

**Status:** targeted P&R adjustment prepared; hosted rerun pending

## 2026-10-03 — Require hosted rerun from the adjusted configuration commit

**Context:** Commit `8cab614e857874c35bad333fccd39b23a0effe52` contains only the
targeted placement-density adjustment and the physical evidence records. Its
clean local regression passed all existing host, demo, RTL, lint, and generic
Yosys gates; RTL source is unchanged.

**Decision:** Use `8cab614` as the next hosted-flow baseline. Do not combine any
RTL or clock-period changes with the P&R experiment. Replace the old physical
metrics only after the hosted GDS, precheck, gate-level, timing, antenna, DRC,
LVS, and tile-fit reports are extracted from this exact commit.

**Status:** local regression passed; hosted rerun pending

## 2026-10-04 — Keep RTL unfrozen after latest physical rerun

**Context:** The latest retained GDS artifact is from commit
`c1e860c1498d267341c8efe7e9fb16e985b06941` with placement target density 70
and a 20 ns clock. The 24-tile `6x4` envelope remains `1289.28 × 710.64` µm.
The measured instance utilization is `77.5267%`; antenna, Magic DRC, route
DRC, and netgen LVS all pass. Slow-corner setup remains negative at
`-5.1042833627` ns WNS and `-446.3203550849` ns TNS with `252` violations.

**Decision:** Keep the RTL unfrozen and do not prepare the submission package.
The density-only P&R change is retained because it removed the previous
antenna failures and materially improved timing, but it does not close the
50 MHz / 20 ns requirement. Any next attempt must remain targeted to physical
timing/P&R and must recheck the same area, utilization, timing, antenna, DRC,
LVS, and 24-tile gates.

**Alternatives considered:** Freezing on green workflows would ignore the
negative worst-corner setup slack. Relaxing the clock or changing RTL before
isolating a remaining P&R timing lever would violate the requested closure
criteria and targeted-fix boundary.

**Consequences:** The latest report supersedes the prior density-60 result for
current status, while the old artifact remains useful as a before/after
baseline. The design is physically cleaner but still not submission-ready.

**Status:** hosted rerun verified; timing closure pending

## 2026-10-04 — Replicate synchronized input banks for setup fanout

**Context:** The latest slow-corner path is the synchronized input bit feeding
the loaded runtime action logic: `input_frontend.sync_value[3]` reaches
`loaded_runtime.reaction_cell_0.action_value[0]` at `25.926 ns` against a
`20.641 ns` requirement, for `-5.285 ns` WNS. This is a setup/fanout problem;
another hold-margin adjustment does not remove the broadcast topology.

**Decision:** Restore `PL_RESIZER_HOLD_SLACK_MARGIN` to `0.10` and split the
input frontend into three named, hierarchy-preserved consumer banks: loaded
runtime, legacy reaction path, and execution engine. Each bank retains its own
two-flop synchronizer and previous synchronized sample, and locally derives
`sync_inputs`, `rise_edges`, and `fall_edges`. Preserve the existing logical
latency and signal behavior; do not add a downstream registered snapshot.

**Alternatives considered:** Keeping the `0.05` hold margin would continue to
target the wrong path. A downstream snapshot would be simpler but would add an
event-to-action cycle and require ABI/spec/regression changes. Plain duplicated
register declarations were rejected after Yosys merged them; explicit bank
instances with `keep_hierarchy`/`dont_touch` preserve the intended topology.

**Consequences:** The frontend now contains three physical synchronizer banks,
adding 48 synchronizer/history flops versus the former single bank. The local
generic Yosys hierarchy count is `35347`; this is directional only and is not a
physical area or timing result. The exact flattened synthesized netlist retained
three `input_frontend.{legacy,loaded,execution}_bank` instances. A hosted GDS
rerun is still required to measure the new slow-corner timing, area, utilization,
and signoff reports.

**Status:** confirmed by Hausen; local RTL gate passed; hosted physical rerun pending

## 2026-10-05 — Enable routed timing repair after diagnosing the exact report

**Context:** `GDS_logs_4343ee9/runs/wokwi/final/commit_id.json` identifies RTL
commit `4343ee9868400fb85a6dfa3238d4753c331cd2ac` and hosted workflow
`37219827449`. At 20 ns and target density 70, final slow-corner setup WNS is
`-3.6422794700 ns`, TNS is `-248.1556363971 ns`, and 249 endpoints violate
setup. Standard-cell area is `705103 µm²`, utilization is `78.1349%`, and the
`1289.28 × 710.64 µm` die retains the 24-tile envelope. Final route/Magic DRC,
LVS, antenna, and hold checks are clean. Slow-corner slew violations total 345;
fanout violations total 409, and the maximum capacitance violation count is 20.

The worst path starts at `input_frontend.loaded_bank.sync_previous[7]` and ends
at `loaded_runtime.reaction_cell_1.action_value[3]`. This endpoint stores a
descriptor action value, not the pin-drive output. The path passes through
event matching, shared rearm arbitration/address selection, the asynchronous
32-entry descriptor-memory read, and action-value selection. Its arrival is
`24.359962 ns` against a `20.717682 ns` requirement. Fifteen `fanout*` buffer
output arcs contribute `9.608169 ns`; one frontend hold-delay arc contributes
`0.615390 ns`. These are arc-delay contributions, not a prediction of how much
delay repair can remove.

Post-CTS repair loads fast, slow, and typical libraries, reports no setup
violations with estimated parasitics, then inserts 6,414 hold buffers. The
intermediate STA metrics report typical-corner slack only; they do not prove
slow-corner closure. More decisively, `resolved.json` sets
`RUN_POST_GRT_RESIZER_TIMING=false`, and `flow.log` explicitly skips
`OpenROAD.ResizerTimingPostGRT`. No timing-repair pass follows global routing.

**Decision:** Replace the proposed density-65 trial with one evidence-backed
P&R correction: set `RUN_POST_GRT_RESIZER_TIMING=true`. Preserve every RTL
source from `4343ee9`, `CLOCK_PERIOD=20`, density 70, and both hold margins.
The enabled step estimates parasitics from global routing and performs setup
and hold repair before detailed routing. The current flow's resizer default
already loads all three STA corners; adding a corner override is unnecessary.

**Alternatives considered:** Density 65 does not directly address the skipped
routed repair stage, and the earlier density 60-to-70 improvement does not
establish what 65 would do. Lower hold margins were already tried and do not
address this path's large fanout-buffer delay. An RTL redesign of descriptor
rearm or memory selection is a fallback if routed repair cannot close setup;
adding rearm latency would require explicit ABI/compiler timing consideration.
Neither false-path/multicycle exceptions nor clock relaxation are justified
by this functioning, same-cycle rearm path.

**Consequences:** This corrects a confirmed flow omission but is not a proven
timing fix. LibreLane documents post-GRT timing repair as experimental, with
possible longer runs or hangs. The new exact-commit final report must show
slow-corner setup WNS at least zero and zero setup violations while hold,
DRC/LVS, antenna, and tile fit remain clean. Also compare slew/capacitance
violations, area/utilization, and buffer counts. RTL freeze remains blocked.

**Status:** focused P&R correction verified locally; hosted physical rerun pending

The local gate passed 30 host tests, five Phase 6 demos, seven standalone RTL
benches, Phase 4 smoke, Verilator lint, and generic Yosys synthesis (35,347
hierarchy cells). The RTL diff against `4343ee9` is empty, and configuration
checks confirm that only the routed timing-repair switch changes. Cocotb was
not requested by this gate invocation; hosted gate-level and physical evidence
remain separate obligations.

## 2026-10-05 — Keep Phase 7 open after routed repair

**Context:** The exact hosted report for commit `922824e4a68a5ad210c46bb571526b53a2af9047`
and workflow `37285614053` confirms that the routed timing-repair stage ran with
the RTL, 20 ns clock, density 70, and hold margins preserved. It improved slow
setup WNS to `-3.1490615451 ns`, TNS to `-129.9196733635 ns`, and reduced setup
violations to 159, but did not reach non-negative WNS. Hold, antenna, route DRC,
Magic DRC, LVS, and the 24-tile envelope remain clean. KLayout DRC was skipped;
the final artifact also records 1,001 `EST-0026` missing-route warnings and four
disconnected pins, with zero marked critical.

The final worst path starts at `input_frontend.loaded_bank/_098_` /
`sync_value[2]`, crosses `loaded_rise_edges[2]`, and ends at
`loaded_runtime.reaction_cell_1.action_value[3]`. The post-GRT resizer reported
no setup violations using its estimated routed parasitics, while final detailed
route STA still reports the `-3.149061 ns` violation.

**Decision:** Treat workflow success as verified artifact generation and clean
signoff checks, not as Phase 7 timing closure. Keep `CLOCK_PERIOD=20`, density
70, both hold margins, and `RUN_POST_GRT_RESIZER_TIMING=true`. Keep RTL
unfrozen and investigate the loaded per-cell event/rearm fanout before changing
the clock or trying another unisolated P&R adjustment.

**Alternatives considered:** Freezing on a green workflow would ignore the
negative slow-corner slack. Repeating the hold-margin experiment does not target
this setup path. Adding a rearm cycle would change the fixed-latency contract and
requires an explicit ABI/spec decision, so it is not being introduced here.

**Consequences:** The routed-repair experiment is retained as a measured
improvement, but Phase 7's timing gate remains unmet. Any RTL topology change
must preserve fixed-cycle behavior, pass simulation and synthesis, and then be
validated by a fresh exact-commit hosted GDS run.

**Status:** hosted rerun verified; Phase 7 timing closure pending

## 2026-10-05 — Target the shared descriptor read and its control fanout

**Context:** Further inspection of the exact `922824e` slow-corner report maps
the worst path through cell 0's event matcher, arbitration/request-address
logic, the loader's descriptor-memory read, and cell 1's action-value reload.
The path contains 15 `fanout*` buffers with a combined cell delay of
`9.015922 ns`; this is measured path delay, not a prediction of recoverable
slack. All 159 reported setup violations originate from three loaded-bank
registers (133, 16, and 10 paths respectively). Most endpoints are descriptor
reload fields/control, but current output and fault-state registers also appear.
Reducing input fanout alone therefore does not address every remaining path.

**Decision:** Propose two isolated RTL experiments while retaining the 20 ns
clock, single descriptor read port, 32 x 128-bit ABI, and current arbitration
and cycle behavior:

1. Remove the unused idle-address-zero selection from the runtime. Keep the
   candidate request address on the read port even when no cell loads:

   ```verilog
   wire select_request_1 = !pending_0 &&
       (pending_1 || (!fire_0 && fire_1));
   assign descriptor_address = select_request_1 ? request_state_1 : request_state_0;
   ```

   Existing `service_0`/`service_1` and load enables retain their behavior.
   An exhaustive Boolean/address check passed 32,768 combinations, including
   15,360 combinations with an active read: whenever either cell loads, the
   proposed and current addresses are identical. This checks the address
   invariant only; simulation and synthesis remain required before adoption.

2. Evaluate a partitioned combinational descriptor read with local address
   decoders and balanced selection, starting with eight 16-bit output slices.
   The goal is to limit each decoded select's load rather than distribute a
   late binary select through a long global buffer tree. Preserve the local
   decoder boundaries only as needed and inspect the mapped netlist to ensure
   synthesis did not merge them back. This retains one logical read port and
   the existing storage; decoder replication can increase area and must be
   measured. Its physical benefit remains a hypothesis.

After each functional experiment, run the local verification gate and inspect
the synthesized control/memory topology. Only a fresh exact-commit routed
report can establish improvement or closure. If direct action/fault paths
remain critical, investigate local event/fire distribution separately.

**Alternatives considered:** More input synchronizer banks may reduce early
path loading but leave the shared read/arbitration chain. A second descriptor
read port duplicates substantial read logic. Registering the reload path changes
cell readiness and the accepted rearm schedule. In clarification of the previous
entry, changing rearm latency does not automatically change the current action's
event-to-output latency; these are distinct contracts, and both need validation.
Those larger architecture choices are deferred pending measurements and an
explicit design decision.

**Consequences:** No RTL or P&R configuration has changed in this analysis.
The user reports that the downstream precheck is still running; the completed
GDS build does not establish a completed workflow or final submission signoff.
Let that check finish while preparing local candidates. All 1,001 `EST-0026`
warnings occur in the intermediate post-GRT repair log, not final detailed-route
STA. The disconnected-pin table lists exactly `ena` and reserved `ui_in[5:7]`,
which `project.v` explicitly marks unused; these counts are not evidence of four
broken functional nets. Final slew/capacitance/fanout violations remain real
electrical constraints to inspect alongside setup, and precheck may add findings.

**Status:** proposed; source/netlist diagnosis and address invariant verified;
RTL implementation and physical validation pending

## 2026-10-05 — Implement candidate selection and four local read decoders

**Context:** After discussing decoder replication's possible area cost, Hausen
approved implementation with "ok implement it". The address-only change passed
all seven standalone RTL benches before decoder experiments. Separate snapshots
of the original `922824e` sources and the address-only sources were retained for
the local comparison; the current hosted precheck was not modified or replaced.

**Decision:** Implement the candidate-address selection and partition the one
logical descriptor read into four 32-bit slices with independent row decoders
and balanced OR selection. Preserve hierarchy and prevent merging only at each
decoder instance, allowing storage and the remaining read logic to optimize.
Keep the original 32 x 128-bit memory, write interface, arbitration, output
latency, and bounded rearm schedule. No clock, tile, density, hold-margin, or
workflow configuration changed.

**Alternatives considered:** Eight 16-bit slices reduce each select's load
further, but four 32-bit slices use less logic in the local comparisons. The
initial experiment preserved whole read slices and kept 64 otherwise-unused
descriptor bits alive at the top level. Narrowing the preserved boundaries to
decoders removes that storage penalty. An address-only implementation removes
five generic muxes before ABC but does not address the memory read distribution.

The following measurements use the same local Yosys `synth -flatten -noabc`
followed by `abc -g simple` pipeline. Counts exclude `$scopeinfo` metadata and
include all instantiated submodules. They are generic logic counts, not IHP
standard-cell area, utilization, or delay; differences in gate mix and mapping
mean a higher pre-ABC count need not mean a higher physical area.

| Experiment | Pre-ABC generic cells | After ABC simple mapping | Pre-ABC register bits |
|---|---:|---:|---:|
| Original full top | 26,269 | 28,423 | 5,831 |
| Address-only full top | 26,264 | 28,821 | 5,831 |
| Original loader only | 10,006 | 13,643 | 4,683 |
| Whole 16-bit read slices, loader only | 14,847 | 14,393 | 4,683 |
| Whole 32-bit read slices, loader only | 14,474 | 14,108 | 4,683 |
| Whole 16-bit read slices, full top | 31,232 | 28,496 | 5,895 |
| Decoder-only boundaries, 16-bit slices, full top | 31,040 | 28,238 | 5,831 |
| Decoder-only boundaries, 32-bit slices, full top (selected) | 30,668 | 27,713 | 5,831 |

The selected implementation has 710 fewer generic mapped cells (about 2.50%)
than the original top and the same pre-ABC storage count. This screens out an
obvious mapped-count/storage regression; it does not establish physical area
or timing improvement. The existing unflattened local-verify pipeline reports
39,810 hierarchy cells, versus its prior 35,347 baseline; the initial whole
16-bit slice candidate reported 40,183. Those counts use a different pipeline
from the table and must not be compared directly to its mapped totals. No local
physical area or slack is available because the IHP PDK and OpenROAD are absent.

**Consequences:** The final local gate passed 30 host tests, all five Phase 6
demos, seven standalone RTL benches, Phase 4 smoke, lint, generic synthesis,
and the new topology/equivalence checks. The expanded loader bench performs
512 word writes over all 32 rows and eight ABI words, including rewrites, and
64 full asynchronous row reads; known written words remain readable while
other words are uninitialized. The runtime bench checks consumed addresses
and retains its same-edge simultaneous actions and pending-first rearm checks.

`scripts/check_descriptor_read.py` is part of local verification: it checks
four distinct decoders after flattening, 128 separate row-select nets, a
maximum fanout of 32, and no decoder storage. The same structure check passed
on the ABC-mapped candidate. A SAT proof establishes that a 32-bit read slice
equals the original indexed read for every five-bit address and arbitrary
1,024-bit contents. Four-state/uninitialized-memory behavior is covered by
simulation separately. Cocotb was skipped because no environment is available;
the existing local gate's host-generated RTL replays and standalone benches ran.

The next physical checkpoint is a new exact-commit hosted GDS run comparing
area, utilization, all-corner setup/hold, electrical constraints, DRC, antenna,
LVS, and tile fit against `922824e`. The ongoing precheck belongs to the old
GDS artifact and remains separate evidence. Phase 7 stays open.

**Status:** confirmed by Hausen; implemented and locally verified; physical
validation pending

## 2026-10-06 — Accept the early-decode descriptor-read timing remedy

**Context:** The exact `2bf7f369` report still failed slow setup on the loaded
event/rearm-to-descriptor path. The mapped diagnosis showed that a late binary
request address was driving the shared asynchronous descriptor read through a
large fanout tree.

**Decision:** Keep the 32 × 128-bit descriptor ABI, one logical read port,
20 ns clock, same-edge action behavior, and pending-first rearm schedule, but
decode each preserved candidate state address before arbitration and select the
already-decoded row afterward. Four 32-bit read slices retain independent
5-to-32 decoders with bounded row-select fanout; the late selector chooses one
decoded row per slice.

**Evidence:** The universal SAT miter proves equivalence to the original
indexed read for arbitrary candidate addresses, decisions, and memory contents.
The local gate passes the expanded selector/read tests, topology checks, lint,
and synthesis. A matched OpenROAD screen improved global-route setup from
`-0.70 ns` / `-6.03 ns` TNS on the baseline to `+2.83 ns` / `0 ns` TNS on the
candidate. The screen is not hosted signoff: it reports congestion and omits
detailed routing, extracted SPEF, DRC/LVS, antenna, and KLayout checks.

**Consequences:** The RTL remedy is accepted for an exact-commit hosted GDS
rerun. Physical closure remains open until that workflow produces fresh
slow-corner timing and complete signoff evidence.

**Status:** confirmed by Hausen; locally proven; hosted physical validation pending

## 2026-10-06 — Reject four-bank replication after exact hosted timing

**Context:** Exact hosted GDS run `37435108709` for commit `934ea8b` completed
the GDS and gate-level jobs but reported slow setup WNS `-7.04375 ns`, TNS
`-647.88482 ns`, and `280` violations. Hold still passed with zero violations.
The worst path again starts at `input_frontend.loaded_bank/_098_/Q`; the four
selector banks added enough physical replication/congestion to make the real
flow worse than the `2bf7f369` baseline.

**Decision:** Reject the four-selector implementation for physical closure.
Share the eight early decoders in two selector banks, with each bank feeding
two adjacent 32-bit read slices. This cuts replicated decoder logic while
retaining the registered candidate inputs, one logical read port, fixed ABI,
same-edge actions, and pending-first rearm behavior.

**Evidence:** The two-bank RTL passes the full local gate, selector simulation,
topology check, SAT equivalence, lint, and synthesis. The matched local routed
screen reports `+0.65 ns` setup WNS, `0 ns` TNS, `+0.03 ns` hold slack, and
`702,469 µm²` / `78%` utilization, versus the baseline screen's `-0.70 ns`,
`-6.03 ns`, `+0.01 ns`, and `690,697 µm²`. It still reports global-route
congestion, so a fresh exact-commit hosted GDS is required.

**Status:** confirmed by Hausen; four-bank candidate rejected; two-bank candidate pending hosted validation

## 2026-10-07 — Hold production and isolate per-context descriptor reads

**Context:** The exact hosted GDS run for the current two-bank production
candidate completed as workflow `37508588226`. Its worst slow-corner path
contains `loaded_runtime.select_request_1` at `15.292 ns`, then the shared
descriptor selector/read network, and arrives at the endpoint at `27.560 ns`.

**Decision:** Keep the production RTL and its 20 ns clock, 32 × 128-bit
descriptor ABI, pending-first grant equations, same-edge actions, and existing
rearm schedule unchanged. Evaluate the proposed two-combinational-read
topology only as an isolated candidate: each context owns event, alternate,
timeout, and pending successor selection, while the existing arbiter controls
only `load_0` and `load_1`. Retain two 64-bit selector banks per context and
require a full integrated implementation before any adoption decision.

**Evidence:** The isolated read prototype passes 128 full-width decision
patterns and the reload-data SAT proof. Its IHP mapped read-cone screen rises
from `48,092` to `81,278 µm²` (`+33,185 µm²`); this is not a full-design area
or routed result. The exact production artifact identifies commit
`dc2287144c0042ecdfc21a243ac17d616a9dcac0` and reports slow setup WNS
`-6.7110816581 ns`, TNS `-1086.7175058528 ns`, and `281` setup violations;
hold WNS/TNS are `0`. DRC, LVS, antenna, and power-grid checks are clean, but
the timing gate is unmet.

**Consequences:** No production RTL, workflow, commit, or push changes are
made by this evaluation. The candidate must next be integrated through both
runtime buses, prove full reload/action equivalence, pass the complete local
gate, and receive an exact-commit hosted report with positive slow-corner WNS,
zero setup TNS/violations, clean hold/signoff, and 24-tile fit before it can
replace production.

**Status:** proposed isolated candidate; production held; Phase 7 open

## 2026-10-07 — Accept the local functional gate; hold physical adoption

**Context:** The isolated two-combinational-read topology was integrated
through both runtime buses without changing production RTL, the 20 ns clock,
the 32 × 128-bit descriptor ABI, same-edge actions, or pending-first rearm
behavior. The replay generator now selects the candidate read interface only
when an alternate source root is requested; the default production interface
remains unchanged.

**Evidence:** The candidate gate passed 30 host tests, all five Phase 6 demos,
the adapted loader/host/fault benches, a 528-case per-context selector bench,
the integrated runtime bench, Phase 4 smoke, strict Verilator lint, Yosys
synthesis, topology inspection, and the two-private-bus SAT proof. The
clock-by-clock production/candidate miter passed 260 cycles while observing
`54` simultaneous fires, `54` deferred reloads, `160` timeouts, both branch
outcomes (`205` true / `64` false), `106` dynamic-selector cases, and `244`
saturated-run cycles. It compared the external action/fault/contract outputs
plus pending state, active controls, cell state/timers/actions, and shift/count
state after every edge.

The mapped candidate retains four context selector banks with four early
decoders each; row-select nets remain distinct and max at fanout `64`, while
candidate addresses are register-driven and no cross-context grant enters the
loader selector. The remaining arbitration-to-load path is still visible in
the runtime equations; local structural evidence cannot determine its routed
delay. The matched full-top generic Yosys+ABC screen is `32,633` production
cells versus `40,369` candidate cells (`+7,736`, `+23.71%`). This is a generic
screening count only, not physical area.

**Decision:** Accept the candidate as locally functionally equivalent and keep
it isolated for physical evaluation. Do not replace production based on this
gate or the generic area count. A future exact-commit hosted run must establish
positive slow-corner setup WNS, zero setup TNS/violations, clean hold and
electrical/signoff reports, and 24-tile fit before any adoption decision.

**Consequences:** The production source tree, workflow files, commit history,
and remote state remain unchanged. The isolated candidate has no hosted GDS,
routed timing, utilization, DRC/LVS, antenna, or tile-fit evidence; Phase 7
remains open.

**Status:** locally functionally proven; physical adoption deferred
