# DSL_SPEC.md — Chimaera Protocol Description Language

This document defines the grammar and semantics of the small domain-specific
language (DSL) used to describe protocols, fault injections, and timing contracts,
which the host-side compiler (`SPEC.md` §13) turns into microcode for the chip's
reaction cells (`ARCHITECTURE.md` §2).

**Status of this document:** the syntax below is a working starting design
(adapted from initial project research), not a finalized grammar. The agent should
implement a parser against this grammar, but is expected to refine exact syntax
details during implementation where the language is ambiguous or awkward in
practice — any such refinement must be reflected back into this document and
logged in `decisions.md`, per `AGENTS.md` §1 and §8. What must **not** change
without an explicit logged decision is the *shape* of what the language expresses
(pin declarations, states with event/timeout transitions, separate mutation and
contract blocks) — that shape is load-bearing for the architecture in
`ARCHITECTURE.md`.

## 1. Design goals for the language itself

- Human-readable enough that Hausen (a competent engineer, new to this specific
  project) can write a small protocol description by hand using this document as
  reference — this is explicitly checked in `IMPLEMENTATION.md` Phase 5.
  If a construct requires deep familiarity with the compiler internals to use
  correctly, that's a language design problem, not a documentation problem.
- Everything expressible in the language must be **staticaly checkable** per the
  proof obligations in `SPEC.md` §13. Do not add a language feature (e.g. unbounded
  loops, dynamic pin ownership) that would make one of those checks impossible.
- Protocol definitions, fault/mutation definitions, and contract/assertion
  definitions are **separate, composable blocks** — a fault or contract attaches
  to a protocol by name, rather than being tangled into the protocol's own state
  definitions. This keeps each concern independently readable and testable.

## 2. Top-level structure

A DSL source file contains one or more of:

```
protocol <name> { ... }      // required: at least one per file
mutation <name> { ... }      // optional: zero or more, each references a protocol
contract <name> { ... }      // optional: zero or more, each references a protocol
```

## 3. `protocol` blocks

### 3.1 Pin declarations

```
protocol i2c_sensor {
    pin sda open_drain
    pin scl input
```

- `pin <role_name> <mode>` declares a named role, not a raw bit number — actual
  physical pin binding happens at load time via the host configuration interface
  (`SPEC.md` §12), per `PIN_MAP.md` §3's indirection requirement.
- Valid modes: `open_drain`, `input`, `output` (push-pull output),
  `bidirectional` (direction switches per-state; each state using it must specify
  direction explicitly in its body).
- The compiler must statically verify, per `SPEC.md` §13, that no two
  simultaneously-active contexts declare conflicting ownership of the same
  physical pin, and that no pin declared `open_drain` is ever driven high by any
  state or mutation.

### 3.2 States

```
    state address {
        on rise(scl) {
            sample sda into address_shift
            count bits
        }

        when bits == 8 && address_shift == 0x48 -> ack
        when bits == 8                            -> ignore
        within 100us else                         -> idle
    }
```

- `state <name> { ... }` defines one reaction-cell state.
- Inside a state body:
  - `on <event> { <actions> }` — actions to take when the named event condition
    fires. Valid event forms: `rise(<pin>)`, `fall(<pin>)`, `level(<pin>, <0|1>)`,
    `pattern(<mask_expr>)`.
  - `sample <pin> into <variable>` — latch a pin's current value into a named
    working variable (backed by reaction-cell sample-mask hardware,
    `ARCHITECTURE.md` §2).
  - `count <counter_name>` — increment a small counter (backed by shared execution
    engine counter/comparator, `ARCHITECTURE.md` §3).
  - `drive <pin> <low|high|release>` — commit a predecoded pin action. `high` is a
    compile-time error if `<pin>` is declared `open_drain` (this must be enforced
    by the parser/checker, not left to a later stage).
  - `when <condition> -> <next_state>` — event-based transition, evaluated after
    the state's `on` actions run.
  - `within <duration> else -> <next_state>` — timeout-based transition (backed by
    the reaction cell's deadline/timeout-successor field, `ARCHITECTURE.md` §2).
    `<duration>` may be expressed in cycles (`N cycles`) or physical time
    (`N us`/`N ns`) — the compiler resolves physical-time durations to a cycle
    count using the configured clock frequency at compile time, and must reject
    any duration it cannot resolve to a bounded cycle count.
- Every state must have **at least one** `within ... else -> ...` timeout
  transition, or must be provably reachable only from a state that already
  guarantees bounded time in this state via some other means — this is the
  language-level mechanism enforcing `SPEC.md` §13's "no unbounded busy loops"
  and "every real-time response has a calculable latency" proof obligations. The
  compiler must reject any state missing this unless it can prove boundedness
  another way; when in doubt, require the explicit `within` clause.

### 3.3 Example: full small protocol (I2C ACK send, from initial design notes)

```
protocol i2c_sensor {
    pin sda open_drain
    pin scl input

    state idle {
        on fall(sda) when scl == 1 -> address
    }

    state address {
        on rise(scl) {
            sample sda into address_shift
            count bits
        }
        when bits == 8 && address_shift == 0x48 -> ack
        when bits == 8                            -> ignore
        within 100us else                         -> idle
    }

    state ack {
        drive sda low
        on fall(scl) {
            release sda
            goto command
        }
    }
}
```

## 4. `mutation` blocks (fault injection, per `SPEC.md` §8)

```
mutation delayed_ack {
    when address == 0x48 && transaction_count % 17 == 0
    delay next action by 3 cycles
}
```

- `mutation <name> { when <condition> <effect> }` attaches a conditional
  modification to a named protocol's normal behavior.
- `<condition>` may reference any protocol variable/counter in scope (address,
  bit counts, a `transaction_count` implicitly maintained per protocol instance)
  and the shared LFSR's current value (via a reserved variable, e.g.
  `random_bits(N)`) for seeded pseudo-random conditions.
- Valid `<effect>` forms (non-exhaustive — extend as needed, but keep each new
  effect form traceable to a real hardware mechanism in `ARCHITECTURE.md` §7,
  never something the hardware can't actually do):
  - `delay next action by <N> cycles`
  - `nack` / `drop byte` (protocol-appropriate refusal/drop)
  - `flip bits <mask> in <variable>`
  - `hold <pin> low for <N> cycles` (clock stretching, per `SPEC.md` §8 examples)
  - `duplicate edge on <pin>`
  - `release <pin> after <N> extra cycles`
- **Reproducibility requirement (hard, from `SPEC.md` §8):** the compiler must be
  able to state, for any compiled program including mutations, that behavior is
  fully determined by `(program hash, random seed, trigger count)`. Any mutation
  effect that can't satisfy this (e.g. depends on real-world timing jitter not
  derived from the LFSR) is invalid and must be rejected at compile time, not
  merely discouraged in documentation.

## 5. `contract` blocks (runtime timing assertions, per `SPEC.md` §9)

```
contract valid_i2c {
    assert stable(sda) while scl == 1
        except start_condition
        except stop_condition

    assert high_width(scl) >= 4 cycles
}
```

- `contract <name> { assert ... }` attaches one or more temporal assertions to a
  named protocol.
- Valid assertion forms (non-exhaustive, extend carefully — same rule as §4:
  every form must map to something the contract-checker hardware in
  `ARCHITECTURE.md` §8 can actually evaluate):
  - `assert stable(<pin>) while <condition> [except <named_exception>...]`
  - `assert high_width(<pin>) >= <duration>` / `<= <duration>`
  - `assert <event_a> within <duration> after <event_b>`
  - `assert not (<condition>)` (general negative assertion, for cases like "no
    push-pull contention")
- On violation, behavior is fixed by `SPEC.md` §9 (trigger output, freeze trace,
  record violation + timestamp, release driven pins, continue operating with an
  incremented violation counter) — this is not configurable per-contract; don't
  add syntax implying otherwise.

## 6. Compiler output

For every compiled `protocol` (plus any attached `mutation`/`contract` blocks),
the compiler must emit, per `SPEC.md` §13:

- The chip-loadable microcode binary.
- A cycle-accurate reference software model instance (for fast host-side testing
  without full RTL simulation, per `AGENTS.md` §5).
- Generated cocotb (or equivalent) randomized tests.
- The formal proof-obligation results as a program manifest (exact fields per
  `SPEC.md` §13's example).
- A human-readable state diagram.
- A textual waveform expectation ("ASCII waveform expect test," per the project's
  Jane Street–aligned testing philosophy referenced in `SPEC.md` §13 — this format
  should make timing behavior reviewable as a plain-text source-control diff).

## 7. Explicitly out of scope for the DSL (v1)

- No general-purpose arithmetic beyond what's needed for counters/comparisons
  (no loops-within-loops, no function calls, no recursion) — this is intentional,
  not a missing feature; it's what makes the static proof obligations in §3.2 and
  `SPEC.md` §13 tractable.
- No SMT-based synthesis of programs from waveform contracts (`SPEC.md` §6 stretch
  list) — the DSL in v1 is written, not automatically generated from a
  specification, except via the host-side capture/replay tooling in `SPEC.md` §10,
  which is a distinct code path from this grammar's compiler.
- No on-chip evaluation of anything in this document — all parsing, compiling,
  and static checking happens on the host, per `SPEC.md` §10 and §13 and
  `AGENTS.md` §5.
