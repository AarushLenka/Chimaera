# Chimaera decisions

## 2026-09-22 — Rename project from ChronoWeave to Chimaera

**Context:** The project name was changed by the owner.
**Decision:** Use `Chimaera` in project documentation and `tt_um_chimaera` as the Tiny Tapeout top-level module name.
**Alternatives considered:** Keeping the old name would leave repository metadata and implementation instructions inconsistent.
**Consequences:** Documentation, metadata, and the template testbench now use the new project name; no hardware behavior was changed.
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
