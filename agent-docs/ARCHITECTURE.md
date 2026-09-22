# ARCHITECTURE.md — Chimaera Hardware Architecture

This document describes the hardware block structure implementing `SPEC.md`.
Where this document gives specific numbers (bit widths, memory sizes, cell
counts), treat them as a **starting point for synthesis, not a fixed constraint**
— `SPEC.md` §2 and Jane Street's own guidance require verifying real numbers via
synthesis and place-and-route rather than assuming these are correct. When real
numbers are obtained, update this document and log the change in `decisions.md`
per `AGENTS.md` §8.

## 1. Top-level split: fast reaction path vs. shared execution path

The chip is split into two cooperating parts:

- **Reaction cells** (§2) — small, fast, per-context state holders that sleep
  until a specific event or timeout occurs, then react with fixed latency.
- **Shared execution engine** (§3) — a slower, shared datapath that does
  bookkeeping (shifting bits, counting, comparing, computing CRCs) and loads the
  next state into a reaction cell after it fires.

This split is what lets multiple "logical protocol machines" exist without
duplicating a full processor per protocol — the expensive, general-purpose part
(the execution engine) is shared and time-multiplexed; the cheap, fast part
(reaction cells) is duplicated because it's small.

## 2. Reaction cells

Start with **two physical reaction cells**, parameterized so the count can be
changed (e.g. testing whether four fit) without a structural rewrite. Do not build
more than two for v1 (see `SPEC.md` §6).

Each reaction cell stores:

| Field | Purpose |
|---|---|
| Current state ID | Which microprogram state this context is in. |
| Event mask + polarity | What pin pattern/edge this state is waiting for. |
| Level condition | Optional level-based (not just edge-based) wait condition. |
| Deadline / timeout | How long to wait before the timeout successor fires instead. |
| Predecoded pin action | Set/clear/release/output-enable masks, precomputed so they can be committed immediately on event match — no decode-time delay. |
| Sample mask | Which input pins to latch into working data when the event fires. |
| Event successor | Next state ID if the event condition is met. |
| Timeout successor | Next state ID if the deadline is hit first. |
| Small counter/shift metadata | Minimal per-context scratch state (e.g. bit count within a byte). |

**Core timing guarantee (must hold for every cell, every mode):** once an event is
detected by the input synchronizer and event matcher, the predecoded pin action is
committed with a **fixed, statically known latency** — always the same number of
cycles for a given action, regardless of what other reaction cells are doing.
Because asynchronous external inputs require synchronization first, the guarantee
is stated as "fixed cycles after the *synchronized* event is observed," not
"instantaneous." This is the mechanism behind `SPEC.md` §3's central claim and must
be preserved through every RTL change — treat any code path that makes this latency
data-dependent or contention-dependent as a correctness bug, not a style issue (see
`AGENTS.md` §4).

## 3. Shared execution engine

A single shared datapath used by all reaction cells, scheduled (earliest-deadline
or fixed-priority — pick whichever is simpler to implement correctly and verify;
log the choice in `decisions.md`) whenever a cell needs bookkeeping work done
between firing and its next state being ready.

Starting components:

- 16-bit datapath.
- One serial shift unit (for sampling/emitting protocol bits).
- One counter/comparator.
- One CRC/LFSR unit (doubles as the fault-injection pseudo-random source, per
  `SPEC.md` §8 — reuse rather than duplicate this block if the timing/area budget
  allows; log the decision either way).
- A small register bank per context.
- A shared mailbox/FIFO (for transducer-mode data passing between ports, and for
  data reaching the host configuration interface).
- The scheduler itself.

## 4. Real-time front end (shared, before reaction cells)

- Input synchronizers (standard 2-flop or configurable 2-/3-stage synchronizers
  for every external input, to correctly handle asynchronous signals — this is
  also *why* the timing guarantee in §2 is phrased "after the synchronized event,"
  not "instantaneous").
- Rising/falling-edge detectors.
- Pin-pattern comparator (for masked-pattern wait conditions).
- Per-pin inversion (cheap way to support polarity differences between
  protocols/devices without separate logic).
- Optional 2- or 3-sample glitch filtering (configurable, since some protocols
  need it and some don't — don't pay the area cost unconditionally if it can be
  gated).
- Input snapshot register.
- Configurable push-pull/open-drain output control per pin — this is the hardware
  mechanism enforcing `SPEC.md` §13's "open-drain pins never actively drive high"
  static-check guarantee; the RTL must make driving high on an open-drain-mode pin
  structurally impossible, not just discouraged by convention.

## 5. Memories

Starting point (verify and adjust via synthesis, per the note at the top of this
document):

- 128 state descriptors (program/configuration memory for reaction cell states).
- Small program/configuration SRAM.
- 32–64 compressed trace entries (supports both `SPEC.md` §9's contract-violation
  capture and §10's capture/replay trace buffer — these can likely share the same
  physical buffer; if implemented separately, log why in `decisions.md`).
- A few bytes of mailbox storage.

Trace memory should stay small by design (see `SPEC.md` §9's "capture the first
violation plus a small window" property) — resist the temptation to grow trace
depth "to be safe." Small, well-targeted capture is a deliberate feature, not a
limitation to work around.

## 6. Host configuration interface

A small SPI-like interface implementing `SPEC.md` §12's function list. Deliberately
**not** a general-purpose CPU. This is a scope and area decision, not an oversight —
a full CPU for configuration would eat area budget better spent on reaction cells
and the execution engine, and would reintroduce exactly the "generic processor with
GPIO instructions" architecture rejected in `SPEC.md` §4. If a future need seems to
require more than this interface can do, treat that as a signal to revisit the
*protocol/mode design*, not to grow the configuration interface into a CPU.

## 7. Fault injection hardware

Implemented as a small conditional-modification stage sitting between a reaction
cell's predecoded pin action and the actual pin drive, gated by:

- A condition evaluated against current transaction state (address, byte position,
  transaction count — sourced from the shared execution engine's counters/
  registers).
- The shared LFSR (§3) for any pseudo-random component, always seeded
  deterministically per `SPEC.md` §8's reproducibility requirement.

The fault stage must never be able to violate the open-drain safety property in
§4 — a fault can *change timing or data*, but the same structural pin-safety
guarantees apply to fault-modified output as to normal output. This is a hard
constraint, not a corner case to handle later.

## 8. Contract/assertion checker

A small comparator/window-logic block that watches the same synchronized signals
as the reaction cells, evaluates armed temporal assertions (grammar defined in
`DSL_SPEC.md`), and on violation performs all four actions from `SPEC.md` §9
(trigger output, freeze trace, record violation + timestamp, release driven pins)
without halting the reaction cells' continued operation.

## 9. Phase 4 implementation checkpoint

The current RTL instantiates the two planned reaction cells. Cell 0 retains the
UART descriptor program on Port A (`uio[0:1]`); cell 1 selects the temporary I2C
target or SPI mode-0 target descriptor program from `ui_in[1:0]` and uses Port B
(`uio[7:4]`). Both cells feed one `chimaera_execution_engine` instance. Each
context has its own small shift/count state, while descriptor matching and
predecoded output actions remain local to the reaction cell, so one context
cannot add variable event-to-output latency to the other.

I2C SDA/SCL output enable is clamped to low-only at the top-level output stage;
the I2C program can request a low drive or release but cannot produce a driven
high. SPI MISO is additionally gated off whenever synchronized CS is high, so a
truncated transaction releases the output before the next transaction. The
temporary selectors and descriptor sources will be replaced by the host loader
in Phase 5; they are not the final program-memory implementation.

## 10. What to build in what order (mirrors `IMPLEMENTATION.md`, restated here for
build-time reference)

1. One reaction cell + shared execution engine minimum viable slice, UART only.
2. Synthesize, get real area/timing numbers, update this document.
3. Second reaction cell, add I2C and SPI.
4. Re-synthesize, compare area growth.
5. Transducer modes (§7 of `SPEC.md`), fault injection (§7 of this doc), contract
   checker (§8 of this doc).
6. Full place-and-route of the complete v1 design.

Do not build components from step 5 before steps 1–4 are verified in simulation
*and* synthesized with real numbers recorded. This project's biggest risk is
discovering an area or timing problem late, after a lot of higher-level feature
work has been built on top of an unverified foundation.
