# Phase 5 descriptor ABI proposal

**Status:** accepted for the first production checkpoint. Hausen delegated the
implementation choice for the 24-tile budget on 2026-09-23.

## Goal

Choose a runtime-loaded descriptor memory that preserves fixed reaction timing
without consuming most of the 24-tile budget. `ARCHITECTURE.md` originally used
128 descriptors as a synthesis starting point, not a fixed requirement. Phase 5
now has enough concrete IR to measure that starting point.

## Accepted fixed descriptor

Use **32 entries × 128 bits** for the first production loader checkpoint. The
compiler assigns five-bit state IDs and lowers complex conditions into additional
states when one record cannot express them directly. The compiler and RTL now use
this exact layout:

| Bits | Field |
|---:|---|
| `2:0` | event kind |
| `10:3`, `18:11` | event mask and value |
| `26:19`, `34:27` | guarded-level mask and value |
| `50:35` | timeout cycles |
| `58:51` | sample mask |
| `66:59`, `74:67` | action mask and value |
| `82:75`, `90:83` | output-enable mask and value |
| `95:91`, `100:96`, `105:101` | true, false/default, and timeout targets |
| `106`, `110:107` | counter condition enable and four-bit value |
| `111`, `119:112` | shift condition enable and eight-bit literal |
| `120`, `121` | counter increment and reset |
| `122`, `123` | shift reset and literal load |
| `125:124` | serial mode |
| `127:126` | reserved, zero |

Each descriptor is transmitted as words 0 through 7, where word 0 is bits
`15:0`; each 16-bit payload itself is serialized most-significant byte first.
The loader computes CRC-16-CCITT over those payload bytes from initial value
`0xffff`.

The 32-bit command frame uses opcode `31:28`, context `27`, descriptor address
`26:22`, word index `21:19`, reserved-zero bits `18:16`, and payload `15:0`.
`BEGIN`, `WRITE_DESCRIPTOR`, `SET_CONTEXT`, `SET_PIN_MODES`, `COMMIT`, and
`CONTROL` form the accepted initial command set.

## Measured generic synthesis cost

`experiments/phase5_abi/fixed_descriptor_memory.v` models a runtime-writable
128-bit descriptor array written in 16-bit chunks and read in one cycle. Its
testbench passed full eight-word write/read. Local Yosys 0.63 synthesis produced:

| Entries | Storage bits | Generic cells | Storage flip-flops | Read/write muxes |
|---:|---:|---:|---:|---:|
| 32 | 4,096 | 8,743 | 4,224 | 3,968 |
| 64 | 8,192 | 17,232 | 8,320 | 8,064 |
| 128 | 16,384 | 34,203 | 16,512 | 16,256 |

These are directional generic counts, not IHP physical area or timing numbers.
The experiment excludes the SPI-like command decoder, CRC check, active-descriptor
registers, and all Phase 6 logic. The Phase 4 design itself was 1,747 generic
cells, so the rough combined directional totals would be 10,490, 18,979, and
35,950 cells respectively before those missing blocks.

The integrated design was then simulated and synthesized with the accepted
loader, synchronized serial interface, two loaded reaction contexts, legacy
Phase 4 fallback, target/CRC/order checks, and pending-first rearm arbitration.
Local Yosys 0.63 reports **12,344 generic cells**, including 9,214 in the loader
and its 4,096 descriptor flip-flops. This remains directional: only IHP
place-and-route can establish physical fit and 50 MHz timing.

## Why fixed 32 is recommended

- One indexed read arms the next descriptor without a variable-length decode,
  keeping inter-event schedulability tractable and the armed event-to-output path
  unchanged.
- Thirty-two states match the current five-bit RTL state IDs. The simultaneously
  active Phase 4 programs need at most 19 states (UART plus I2C), leaving 13 for
  lowering helpers before compiler rejection.
- The 64-entry candidate leaves little directional margin for the loader, trace,
  mutation, and contract hardware. The 128-entry starting point exceeds the rough
  raw competition-cell budget by itself when implemented from standard cells.
- A compact 16-bit word stream can store more simple states per bit, but it needs
  a pointer table and multi-cycle decode before a cell can re-arm. That trades area
  for maximum protocol edge rate and scheduler complexity at the exact point where
  fixed timing is Chimaera's main claim.

## Implementation consequences

1. The compiler rejects programs above 32 descriptors after helper-state lowering.
2. Protocol-only programs emit a `.loader.bin` stream and are marked
   `chip_loadable: true`; mutation/contract programs remain host-only until Phase 6.
3. The loader and runtime reject ordering, CRC, partial-record, entry-point, and
   successor-target errors before execution can resume.
4. Two-context manifests expose the two-cycle rearm/inter-event-spacing assumption;
   the DSL still needs explicit timing requirements before that proof is unconditional.
5. The next hardware checkpoint is the real IHP hardening flow. If full v1 programs
   cannot fit 32 states or physical results leave inadequate margin, return to a
   compact encoding as a measured redesign rather than silently growing memory.
