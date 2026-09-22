# SPEC.md — Chimaera Functional Specification

## 1. One-sentence description

A two-port, event-driven timed-transducer ASIC with fixed-latency reaction cells,
deterministic fault injection, runtime temporal-protocol assertions, and a formally
checked protocol DSL — submitted to Tiny Tapeout for the Jane Street–sponsored
competition, deadline **January 18, 2027**.

## 2. Competition constraints (hard limits)

- **Area budget:** 24 Tiny Tapeout tiles, ≈0.7 mm², roughly 24,000 logic cells
  *before* routing/overhead is subtracted. Treat the real usable budget as lower
  than the raw cell figure.
- **Deadline:** January 18, 2027.
- **Judging emphasis (per Jane Street):** unique functionality and novel design and
  verification methods — not "supports the most protocols."
- **Pin budget (standard Tiny Tapeout wrapper):** 8 dedicated inputs, 8 dedicated
  outputs, 8 bidirectional pins. Exact assignment is in `PIN_MAP.md` and must be
  kept in sync with it.
- Jane Street's own stated advice: synthesize and run full place-and-route early.
  A design that looks fine after synthesis can still fail routing or timing. This
  project's phase ordering (see `IMPLEMENTATION.md`) is built around taking that
  advice seriously.

## 3. Core architectural claim

> Every armed protocol state has a **statically bounded event-to-output latency**,
> independent of what other sleeping contexts are doing — specifically, a fixed
> number of cycles after the synchronized event is observed (not claiming
> instantaneous response, since asynchronous inputs require synchronization).

This is the project's central technical differentiator and must hold for every
reaction cell in every mode. See `ARCHITECTURE.md` §2 for the hardware mechanism
that makes this true, and §4 (below) for why this matters more than raw protocol
count.

## 4. Why this design over alternatives (context, not a decision to revisit)

Two more obvious approaches were considered and rejected before landing on this
architecture — recorded here so the agent understands *why*, not just *what*:

1. **A tiny general-purpose processor with protocol instructions** (`WAIT_PIN`,
   `SET_PIN`, `SHIFT`, `DELAY`). Rejected: this is difficult to distinguish from the
   RP2040's existing PIO architecture (8 state machines, 2 PIO blocks, 9-instruction
   ISA), and open-source Verilog reimplementations of PIO-like hardware already
   exist. Low novelty for a competition that explicitly values novel design.
2. **Separate fixed hardware blocks per protocol** (a UART block, an SPI block, an
   I2C block, muxed together). Rejected: doesn't scale to "protocols not known at
   design time," which is the whole point of the entry, and doesn't produce an
   interesting architectural story.

The chosen direction — one shared, generic, event-driven engine, programmed
per-protocol after fabrication — is what makes the final demo (Demo 5: loading a
brand-new protocol post-fabrication with no RTL change) possible at all.

## 5. What's in v1 (must work for submission)

- Two reaction cells sharing one execution engine (see `ARCHITECTURE.md` §2–3).
- Protocol support: **UART, I2C, SPI**.
- Bidirectional transducer modes (§6 below): endpoint, transparent proxy,
  translation, rewrite, protocol firewall.
- Deterministic, seeded fault injection (§7).
- Runtime timing-contract assertions (§8).
- The protocol DSL, its compiler, and static safety checks (§9, full grammar in
  `DSL_SPEC.md`).
- Host-side capture → compile → replay tooling (§10) — **host-side only**, never
  on-chip inference.
- All five demos in §11 working end to end in simulation, then on real silicon
  after fabrication.

## 6. What's explicitly NOT in v1 (stretch only, after v1 passes place-and-route)

- USB, CAN, Ethernet — if attempted at all, digital framing/encoding only, using an
  external electrical transceiver/PHY. **Never claim full electrical-layer
  compliance from GPIO alone.**
- SMT-based program synthesis ("supercompilation" — using a solver to find the
  shortest correct microprogram for a target waveform contract). Interesting
  future direction, out of scope for this deadline.
- More than two reaction cells.
- Any on-chip machine learning or autonomous protocol inference.

If synthesis/place-and-route pressure forces cuts, cut from this list's *later*
entries first, but the entire list is expendable before touching §5.

## 7. Bidirectional transducer modes

Two logical sides, Device A and Device B, each connected through a logical "port"
(exact pin mapping in `PIN_MAP.md`; the four-bidirectional-pins-per-side split is
the reference allocation, not a hard requirement if `PIN_MAP.md` specifies
otherwise).

| Mode | Behavior |
|---|---|
| **Endpoint** | Chip acts as one side of the protocol itself (e.g. an I2C sensor, SPI peripheral, UART device). |
| **Transparent proxy** | Forwards all traffic between A and B unchanged, while recording it to the trace buffer. |
| **Translation** | Converts one protocol/parameter to another while forwarding — e.g. UART baud rate conversion, UART-to-SPI, polarity/bit-order changes. |
| **Rewrite** | Forwards traffic but deliberately modifies specific fields — e.g. replacing an SPI flash JEDEC ID, patching one register value, hiding a debug register. |
| **Firewall** | Forwards traffic selectively per a policy — allows/blocks specific transaction types, addresses, or commands (e.g. allow SPI flash reads but block writes/erases); can disconnect/release all outputs on a policy violation. |

Mode selection and configuration happens via the host configuration interface
(§12), not via RTL changes.

## 8. Deterministic fault injection

Faults are **transaction-state- and timing-dependent**, not generic random bit
flips. Example forms (illustrative, not exhaustive — the DSL in `DSL_SPEC.md`
defines the actual expressible fault grammar):

- Conditional delay/NACK/drop based on address, byte position, or transaction
  count (e.g. "delay ACK by 3 cycles when address == 0x48 and transaction_count %
  17 == 0").
- Timing violations of a bounded, specified size (e.g. shorten a clock-high pulse
  by an exact number of cycles, violate stop-bit timing by exactly N cycles).
- Bounded jitter on selected transitions.
- Bit/CRC corruption while preserving payload structure.
- Clock stretching, duplicated edges, late-released open-drain lines.

**Reproducibility requirement:** every fault run must be exactly replayable from
`(program hash, random seed, trigger count)`. Use a small LFSR (linear-feedback
shift register) for the pseudo-randomness source — this is a hardware-cheap,
well-understood, and fully deterministic-from-seed choice.

## 9. Runtime protocol contracts (timing assertions)

Compact temporal assertions armed alongside a running protocol program, e.g.:
"signal X must stay stable while signal Y is high," "signal X's high pulse must be
at least N cycles," "event Y must occur within N cycles after event X." Full
assertion grammar in `DSL_SPEC.md`.

On violation, the chip must (all four, not a subset):
1. Raise a trigger output.
2. Freeze the trace buffer.
3. Record which contract was violated and when.
4. Release all actively driven pins (fail safe, not fail driving).

...while continuing to operate and incrementing a violation counter (a violation
is recorded, not fatal to the chip's operation).

**Key hardware property:** the monitor must capture the *first* violating
transition plus a small window of events immediately before and after it — not
attempt to buffer large amounts of normal, non-violating traffic. This keeps trace
memory small (see `ARCHITECTURE.md` §5) while still being maximally useful for
debugging.

## 10. Capture → compile → replay (host-side)

1. On-chip: record `(delta_time, changed_pin_mask, new_pin_values)` into a small
   trace buffer, using variable-length/run-length encoding so idle gaps cost little
   storage.
2. Host tool: reconstruct the waveform, detect repeated subsequences, estimate
   likely symbol durations, convert repeated behavior into states/loops, emit
   executable DSL/microcode, and allow the user to parameterize specific fields
   (e.g. "this byte is a variable, not a constant").
3. Optional replay variants: original timing, half/double speed, fixed jitter,
   reproduced measured jitter, one deliberately malformed pulse.

**Hard constraint:** all inference/compilation stays on the host. The chip's role
is strictly record (small buffer) and later replay (execute a compiled program) —
never on-chip autonomous protocol inference. This is both a scope-control decision
and a correctness one: keeping "smart" work off-chip means the chip's behavior
stays fully specified and provable (§13), which matters for the safety guarantees
in §8/§13 and for area.

## 11. Demo script (five demos, same physical chip, no RTL changes between them)

1. **Basic compliance.** Load UART, SPI, and I2C programs; demonstrate standard
   transmit/receive behavior for each.
2. **I2C sensor impersonation.** Chip behaves as a temperature sensor with
   writable registers, clock stretching, and configurable response delay.
3. **SPI flash identity patch.** Chip sits between a controller and a real SPI
   flash device, forwards normal reads, but replaces the JEDEC ID response
   (rewrite mode, §7).
4. **Reproducible fault.** Configure a fault (e.g. "NACK every 17th access to
   register 0x03"), show the exact same failure recurring after reset with the
   same seed (§8).
5. **New protocol after fabrication.** Load a protocol that was never planned for
   at design time (PS/2, one-wire, pulse-width, or a custom protocol) purely by
   loading a new program — zero RTL changes. This demo is the direct answer to the
   competition's central requirement that the chip stay useful for protocols not
   hard-wired before fabrication, and must not be cut under any scope pressure.

Each demo needs a corresponding simulation test (see `AGENTS.md` §6) before being
considered complete, and later a real-silicon validation once chips are back from
fabrication (Phase 9 of `IMPLEMENTATION.md`).

## 12. Host configuration interface

A small SPI-like configuration interface (not a general-purpose CPU — see
`ARCHITECTURE.md` §6 for why a full CPU is explicitly avoided here) used to:

- Halt/resume execution.
- Load program memory.
- Set per-pin modes (push-pull vs. open-drain, direction).
- Read counters and trace data.
- Start a context at a selected timestamp.
- Seed the fault-injection LFSR.
- Read contract violations.

## 13. Proof-carrying microcode (compiler-side static checks)

Before any program is loaded onto the chip, the host compiler must statically
verify:

- No unbounded busy loops.
- Every real-time response has a calculable latency.
- No two contexts own the same output pin simultaneously.
- Open-drain pins never actively drive high.
- Every program-counter target is valid.
- Control flow remains stackless and within the program region.
- FIFO/mailbox use is bounded.
- The program cannot disable the configuration interface.
- Required timing is schedulable at the configured clock.

The compiler emits a small program manifest summarizing the proof result (example
shape — exact fields may evolve, but the concept and intent must not be dropped):

```
Maximum response latency:      3 cycles
Maximum active contexts:       3
Owned pins:                    A0, A1, B0, B1
Open-drain pins:               A0, B0
Worst-case mailbox occupancy:  4 bytes
Program CRC:                   ...
```

A lightweight **on-chip** loader validates only the structural parts and a
checksum against this manifest — the heavy proof work itself stays off-chip
(consistent with §10's host/chip split). This is the project's core verification
narrative: *the compiler doesn't just generate microcode, it proves the generated
program satisfies declared real-time and electrical-safety constraints* — and this
framing should be preserved in the eventual competition write-up.

## 14. What to explicitly avoid (design anti-goals)

These were deliberately rejected during initial design (see `SPEC.md` §4) and
must not be reintroduced without a new, explicitly logged decision in
`decisions.md`:

- A miniature RISC-V or similar general CPU with GPIO instructions.
- Separate fixed UART/SPI/I2C hardware blocks behind a mux.
- A near-direct RP2040 PIO recreation.
- Multiple complete 32-bit processors.
- A large barrel shifter or multiplier.
- Large on-chip packet buffers.
- Autonomous on-chip AI/ML protocol recognition.
- Attempting to support many protocols before the first successful
  place-and-route of the core.
- Claiming complete USB/CAN/Ethernet physical-layer compliance without the
  required external electrical interface.

## 15. Relationship to the other spec documents

- `ARCHITECTURE.md` — how the hardware blocks in this spec are actually built
  (reaction cells, execution engine, memories, synchronizers).
- `PIN_MAP.md` — the literal pin assignment implementing §7 and §12.
- `DSL_SPEC.md` — the full grammar for the protocol descriptions, fault
  definitions, and contracts referenced in §8, §9, §10, §13.
