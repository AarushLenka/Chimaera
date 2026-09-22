# AGENTS.md — Operating Instructions for the Coding Agent

You are working on **Chimaera**, a Tiny Tapeout ASIC submission for the Jane
Street–sponsored Tiny Tapeout competition (deadline **January 18, 2027**). This file
governs how you work on this repository. Read it in full before doing anything else,
and re-read `SPEC.md` and `ARCHITECTURE.md` before starting each new phase of work.

The human you're working with (Hausen) is technically strong in RTL/DV and embedded
systems but is treating this specific project's early phases as a learning process.
Explain non-obvious design choices in plain language when asked, don't assume the
question is naive, and never let politeness cause you to skip stating a real risk or
a real problem with the design.

---

## 1. Source of truth and document hierarchy

When documents conflict, resolve in this order:

1. **`SPEC.md`** — the functional specification. What the chip must do.
2. **`ARCHITECTURE.md`** — how it does it, at the hardware block level.
3. **`PIN_MAP.md`** — exact pin assignments; must never silently drift from what's
   actually implemented.
4. **`DSL_SPEC.md`** — the protocol description language grammar/semantics.
5. Everything else, including your own prior code, defers to the above.

If you find yourself about to implement something that isn't in `SPEC.md` or
`ARCHITECTURE.md`, stop and do one of:
- Confirm it's a natural, unambiguous consequence of what's already specified
  (e.g. an obvious helper function) — and note the addition in `decisions.md`.
- If it's a real design decision (changes behavior, area, timing, or scope), **ask
  the human before proceeding** rather than deciding unilaterally. Undocumented
  scope changes are the single biggest risk to this project finishing on time.

Never expand scope beyond `SPEC.md`'s "In v1" list without explicit human
confirmation, even if a stretch feature seems easy or fun to add. Re-read
`IMPLEMENTATION.md` §4 ("What v1 actually includes") if you're unsure whether
something is in scope.

---

## 2. Required documentation habit: `decisions.md` and `flow.md`

You must create and continuously maintain two files at the repository root:
**`decisions.md`** and **`flow.md`**. These are not optional or "nice to have" —
they are a required deliverable of every work session, and the human is relying on
them to write the competition submission description later. Create both during your
first working session (Phase 2 of `IMPLEMENTATION.md`) if they don't exist yet.

### `decisions.md` — the *what and why*

A running, dated log of every non-trivial decision made during the project.
Structure each entry like this:

```markdown
## 2026-XX-XX — <short decision title>

**Context:** What problem or choice prompted this.
**Decision:** What was decided.
**Alternatives considered:** What else was on the table, briefly, and why rejected.
**Consequences:** What this affects (area, timing, scope, future flexibility).
**Status:** proposed | confirmed by Hausen | superseded by <link to later entry>
```

Log a decision whenever you:
- Choose a specific encoding, bit width, memory size, or instruction format not
  already pinned down exactly in `ARCHITECTURE.md`.
- Cut, defer, or add a feature relative to `SPEC.md`.
- Hit a synthesis/place-and-route constraint that forces a design change.
- Choose between two roughly-equal implementation approaches for anything
  non-trivial.
- Get an explicit go/no-go answer from Hausen on something you asked about.

Do **not** log trivial code-style choices, variable naming, or anything that has no
real consequence if changed later — keep the signal-to-noise ratio high. This file
is meant to be skimmed by a human once a week, not read line by line every day.

### `flow.md` — the *narrative*

A chronological, human-readable story of how the project actually progressed,
written as if explaining it to someone who wasn't there. Update it at the end of
every work session with a short entry:

```markdown
## 2026-XX-XX — <session summary in a few words>

What was attempted, what happened (including failures and dead ends — these matter
as much as successes for the submission write-up), what changed as a result, and
what the next session should pick up.
```

`flow.md` should read as a continuous story, not a changelog — it's the source
material for the "development journey" section of the eventual public submission
description, and for debugging "what changed since this worked" questions later
(see `IMPLEMENTATION.md` §6). Keep dead ends and failed approaches in it; don't
retroactively clean the story up to look tidier than it was. That honesty is the
whole point of the file.

Both files live at the repository root, are committed to version control like any
other project file, and are never deleted or rewritten from scratch — only appended
to (with occasional light reorganization for readability, never loss of content).

---

## 3. Working process, phase by phase

Follow the phases in `IMPLEMENTATION.md` §3 in order. Do not skip ahead to a later
phase's features while an earlier phase's "done when" criteria is unmet — this is a
hardware project; unverified early work compounds into much more expensive failures
later (a bug found after place-and-route costs far more time than one found in
Phase 2 simulation).

At the start of each phase:
1. Re-read the relevant section(s) of `SPEC.md` and `ARCHITECTURE.md`.
2. State in your response what you're about to build and how you'll verify it,
   before writing code.

At the end of each phase:
1. Update `decisions.md` and `flow.md`.
2. Explicitly state whether the phase's "done when" criteria (from
   `IMPLEMENTATION.md`) is met. If not, say what's missing — don't imply
   completion.
3. Give the human something concrete to review (simulation output, waveform
   description, synthesis report, a small DSL example) — never just "tests pass."

---

## 4. Hardware-track engineering rules

These apply to all RTL work:

- **Simulate before synthesizing, synthesize before place-and-route, every time.**
  Never claim something works based on synthesis alone if it hasn't passed
  simulation first, and never claim "it fits" based on synthesis cell counts alone —
  only full place-and-route confirms real fit and timing (per Jane Street's own
  guidance referenced in `SPEC.md`).
- **Every reaction cell's event-to-output latency must be a fixed, statically
  known number of cycles.** This is the project's core architectural claim (see
  `ARCHITECTURE.md` §2). If you write logic where this isn't true, that's a
  correctness bug against the spec, not a style issue — flag it immediately rather
  than shipping it.
- **Open-drain pins must never be actively driven high.** This is a real hardware
  safety property (matches actual I2C electrical behavior), and the static
  compiler checks in `SPEC.md` exist specifically to catch violations of it before
  a program is ever loaded. Don't bypass or weaken these checks to make a demo
  program compile.
- **No two logical contexts may claim ownership of the same output pin
  simultaneously.** Same reasoning as above — this is a static, provable property,
  not a runtime hope.
- Prefer the smallest correct implementation over a more "clever" one. Area is a
  hard, fixed budget (24 tiles / ~24K cells before overhead) — there is no
  "optimize later," because overshooting the budget is a hard failure, not a
  performance regression.
- Log every synthesis and place-and-route run's area/timing numbers into
  `decisions.md`, even (especially) failing ones. A failed P&R run with numbers
  attached is much more useful later than an unlogged one.

---

## 5. Software-track rules (DSL, compiler, reference model)

- The DSL parser, compiler, and static checkers are host-side tools (run on a
  normal computer, not on the chip). Keep it that way — do not move any inference,
  compilation, or proof logic onto the chip itself. The chip is a small deterministic
  execution engine; all the "smart" work happens on the host, by design (see
  `SPEC.md` §"Proof-carrying microcode").
- If an LLM-assisted step is ever used (e.g. drafting a DSL program from a written
  protocol datasheet), its output must always be independently checked by the
  interpreter, static checker, and RTL simulator before being trusted. Never treat
  LLM output as ground truth for correctness — this rule applies to you too, in the
  sense that your own generated DSL programs still go through the full check
  pipeline, no exceptions for code you wrote yourself.
- The reference software model of the chip (used for fast compiler-output checking
  without a full RTL simulation) must be kept behaviorally in sync with the RTL. If
  you change RTL behavior, update the reference model in the same work session and
  say so in `decisions.md` — a silently drifting reference model is worse than not
  having one.

---

## 6. Testing expectations

- Every protocol (UART, I2C, SPI) needs cocotb tests covering: normal operation,
  at least one edge case (e.g. malformed input, boundary timing), and — once fault
  injection exists — a reproducible fault scenario.
- Every demo in `SPEC.md` §"Demo script" needs a corresponding simulation test that
  can be pointed to as evidence it works, not just described as working.
- When you report a test result to the human, include enough concrete detail
  (values, timing, a described or rendered waveform) that they could sanity-check
  it themselves without re-running anything — assume they will ask "how do I know
  this actually worked," because per `IMPLEMENTATION.md` they've been told to ask
  exactly that.

---

## 7. When to stop and ask instead of proceeding

Ask Hausen before proceeding, rather than making the call yourself, when:

- A synthesis or place-and-route result forces cutting or descoping a v1 feature.
- You're unsure whether something counts as in-scope per `SPEC.md`.
- Two implementation approaches trade off area vs. timing vs. flexibility in a way
  that isn't obviously "better" — this is a judgment call the human should own.
- You've hit something that would take a written decision in `decisions.md` with
  `Status: proposed` — get it to `confirmed by Hausen` before building heavily on
  top of it.

Don't ask about things that are unambiguous consequences of already-approved specs —
that's the kind of low-value interruption that erodes trust in when you *do* need an
answer. Use judgment, and when genuinely unsure which category something falls in,
err toward asking.

---

## 8. Repository hygiene

- Keep `SPEC.md`, `ARCHITECTURE.md`, `PIN_MAP.md`, and `DSL_SPEC.md` accurate to
  the actual implementation at all times. If implementation reality diverges from
  what a spec doc says, update the spec doc in the same session (and log why in
  `decisions.md`) — these documents must never become stale fiction that no longer
  describes the real project.
- Commit messages should be specific enough that `flow.md` could mostly be
  reconstructed from `git log` alone, though `flow.md` itself remains the primary
  narrative record.

---

## 9. Commit and push policy

- Make small, logically complete commits at verified checkpoints. Keep unrelated
  changes in separate commits, review the staged diff before committing, and do
  not hide unfinished or failing work inside a broad catch-all commit.
- Use concise Conventional Commit messages (`feat:`, `fix:`, `docs:`, `test:`,
  etc.) that state the specific outcome. Add a body only when the reason is not
  obvious from the subject and diff.
- Never add Codex, another AI agent, or an AI vendor as a collaborator,
  contributor, co-author, or attribution. Do not add `Co-authored-by`,
  `Assisted-by`, `Generated-by`, or similar AI-related commit trailers or prose.
- Local commits are allowed when Hausen requests project work or commits, but do
  not push automatically. After the relevant commits and verification are ready,
  tell Hausen exactly what is committed and that it is ready to push. Push only
  after Hausen explicitly instructs you to do so.
