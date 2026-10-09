# SS setup diagnosis and branch lookahead

## Exact failing build

`GDS_logs_39c1395/runs/wokwi/final/commit_id.json` identifies
`39c139509a4f45b40132d9a48f82cec6b8f6120f`, workflow `37750553768`.
All archived RTL files match the checkout before this fix. The build uses the
hybrid shared final descriptor bus, despite the commit subject referring to
private reads. Clock period is 20 ns and the floorplan is 6x4 tiles.

| Corner | Worst setup slack (ns) | Setup TNS (ns) | Violations |
| --- | ---: | ---: | ---: |
| FF | 8.993617 | 0 | 0 |
| TT | 3.061777 | 0 | 0 |
| SS | -7.130902 | -815.552449 | 283 |

The worst path starts at `input_frontend.loaded_bank/_103_/Q`, the synchronized
input bit 7, and ends at `_55837_/D`, `reaction_cell_0.timer[2]`. It traverses
the sampled-bit reduction, mutation match predicates, four corruption XORs,
the byte branch comparison, descriptor row selection, and the shared read tree.

| Point on the SS path | Arrival time (ns) |
| --- | ---: |
| Synchronized input Q | 1.892144 |
| `loaded_runtime.branch_condition_1` | 15.267402 |
| Context 1 selected row | 17.066614 |
| Read reduction `_44592_/Y` | 25.985487 |
| Endpoint D | 27.939173 |
| Required endpoint arrival | 20.808271 |

The exact libraries from IHP PDK `2bbec755dc67ca3db0261c3d6163e15735d66710`,
final netlist, SDC, and extracted SPEF reproduce this path and its delays to
six decimal places using local OpenSTA.

## Why previous local screens did not predict it

A local reroute of the archived post-GRT placement reports setup `+0.826596 ns`
while the final extracted artifact reports `-7.130902 ns`. Critical loads are
underestimated: `fanout3560` is `0.240202 pF` in the local global-route estimate
versus `0.391955 pF` after extraction; `_44592_` is `0.098242 pF` versus
`0.192280 pF`. This is a comparative screen with a different tool version and
rerouted geometry, not a byte-identical replay of the hosted global route.

The archived resizer layer-RC table contains zeros. This was investigated and
ruled out as the cause: OpenROAD falls back to the technology LEF when explicit
layer RC is zero. Setting the same LEF values explicitly changes neither the
estimated slack nor setup repair. No such redundant RC override is retained.

## Implemented remedy

`chimaera_branch_predicate` computes the branch result for both possible serial
sample bits from registered state, control, mutation configuration, and LFSR.
Only the sampled-bit reduction and a Boolean mux remain on the incoming-pin
branch path. The retained module boundary prevents ABC from merging the late
sample back into mutation and byte-comparison logic.

The four corruption masks combine in parallel because all their match predicates
test the original shifted byte. The original mutation/action outputs retain
their implementation; only the branch computation is replaced. No new register,
clock change, memory-depth change, descriptor-format change, or scheduling change
is introduced.

The production configuration now loads FF/TT/SS for PNR, places SS first for
single-corner intermediate reports, and enforces final setup at every corner.
Previously the PDK setup checker selected `*typ*`. The local 3.0.14
`STAMidPNR` invokes a single-corner script with all libraries and reports only
the first defined corner; its violation enumeration also lacks a corner
filter. Final per-corner extracted reports are therefore the evidence used
below, not the mislabeled intermediate register-to-register metrics.

A regression against the actual local LibreLane checker reproduces the old
gate accepting the archived 283 SS failures with a warning. The new explicit
setup override rejects those failures and accepts zero violations at all
three corners. This is a checker regression, not a candidate timing result.

## Verification and measured cost

The local gate passes 30 host tests, five demos, all standalone benches, the
260-cycle runtime miter, Phase 4 smoke, strict lint, synthesis, and descriptor
SAT/topology checks. The miter uses frozen pre-lookahead execution logic so
changing the candidate does not change its reference. Observed cases include
54 simultaneous fires, 54 deferred reloads, 160 timeouts, both branch outcomes,
106 dynamic-selector cases, and 244 saturated cycles.

`scripts/check_branch_lookahead.py` proves equivalence for arbitrary registered
state, samples, and all four mutation records. Its backward netlist-cone check
confirms that only registered state feeds both predicate modules. These checks
also pass on the IHP-mapped netlist.

Matched local AREA-0 synthesis with LibreLane 3.0.14 and the exact timing libraries:

| RTL | Mapped area (um2) | Sequential cell count |
| --- | ---: | ---: |
| Archived 39c1395 baseline | 532631.6352 | 5795 |
| Branch lookahead | 541146.8788 | 5795 |

The measured increase is `8515.2436 um2` (`1.60%`). These are synthesis areas,
not routed fit evidence. Local routing/extraction completed in
`/tmp/chimaera-ss-fix.JiNkH8/runs/branch-lookahead-v2/`; its floorplan and PDK
libraries match the artifact, but LibreLane/OpenROAD versions differ from the
hosted 3.1.0.dev3 flow. Exact-commit hosted signoff remains required for Phase 7.

The completed screen still fails SS setup at -6.309755 ns with 300 violations,
FF hold at -0.047645 ns with four violations, and slew/capacitance checks.
The worst path now starts at synchronized input bit 2 through rising-edge
detection, event/grant logic and descriptor selection/read. See
[the extracted-repair evidence](EXTRACTED_REPAIR.md) for per-corner results,
the restored frontend behavior, mandatory signoff gates, and subsequent
physical repair screens. Branch lookahead alone has not closed timing.
