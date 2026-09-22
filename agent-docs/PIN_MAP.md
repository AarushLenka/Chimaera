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

## 2. Phase 4 allocation

| Pin group | Assignment | Notes |
|---|---|---|
| `uio[3:0]` | Port A (Device A side) | UART baseline: `uio[0]` RX and `uio[1]` TX; `uio[3:2]` released/input. |
| `uio[7:4]` | Port B (Device B side) | I2C and SPI Phase 4 endpoint pins. |
| `ui_in[1:0]` | Port B protocol selector | `00` selects I2C, `01` selects SPI, and `10`/`11` disable cell 1. Temporary until Phase 5 loader. |
| `ui_in[7:2]` | Reserved host configuration inputs | Reserved pin names; final SPI-like loader behavior is Phase 5 scope. |
| `uo_out[7:0]` | Last received protocol byte | Updated by UART RX, I2C data capture, or SPI command capture. |
| `uio[0]` | Port A UART RX | Input only. |
| `uio[1]` | Port A UART TX | Push-pull output, idle high. |
| `uio[3:2]` | Port A reserved | Released/input. |
| `uio[4]` | Port B I2C SDA / SPI SCLK | I2C input/open-drain; SPI input. |
| `uio[5]` | Port B I2C SCL / SPI MOSI | I2C input/open-drain; SPI input. |
| `uio[6]` | Port B reserved in I2C / SPI MISO | Push-pull output only in SPI while CS is low. |
| `uio[7]` | Port B reserved in I2C / SPI CS | SPI input, active low. |

The Phase 4 selector is a temporary bootstrap interface, not the final host
configuration protocol. The exact SPI-like loader assignment and behavior must be
implemented in Phase 5 before transducer modes and fault injection depend on it.

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
Tiny Tapeout template. The UART and Port B assignments in §2 match the Phase 4
RTL. The host loader remains a documented Phase 5 item; no final v1 loader
behavior is claimed by this checkpoint.
