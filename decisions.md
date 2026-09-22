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
