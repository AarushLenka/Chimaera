# PIN_MAP.md — Tiny Tapeout Pin Assignment

This document must always match the actual RTL top-level port list exactly. If
they ever diverge, that is a bug — fix the divergence in the same work session it's
found, per `AGENTS.md` §8, and log why the divergence happened in `decisions.md`.

## 1. Tiny Tapeout standard wrapper (fixed by the platform, not by us)

Every Tiny Tapeout project gets exactly:

- 8 dedicated inputs (`ui_in[7:0]`)
- 8 dedicated outputs (`uo_out[7:0]`)
- 8 bidirectional pins (`uio_in[7:0]` / `uio_out[7:0]` / `uio_oe[7:0]`)

Confirm the exact current signal names against the Tiny Tapeout template
repository at project start (Phase 0 of `IMPLEMENTATION.md`) — these names are
stable across recent Tiny Tapeout shuttles but should be verified, not assumed,
since this document was drafted before template setup.

## 2. Reference allocation (starting point — confirm/adjust during Phase 2–4 build-out)

| Pin group | Assignment | Notes |
|---|---|---|
| `uio[3:0]` | Port A (Device A side) | 4 bidirectional lines — covers open-drain (I2C-style: data + clock) and push-pull (SPI/UART-style: multiple signal lines) needs for one protocol side. |
| `uio[7:4]` | Port B (Device B side) | Mirror of Port A, other side of the transducer. |
| `ui_in[7:0]` | Reserved for the host configuration interface | Unused by the Phase 2 UART slice; must be assigned before Phase 4 completes. |
| `uo_out[7:0]` | Last successfully received UART byte | Phase 2 observability path; later host readback may replace this direct mapping. |
| `uio[0]` | Port A UART RX | Input only in Phase 2. |
| `uio[1]` | Port A UART TX | Push-pull output, idle high, in Phase 2. |
| `uio[3:2]` | Port A reserved | Released/input in Phase 2. |
| `uio[7:4]` | Port B reserved | Released/input in Phase 2. |

The host-interface assignment remains intentionally reserved during Phase 2. Fill
it in no later than the end of Phase 4 (`IMPLEMENTATION.md`) — by the time
transducer modes and fault injection are being built in Phase 6, this table must
be exact and complete, since later phases depend on a stable pinout.

## 3. Per-protocol pin usage within a port (Port A shown; Port B mirrors)

| Protocol | Pins used within the 4-pin port | Notes |
|---|---|---|
| UART | 1 TX (push-pull out), 1 RX (input) | 2 of 4 pins used; remaining 2 free for a second simultaneous protocol instance or left idle. |
| SPI | SCLK, MOSI, MISO, CS — all 4 pins | Uses the full 4-pin port. |
| I2C | SDA (open-drain, bidirectional), SCL (open-drain, bidirectional/input depending on mode) | 2 of 4 pins used; open-drain configuration is mandatory per `ARCHITECTURE.md` §4 — never push-pull for these two, even in fault-injection scenarios (`ARCHITECTURE.md` §7). |

Exact pin-to-protocol-role mapping (e.g. "which physical `uio` bit is SPI SCLK
specifically") must be fixed in the DSL's pin-declaration syntax (`DSL_SPEC.md`
§"pin declarations") so a DSL program can name a role (`sda`, `sclk`, etc.) rather
than a raw bit number — this indirection is intentional and should not be
collapsed away for convenience.

## 4. Open-drain vs. push-pull — must match `ARCHITECTURE.md` §4

Any pin used for I2C, or for any protocol/mode explicitly configured as open-drain
in a DSL program, must go through the open-drain output control path described in
`ARCHITECTURE.md` §4, which makes driving-high structurally impossible in that
mode. Do not implement open-drain behavior as "push-pull logic that just happens
to not drive high in current test cases" — it must be a structural property of the
pin's output stage configuration, enforced in hardware, because this is also a
compiler-checked static safety property (`SPEC.md` §13) and the two must agree by
construction, not by testing coincidence.

## 5. Status of this document

The wrapper names and widths in §1 have been verified against the checked-out
Tiny Tapeout template. The UART assignments in §2 match the Phase 2 RTL. Port B
and the host configuration pins remain reserved until their Phase 4 functions
exist; those rows are not yet the final v1 allocation.
