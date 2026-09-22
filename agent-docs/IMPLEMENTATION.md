# Chimaera — Implementation Guide (Start Here)

**Who this is for:** you, assuming you know close to nothing about how this project
actually comes together yet. This document explains *what you're building, why each
step exists, and what to actually type/click*, in order. It does not assume you know
what Tiny Tapeout is, what an ASIC flow looks like, or what any of the acronyms mean —
they're all explained the first time they show up.

**What the other documents are for:** this file is for *you* to read and follow.
`AGENTS.md`, `SPEC.md`, `ARCHITECTURE.md`, etc. are written for an AI coding agent
(Codex) to follow while it does the actual RTL/toolchain work. You won't need to read
those closely — skim them once so you know they exist, then let the agent use them.
This file tells you when to hand the agent a task and what to check when it's done.

---

## 0. The 60-second version

You're entering a silicon design competition (Tiny Tapeout x Jane Street). You submit
a small digital circuit design (RTL — the "source code" for a chip), it gets combined
with other people's circuits onto one real silicon chip, and that chip gets
manufactured and mailed back to you months later, actually working.

Your design idea (**Chimaera**) is a programmable circuit that can watch and talk
on common hardware communication protocols (I2C, SPI, UART — the ways chips talk to
each other) — and can act as any of them, translate between them, inject controlled
faults, and check timing rules, all without rebuilding the chip. You load a small
"program" into it after manufacturing to tell it what to do.

You will not hand-write all the circuit code yourself. An AI coding agent (Codex) will
write and test the RTL, following the spec documents in this folder. Your job is to:
run the agent, review what it produces at checkpoints, make decisions when the agent
asks, and push the design through the official submission steps near the deadline.

**Deadline: January 18, 2027.**

---

## 1. Words you'll see constantly (read this once)

| Term | What it means here |
|---|---|
| **RTL** | "Register Transfer Level" — code (in a language called Verilog) that describes digital circuit behavior. This is the actual design. |
| **Verilog** | The programming language used to write RTL. Looks like C but describes hardware, not software steps. |
| **Tiny Tapeout** | The program that lets individual people/teams submit a small design to be fabricated on a real chip, cheaply, by sharing chip area with many other teams. |
| **Tile** | A unit of chip area Tiny Tapeout gives you. You have **24 tiles** (~0.7 mm², roughly 24,000 logic cells before overhead) — a hard space budget. |
| **Fabrication ("tapeout")** | The actual manufacturing of the chip in a real semiconductor factory. Happens after your design is finalized and submitted — you don't control this part, you just submit correctly. |
| **Synthesis** | Converting your Verilog into a netlist of actual logic gates. The first "does this even fit and work" checkpoint. |
| **Place and route (P&R)** | Deciding where each gate physically sits on the chip and how wires connect them. This is where designs often fail even if synthesis succeeded — timing or space problems show up here. |
| **Simulation** | Running your Verilog on your computer (not real hardware) to check it behaves correctly, before ever going near real silicon. |
| **Testbench** | Code that drives inputs into your simulated design and checks the outputs are correct. |
| **cocotb** | A Python-based testing framework used to write testbenches for Tiny Tapeout projects. You'll mostly let the agent write these. |
| **GDS / GDSII** | The final geometric file format describing exactly what to etch on the chip. This is what actually gets submitted for fabrication. |
| **Reaction cell** | Chimaera's core building block — a small hardware unit that "sleeps" until a specific pin event or timeout happens, then reacts instantly. Explained fully in `ARCHITECTURE.md`. |
| **Protocol** | A set of rules two chips use to talk over wires — e.g. I2C, SPI, UART. Chimaera's whole point is handling these generically. |
| **DSL** | "Domain-Specific Language" — a small custom language (not Verilog) you'll design so protocols can be described in a readable text format and compiled into Chimaera's internal program format. |
| **Codex** | The AI coding agent that will do the RTL/tooling work, following `AGENTS.md`. |

---

## 2. What you're actually building (in plain English)

Skip the fancy words for a second. Here's the idea:

- Most communication protocols between chips (I2C, SPI, UART, etc.) are just:
  "wait for a pin to change, then do something, on a timer."
- Instead of building one fixed circuit per protocol (which is what most people do,
  and what would just copy an existing design), Chimaera builds **one generic
  engine** that can be *programmed*, after the chip is manufactured, to become any of
  these protocols — or several at once, or something in between (translate one
  protocol into another, corrupt it on purpose for testing, check its timing rules
  live, etc).
- You write the "program" for a protocol in a **text file** (in a custom language
  you'll design, described in `DSL_SPEC.md`), and a **compiler tool** turns that text
  file into a tiny binary program the chip loads and runs.
- The demo, at the end, is: the *same* manufactured chip acts like an I2C sensor,
  then an SPI flash chip impersonator, then injects a reproducible timing fault, then
  gets reprogrammed on the spot to speak a brand-new protocol you never planned for
  when the chip was designed — proving it's genuinely reprogrammable, not just a
  bundle of fixed protocol blocks.

That's it. Everything else in the spec documents is detail in service of that.

---

## 3. The order you'll actually do things in

This project has two tracks that run somewhat in parallel: **hardware** (the chip
itself) and **software** (the compiler/DSL/simulator tooling). The hardware track is
the one with hard risk (it either fits on real silicon or it doesn't), so it goes
first and gets prioritized whenever the two compete for time.

Below is the full path from zero to submission. Each phase says **what happens**,
**what you personally need to do**, and **what "done" looks like**.

### Phase 0 — Environment setup (you, ~1 day)

**What happens:** You get your computer (or a cloud dev environment) able to run
Verilog simulators and the Tiny Tapeout toolchain.

**What you do:**
1. Create a GitHub account if you don't have one.
2. Go to the Tiny Tapeout template repository (the agent will find and tell you the
   exact current URL — link it yourself if this doc is out of date) and click
   "Use this template" to make your own copy under your GitHub account.
3. Tell the agent to set up the local dev environment per that template's
   instructions (it typically uses a tool called `uv` or `pip` plus open-source
   simulators like `iverilog` or `verilator`).
4. Confirm you can run the template's example test (`make` or similar) and see it
   pass, *before* any of your own code exists. This proves your environment works.

**Done when:** the unmodified template's own example simulation passes on your
machine.

### Phase 1 — Lock the spec (you + agent, collaborative)

**What happens:** `SPEC.md`, `ARCHITECTURE.md`, `PIN_MAP.md`, and `DSL_SPEC.md` in
this folder define *exactly* what you're building, at a level detailed enough that
the agent doesn't have to guess. These are already drafted for you (see the rest of
this folder) based on the strongest design direction from your research. Read
`SPEC.md` end to end once — you don't need to understand every electrical detail,
but you should be able to say the one-sentence description of the project back in
your own words. If something in there doesn't match what you actually want to build,
edit it now, before the agent starts — changing the spec after the agent has built
against it is expensive.

**What you do:** Read `SPEC.md`. Sanity check the scope (Section "What's in v1"
below tells you exactly what's being built first). Approve it or edit it.

**Done when:** you've read `SPEC.md` and either accepted it as-is or edited it to
match what you actually want.

### Phase 2 — First reaction cell + UART, in simulation only (agent-led)

This is the *only* protocol you build first. Not I2C, not SPI — UART, because it's
the simplest (no clock line, just timed bits), and it proves the whole architecture
end to end before you invest in anything else.

**What happens:** The agent, following `AGENTS.md`, will:
1. Write the RTL for exactly **one** reaction cell (the core hardware building
   block — see `ARCHITECTURE.md` §2) and the shared execution engine it needs.
2. Write a UART transmit and receive microprogram loaded into that one cell.
3. Write a cocotb testbench that drives a simulated UART signal in and checks the
   chip receives it correctly, and drives a byte out and checks it's a valid UART
   waveform.
4. Run the simulation and iterate until it passes.

**What you do:** Nothing technical required, but **you must actually look at the
result**. Ask the agent to show you:
- A waveform screenshot or description of a successful UART receive.
- The test pass/fail output.

You're checking: does this look like it's actually doing the thing (receiving a byte
correctly), not just "tests say PASS" with no evidence. If you don't understand the
waveform, ask the agent to explain what you're looking at in plain English — that's
a legitimate and expected question to ask it.

**Done when:** cocotb tests for UART TX and RX both pass in simulation, and you've
personally seen evidence (not just been told) that it works.

### Phase 3 — First synthesis + area/timing check (agent-led, high-stakes checkpoint)

**Why this matters more than it sounds:** a design can simulate perfectly and still
fail to fit in your 24 tiles, or fail timing, once run through real synthesis tools.
This is the earliest point you find that out, and Jane Street's own advice (per your
research notes) is to do this *early*, not after the design feels "finished."

**What happens:** The agent runs the Tiny Tapeout template's synthesis flow (uses
open-source tools — likely Yosys) on the Phase 2 design and reports:
- Cell/area usage vs. your 24-tile budget.
- Whether timing closes at the target clock speed.

**What you do:** Look at the area number. If one reaction cell + UART already eats a
large fraction of the 24-tile budget, that's critical information — it changes how
many reaction cells and how much DSL/fault-injection logic you can afford later. Ask
the agent to log this number in `decisions.md` (see §6 below) regardless of the
outcome, so you have a paper trail of area growth over time.

**Done when:** you have a real synthesis area number for one reaction cell + shared
engine, and it's recorded.

### Phase 4 — Add I2C and SPI, second reaction cell (agent-led)

**What happens:** Only after Phase 3 gives you real numbers, the agent adds:
- A second reaction cell (to prove the "shared execution engine, multiple contexts"
  architecture actually works, not just theoretically).
- I2C and SPI microprograms.
- Extends the testbench to cover both.

**What you do:** Same review pattern as Phase 2 — ask for evidence, not just a
"tests pass" message. Re-run the Phase 3 synthesis check and compare the new area
number to the old one — is growth roughly linear per protocol, or is something
scaling badly? Flag anything surprising.

**Done when:** I2C and SPI both pass simulation tests using two reaction cells
sharing one execution engine, and you have an updated area number.

### Phase 5 — The DSL and compiler toolchain (agent-led, software track)

**What happens:** This is the part that turns your protocol descriptions (written in
the small custom language defined in `DSL_SPEC.md`) into the binary microprograms the
chip loads. The agent builds:
1. A parser for the DSL.
2. A compiler that emits the chip's binary program format.
3. Static checks (per `SPEC.md` §"Proof-carrying microcode") that catch broken
   programs *before* they're loaded onto the chip — e.g. two protocols trying to
   drive the same pin at once.
4. A reference software model of the chip so the compiler's output can be checked
   against expected behavior *without* running the RTL simulator every time
   (much faster iteration).

**What you do:** This is the most "trust the agent" phase, since it's pure software
and lower-stakes than the hardware track — nothing here risks the chip not fitting.
Try writing one tiny protocol description yourself in the DSL, using `DSL_SPEC.md` as
a reference, and ask the agent to compile it. This is a good gut-check for whether
the DSL is actually usable by a human (you) or only by the agent.

**Done when:** you've personally written and compiled at least one small DSL program
successfully.

### Phase 6 — Live demo features: transducer modes, fault injection, contracts (agent-led)

**What happens:** With the core proven, the agent builds the higher-level features
from `SPEC.md` §"Demo features": proxy/translate/rewrite modes between two ports,
the deterministic fault injection system (reproducible from a seed), and the runtime
timing-contract assertion checker.

**What you do:** Review demo-by-demo, matching the five demos described in
`SPEC.md` §"Demo script". For each one, actually watch/read the evidence the agent
produces (waveform, log, or short recording) and confirm it matches what the demo is
supposed to show.

**Done when:** all five demos from `SPEC.md` work in simulation.

### Phase 7 — Full place-and-route, real hard numbers (agent-led, critical checkpoint)

**What happens:** The complete design (all reaction cells, protocols, DSL-generated
programs, fault injection, contracts) goes through full synthesis *and*
place-and-route — the step that tells you, for real, whether this fits and meets
timing on actual silicon layout, not just gate count.

**What you do:** This is the point where you may need to make cuts. If it doesn't
fit or doesn't meet timing, you and the agent look at `SPEC.md`'s "What's in v1" vs.
"Stretch goals" split and cut stretch features first. Record every cut and why in
`decisions.md`.

**Done when:** the full design passes place-and-route within the 24-tile budget and
meets timing at the target clock.

### Phase 8 — Physical testing prep + final submission (you + agent)

**What happens:** Tiny Tapeout requires a specific submission format (project info
YAML, pinout documentation, a written project description, and passing their CI
checks). The agent prepares all of this per `AGENTS.md`.

**What you do:**
1. Review the written project description for accuracy before it's public — this is
   what judges and the community will read.
2. Follow Tiny Tapeout's own submission instructions (check their site close to the
   deadline for the exact current process, since it can change between shuttle
   runs) to actually submit the repository.
3. Confirm you receive submission confirmation before the January 18, 2027 deadline.
   **Do not wait until the deadline day.** Aim to have a submittable design at least
   one to two weeks early, so you have buffer if CI checks reveal a last-minute
   problem.

**Done when:** you've received confirmation your design was accepted into the
shuttle run.

### Phase 9 — After submission (waiting + prep)

**What happens:** Nothing you can change — the chip is manufactured and mailed back
over the following months (this is normal for Tiny Tapeout and outside your
control).

**What you do:** Prepare your demo materials (write-up, video script, any
host-side companion tooling) so you're ready the moment physical chips arrive,
rather than starting that work cold. This can happen anytime after Phase 6.

---

## 4. What "v1" actually includes (don't let scope grow silently)

To keep this achievable by the deadline, here's the line between what's actually
being built and what's a "nice to have later." This matches `SPEC.md`, repeated here
because it's the single most important thing to hold the line on.

**In v1 (must work for submission):**
- Two reaction cells, one shared execution engine
- UART, I2C, SPI protocol support
- Bidirectional transducer: endpoint, transparent proxy, translation, rewrite, and
  firewall modes
- Deterministic, seeded fault injection
- Runtime timing-contract assertions
- The DSL + compiler + static safety checks
- Capture-to-microcode replay tooling, **host-side only** (not on-chip inference)

**Explicitly NOT in v1 (stretch, only if time remains after Phase 7 passes):**
- USB, CAN, Ethernet (digital framing only if attempted at all — never claim full
  electrical-layer compliance)
- SMT-based program synthesis ("supercompilation")
- More than two reaction cells
- Any on-chip machine learning or autonomous protocol inference

If the agent (or you) starts building something from the second list before
everything in the first list is done and passing place-and-route, that's scope
creep — stop and redirect to the first list.

---

## 5. How to actually work with the agent day to day

- Give the agent one phase (from §3 above) at a time, not "build the whole thing."
- At the end of every session, ask it to update `decisions.md` and `flow.md` (see
  §6) — don't let this slip, since it's your record of *why* things are the way they
  are, which you will need later when writing the submission description and demo
  script.
- When the agent proposes a design choice you don't understand, ask it to explain
  in plain English before approving — you are the one who has to defend this design
  if anyone asks about it, so understanding *why* matters more than moving fast.
- If a phase's "done when" criteria isn't met, don't move to the next phase. The
  hardware track especially punishes skipped verification — a bug that looks small
  in simulation can mean a completely non-functional chip once it's real silicon you
  can't change.

---

## 6. `decisions.md` and `flow.md` — what these are and why you'll want them

You didn't ask the agent to write these for your own sake mid-project — you'll want
them for two very concrete reasons later:

1. **Writing the competition submission description.** Judges want to know what you
   tried, what you rejected, and why. `decisions.md` is that record, already written
   as you go instead of reconstructed from memory afterward.
2. **If something breaks late.** If Phase 7's place-and-route suddenly fails after
   working fine in Phase 4, `flow.md`'s change history helps you and the agent find
   what changed, instead of guessing.

You don't need to maintain these yourself — `AGENTS.md` instructs the agent to keep
them updated. Your job is just to periodically skim them (e.g. once a week) to make
sure they're actually being kept current, and to read them before Phase 8 when
writing your public project description.

---

## 7. If you get stuck

- **"The agent did something and I don't understand why."** Ask it to explain in
  plain English and to point you to the relevant section of `SPEC.md` or
  `ARCHITECTURE.md`. If it can't justify it against the spec, that's a sign to push
  back.
- **"Synthesis/place-and-route failed and I don't know what that means."** Ask the
  agent to summarize the failure in plain English (what resource ran out, or what
  timing path failed) before diving into fixes. Don't let it just start changing
  code without you understanding what broke first.
- **"I think the spec itself is wrong."** Stop, edit `SPEC.md` directly, and tell the
  agent the spec changed and it should re-read it before continuing. Don't ask it to
  "just also do X" verbally without updating the spec doc — that's how the spec and
  the code drift apart.

---

## 8. Quick reference — the files in this folder

| File | Audience | Purpose |
|---|---|---|
| `IMPLEMENTATION.md` | You | This file. Step-by-step plan in plain English. |
| `AGENTS.md` | Codex (agent) | Operating instructions, workflow rules, and required documentation habits for the agent. |
| `SPEC.md` | Agent (+ you, once) | The full functional specification — what the chip does. |
| `ARCHITECTURE.md` | Agent | Hardware architecture detail — reaction cells, execution engine, memories. |
| `PIN_MAP.md` | Agent | Exact Tiny Tapeout pin assignments. |
| `DSL_SPEC.md` | Agent (+ you, if curious) | The protocol description language grammar and semantics. |
| `decisions.md` | Agent writes, you read | Running log of design decisions and rationale. Created by the agent during Phase 2. |
| `flow.md` | Agent writes, you read | Running narrative of how the project actually progressed over time. Created by the agent during Phase 2. |
