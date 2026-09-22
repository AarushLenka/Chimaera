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
