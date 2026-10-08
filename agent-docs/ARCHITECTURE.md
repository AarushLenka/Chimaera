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

A shared execution block serves both reaction cells whenever a cell needs
bookkeeping work between firing and its next state being ready. Each context
has a local combinational successor decoder over the shared memory. The two
decoded one-hot rows feed one shared final descriptor read bus; pending-first
arbitration selects between those already-decoded rows and controls the reload
enables. Simultaneous cells still commit their locally predecoded actions on
the same fixed-latency edge; one descriptor reload occurs on that edge and the
deferred reload is guaranteed the following edge, before any new request. Thus
rearm latency is at most two inclusive cycles without making reaction latency
contention-dependent.

A deferred cell is unarmed during its reload edge, so an external event arriving
on that edge is not captured. Until the DSL can declare and prove protocol timing
requirements, a two-context manifest therefore records a minimum safe two-cycle
inter-event spacing assumption rather than claiming unconditional schedulability.

The small counter/shift successor calculation is retained per context in this
checkpoint so both next-state decisions are captured on a simultaneous fire. The
logic costs 276 generic cells, versus 9,214 for the descriptor loader, and avoids
adding another queued sample/control record. Revisit that trade only if physical
hardening shows it is worthwhile.

Each loaded context precomputes its branch predicate for both possible serial
sample bits from registered shift/count/control, mutation records, and LFSR state.
The synchronized sampled input selects between those two Boolean results. A
retained combinational module boundary keeps byte mutation and comparison ahead
of the late sampled-bit choice through synthesis. This removes those operations
from the input-to-descriptor selection path without adding storage or changing
the same-edge action/reload schedule. A universal SAT check covers arbitrary
state, samples, and all four mutation records; the runtime comparison uses frozen
pre-lookahead execution logic as its reference.

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

- 32 fixed 128-bit state descriptors (4,096 bits), runtime-writable as eight
  16-bit words per descriptor. This replaces the original 128-entry synthesis
  starting point after the measured comparison in `PHASE5_ABI_PROPOSAL.md`.
- 32–64 compressed trace entries (supports both `SPEC.md` §9's contract-violation
  capture and §10's capture/replay trace buffer — these can likely share the same
  physical buffer; if implemented separately, log why in `decisions.md`).
- A few bytes of mailbox storage.

The descriptor memory has one shared combinational 128-bit read bus and one
shared write port. Each context has one selector decoding its four registered
event, alternate, timeout, and pending successor state IDs. A separate
pending-first grant chooses between the two already-decoded one-hot rows, then
two read selector banks feed adjacent 32-bit slices. The grant therefore adds
one shallow row mux after local decode instead of selecting among binary
addresses before the decoder. Decoder and selector hierarchy is retained
through technology mapping; storage and read-data logic can still optimize
across the top level.

The runtime exposes registered candidates, six local decision bits, and the
separate final-row grant. The loader duplicates the shared 128-bit result into
the existing 256-bit interface, while only one reload is serviced per edge.
The memory contents, loader stream/CRC, load enables, same-edge actions, and
inclusive two-cycle rearm schedule retain their prior behavior, with no added
register. Local SAT proves a complete 32-bit read slice against the selected
context reference for arbitrary candidates, decisions, grant, and memory data;
the four identical slice instances are structurally checked in the top-level
netlist. Physical signoff still requires a new exact-commit routed report.

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

The Phase 5 interface samples active-low CS, serial clock, and MOSI on dedicated
inputs, with MISO on `uo_out[0]` while CS is active. Thirty-two-bit MSB-first
frames are synchronized into the 50 MHz system domain, so configuration SCLK is
limited to less than one quarter of the system clock (12.5 MHz at the current
target). `BEGIN` halts execution before writes; `COMMIT` checks complete ordered
records, CRC, context entries, and all successor targets; a separate `CONTROL`
frame resumes a valid program.

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

The Phase 6 implementation keeps this stage separate from the descriptor ABI.
Each context has four 32-bit mutation records loaded through dedicated
configuration opcodes, and a shared seeded 16-bit LFSR. The fault stage can
mutate a sampled shift-register value, delay or suppress a predecoded action,
hold a selected pin low, repeat a selected action, or defer a selected release
by a bounded byte-sized interval. Open-drain output drive remains behind the
existing low-only mask, including all fault paths. Pin-targeted records carry
the bound physical pin in their low three bits; data/action records retain the
seeded threshold there.

## 8. Contract/assertion checker

A small comparator/window-logic block that watches the same synchronized signals
as the reaction cells, evaluates armed temporal assertions (grammar defined in
`DSL_SPEC.md`), and on violation performs all four actions from `SPEC.md` §9
(trigger output, freeze trace, record violation + timestamp, release driven pins)
without halting the reaction cells' continued operation. The current compact
records cover stable-while, high-width minimum/maximum, event-within, and
negative pin conditions. The monitor uses four trace entries, records the first
violating record, and releases outputs for one cycle so execution can resume.

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
temporary selectors and descriptor sources remain only as a reset-time fallback
for Phase 4 regression. Receipt of a Phase 5 `BEGIN` frame transfers the
bidirectional pins to the loaded runtime and releases them while loading/halted.

## 10. Phase 5 loader/runtime checkpoint

The compiler emits the accepted 32 × 128-bit descriptor format and a CRC-protected
loader stream for protocol and supported Phase 6 sources. Two generic reaction
cells execute the loaded descriptors. Their event/action fast paths are
independent; descriptor rearm uses two local candidate decoders followed by a
shared final read bus with the bounded pending-first reload policy in §3.
Mutation and contract records stay outside the descriptor fast
path. The final output stage masks values on compiler-declared open-drain pins,
making an active high drive structurally impossible even for malformed
descriptor or fault action bits.

Unit simulation covers frame synchronization and partial-frame recovery, ordered
writes, CRC and target rejection, compiler-stream loading, event/timeout execution,
simultaneous two-context arbitration, halt-time pin release, and full top-level
serial loading. Generic synthesis reports 12,344 cells. This is not a physical-fit
claim; IHP hardening is still required.

## 11. What to build in what order (mirrors `IMPLEMENTATION.md`, restated here for
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
