# Extracted timing repair screen

Phase 7 remains open. The completed branch-lookahead screen at
`/tmp/chimaera-ss-fix.JiNkH8/runs/branch-lookahead-v2/` has the following final
extracted results, using LibreLane 3.0.14 rather than the hosted tool version:

| Corner | Setup slack (ns) | Setup TNS (ns) | Setup violations | Hold slack (ns) | Hold violations |
| --- | ---: | ---: | ---: | ---: | ---: |
| FF | 9.416074 | 0 | 0 | -0.047645 | 4 |
| TT | 3.661690 | 0 | 0 | 0.125335 | 0 |
| SS | -6.309755 | -599.086280 | 300 | 0.440318 | 0 |

The route has 89 SS slew violations, 21 TT slew violations, and 10 capacitance
violations at each corner. Standard-cell area is 694344 um2, utilization
76.9426%, with zero routing DRC and antenna violations. This screen stopped
after extracted STA and did not run full DRC/LVS signoff.

The SS worst path now launches from `loaded_bank.sync_value[2]`, through the
rise detector and event/grant logic, the final descriptor row selection and
read reduction, into `reaction_cell_0.action_value[2]`. The edge detector
`input_frontend.loaded_bank/_050_` has 0.267974 pF output load, 3.409807 ns slew,
and 2.634577 ns delay. The descriptor read gate `_46696_` has 3.843759 ns slew
and 3.095545 ns delay. These measured loads motivate cell sizing and electrical
repair, without adding a synchronization or reaction cycle.

## Functional and gate corrections

The uncommitted input-pipeline edit failed `input_frontend_tb` at 6 ns because
the registered edge outputs reset to `0xff`. It also added an unapproved cycle
to loaded/execution observations. Restore the committed frontend; all three
two-flop banks and edge histories remain aligned. The removed edits are backed
up in `/tmp/chimaera-status-backup/`.

Both production `src/config.json` and `config.local.json` explicitly require
setup, slew and capacitance checks at every corner. Hold already requires every
corner. Enable Magic DRC, KLayout DRC and LVS. The actual LibreLane LVS flag is
`RUN_LVS`, not `RUN_NETGEN_LVS`. Max-slew/max-cap checkers have their own disabled
defaults, so changing only `TIMING_VIOLATION_CORNERS` does not enable them.

The actual checker methods were exercised against the failing extracted
metrics: each of setup, hold, slew and capacitance rejects the failures under
both configurations and accepts zero violations at every reported corner.

## Reproduce the local repair

Use the timing libraries associated with the input layout. This script does
not download or substitute a PDK, relax the clock, or add registers.

```sh
rtk proxy env \
  CHIMAERA_REPAIR_RUN=/absolute/path/to/completed/run \
  CHIMAERA_REPAIR_LIB_DIR=/absolute/path/to/matched/stdcell/lib \
  CHIMAERA_REPAIR_OUTPUT_PREFIX=/tmp/chimaera-repair/candidate \
  openroad -exit scripts/repair-extracted.tcl
```

Create the output directory first. The library directory must contain the
`sg13cmos5l_stdcell_{slow_1p08V_125C,typ_1p20V_25C,fast_1p32V_m40C}.lib` files.
The input run must have the normal Chimaera `final/odb`, `final/sdc`, and
`final/spef/nom` views. Existing output views/reports are rejected rather than
overwritten.

The script reads extracted parasitics, removes fillers, repairs electrical
loads and setup/hold, legalizes placement, and saves an ODB, DEF, netlist and
SDC. It removes ordinary routed wires before saving, preserving the special
power grid. Reusing the old detailed wiring as routing obstructions incorrectly
reduces available GRT resources; this was detected and corrected in the first
restart attempt.

OpenROAD warns that its resizer has no estimated parasitics and uses wire-load
models for newly inserted wiring. The provisional repair reports therefore
cannot demonstrate closure. Resume a separate Classic flow from
`OpenROAD.GlobalRouting`, overriding its input ODB/DEF/netlist/SDC with these
views. Skip `OpenROAD.ResizerTimingPostGRT` for this comparison, so the
estimate-based pass does not modify the extracted-load repair. Run through
detailed routing, extraction and final per-corner STA, then full signoff.
Retain the source manifest, input/output hashes, tool versions and all reports.

The initial trial makes 135 resize operations on 117 distinct cells, swaps
11 instances' equivalent pins, and inserts 18 electrical-repair buffers plus
22 hold buffers. Area before rerouting is 695478 um2, about 0.16% above the
input route. Functional mapped simulation passes serial load, commit/resume,
event action and timeout without delay annotation. Fresh extraction is
required before treating this as a physical improvement; the script is a local
screen and is not automatically part of the hosted Tiny Tapeout flow.

## 2026-10-09 — Fresh extracted baseline and remaining repair

The corrected `extracted-repair-v2` route completed detailed routing and RCX.
Its final extracted metrics are:

| Corner | Setup worst slack (ns) | Setup violations | Hold worst slack (ns) | Hold TNS (ns) | Hold violations | Slew violations | Capacitance violations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| FF | 10.853827 | 0 | -0.036307 | -0.049251 | 2 | 0 | 5 |
| TT | 7.625293 | 0 | 0.184567 | 0 | 0 | 0 | 5 |
| SS | 0.273237 | 0 | 0.580389 | 0 | 0 | 22 | 5 |

Setup TNS and WNS are zero at every corner. Positive setup margin is recorded
under `timing__setup__ws`, rather than the negative-only WNS metric. The
696071 um2 standard-cell area occupies 77.1341% of the 902417 um2 core;
`design__instance__area` includes fillers and must not be described as logic
area. Routing DRC, antenna, and critical disconnected-pin counts are zero.
This run stopped at STA and omitted final timing/electrical checkers, DRC and
LVS. Phase 7 remains open.

The two FF hold endpoints are `_54758_/D` (`current_shift_0[2]`) and
`_54771_/D` (`current_shift_1[7]`). The 22 SS slew violations are driven by
`input_frontend.loaded_bank/_053_`, `_43346_`, `_44307_`, `_28917_`,
`_28470_` and `_28466_`. Capacitance violations affect `fanout3247`,
`fanout4193`, `fanout3880`, `fanout4129` and `fanout3856`; the worst load is
0.329483 pF against a 0.300000 pF limit. These cells/nets are not marked
`dont_touch` in the input ODB.

A second invocation of `scripts/repair-extracted.tcl`, using this fresh
extraction, produces `/tmp/chimaera-ss-fix.JiNkH8/closure-v3.*`. It resizes
11 instances and adds 17 electrical buffers and 30 hold buffers, with
pre-route standard-cell area 696733 um2 (+0.095%). Both netlists retain 5795
sequential cells. The saved SDC differs only by a generated date comment.
The mapped `phase5_loader_top_tb` passes serial load, commit, resume, event
action and timeout using the same functional IHP cell models as the earlier
screen, without SDF annotation.

Fresh routing and full signoff are running in
`/tmp/chimaera-ss-fix.JiNkH8/runs/extracted-closure-v3-all/`. This run uses the
original screening configuration plus a JSON overlay explicitly enabling
Magic DRC, KLayout DRC, LVS, and `["*"]` coverage for setup, hold, slew and
capacitance. Check `resolved.json` for the actual arrays: LibreLane 3.0.14
CLI `--override-config` treats a JSON-looking list as a list containing that
literal string, which does not match corner names. An initial restart with
that malformed override was stopped during GRT and is excluded from evidence.
The corrected run skips only `OpenROAD.ResizerTimingPostGRT` and has no
`--to` limit. Final rerouted/extracted metrics and physical reports remain
pending; the repair-time reports are provisional.

## Audit the completed artifacts

```sh
rtk proxy python3 -B scripts/audit-physical-signoff.py /absolute/path/to/run
```

The audit returns 0 for recorded physical gates passing, 1 for measured
violations or incompatible constraints, and 2 for incomplete evidence. It
requires finite FF/TT/SS setup/hold slack, zero timing/electrical violation
counts and TNS, completed routing/extraction/STA and physical checker stages,
clean antenna/connectivity/DRC/LVS metrics, all-corner checker coverage, the
20 ns clock and 6x4 footprint, and nonempty final GDS/ODB/netlist/SDC/SPEF
views. The failing `extracted-repair-v2` artifacts are rejected with their
exact residual failures and omitted physical stages; the stopped malformed
CLI-override run is identified as incomplete.

For hosted artifacts, add `--expected-commit FULL_SHA` to check the exact
`final/commit_id.json` marker. Source-manifest selection and input hashes must
still be verified separately, alongside functional proof. A local physical
pass does not establish an exact hosted-build pass.

## 2026-10-09 — Stop v3 and preserve the rollback checkpoint

V3 completed routing and extraction. SS setup is -0.038121 ns with one
violation; all-corner hold passes. SS still has 15 slew violations and
FF/TT/SS have 4/3/3 capacitance violations. Standard-cell area is 697169 um2
at 77.2557% utilization. Routing DRC and antenna counts remain zero. The
run was stopped during Magic streamout because these measured failures
already prevent closure; full GDS/DRC/LVS remains incomplete.

Hausen requested a commit before further changes. Both v2's better SS setup
margin and v3's clean hold result, with their exact views and matched PDK,
are archived outside `/tmp`. See
[the physical rollback checkpoint](PHYSICAL_CHECKPOINT_2026-10-09.md) for
the complete corner table, archive SHA-256, view hashes and restore procedure.
No subsequent physical repair has been applied.

## 2026-10-09 — Target the measured v3 loads after checkpoint 4d7433e

`scripts/repair-closure-v3.tcl` operates only on the saved v3 routed input,
checking instance masters and receiver nets before each edit. It upsizes
`_46743_` from NAND2B-1 to NAND2B-2: the measured SS path gives that gate
0.198567 pF load and 1.847082 ns delay. It inserts four BUF-4 cells next to
the weak NAND3/NAND4/A221OI drivers responsible for SS slew failures, and
four geographically placed BUF-4 cells to split the excessive-capacitance
branches. Diode receivers remain connected with their existing load groups.
The matched library has no NAND3-2; an initial provisional trial that merely
warned about that unavailable master was rejected. The script now verifies
every actual replacement and inserted buffer. OpenROAD adds numeric suffixes
to the requested buffer/net prefixes, so verification follows the actual
receiver net rather than assuming an exact instance name.

The accepted candidate is `/tmp/chimaera-ss-fix.JiNkH8/closure-v4c.*`.
Pre-route standard-cell area is 697290 um2 (+121 um2, +0.0174% versus v3),
with all 5795 sequential cells retained. SDC differs only by a generated date
comment. Existing hold buffers are retained; no setup/hold constraints change.
`scripts/check-closure-eco.py` confirms all 47252 existing non-filler cells
keep identical pin connectivity after collapsing the eight new identity
buffers, and the resized cell has the same Boolean functions in the matched
FF/TT/SS libraries. Mapped functional simulation passes top-level serial
load, commit, resume, event action and timeout at the 20 ns clock, using the
saved functional IHP models and UDP definitions, without SDF annotation.

Fresh routing/RCX/STA runs as `extracted-closure-v4c`, resuming from GRT with
the new ODB/DEF/netlist/SDC. Estimate-based post-GRT timing repair is skipped.
The run explicitly stops at `OpenROAD.STAPostPNR`. Before any new GDS export,
run the new preliminary audit mode:

```sh
rtk proxy python3 -B scripts/audit-physical-signoff.py --extracted-only /tmp/chimaera-ss-fix.JiNkH8/runs/extracted-closure-v4c
```

This mode requires completed detailed routing/RCX/STA, clean routing/antenna/
connectivity, all-corner setup/hold/slew/capacitance and finite zero violation
metrics under the same clock/footprint. Its PASS message explicitly requires
full physical signoff afterward. The default mode continues to require full
DRC/LVS, physical checker stages and final GDS; those requirements were not
weakened. The preliminary mode rejects the real v2 residual violations.
Final extracted v4c results are recorded below.

## 2026-10-09 — Reject v4c and select the next repair baseline

`extracted-closure-v4c` completed detailed routing, RCX and all-corner STA.
The preliminary audit correctly returns FAIL:

| Corner | Setup worst slack (ns) | Setup TNS (ns) | Setup violations | Hold worst slack (ns) | Hold violations | Slew violations | Capacitance violations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| FF | 11.130627 | 0 | 0 | 0.112277 | 0 | 0 | 9 |
| TT | 7.235564 | 0 | 0 | 0.309873 | 0 | 0 | 8 |
| SS | -0.224404 | -0.444715 | 2 | 0.640001 | 0 | 27 | 8 |

Standard-cell area is 697715 um2. Routing DRC, antenna and critical
disconnected-pin counts are zero; four noncritical disconnected pins are
reported. GDS streamout and full DRC/LVS were intentionally omitted.

Compared with v3, worst SS setup loses 0.186283 ns, slew count increases
from 15 to 27, and capacitance counts increase. The resized `_46743_`
actually improves its recorded SS cell delay from 1.847082 to 1.141260 ns.
However, the worst path switches from `_54412_ -> _54832_` to
`_54412_ -> _54830_`, with a second failure to `_55027_`. The current
`_54832_` maximum-path report has +0.405237 ns slack and a different
sensitized branch. This is evidence of a changed limiting path; individual
reports do not isolate every contribution from the eight ECO buffers and
the full reroute. Do not attribute the whole regression to one component.

The next experiment should start from preserved v2 (+0.273237 ns SS setup)
and target only its two FF hold endpoints `_54758_/D` and `_54771_/D`
(-0.036307 and -0.012945 ns). Its six weak slew drivers and five over-cap
nets require separate load-aware electrical repair. Investigate preserving
unaffected routes before another full GRT/reroute. Each candidate still
requires fresh routing/RCX and all-corner timing/electrical checks; v2 remains
an incomplete baseline, not a closed design. No next candidate is launched
by this diagnosis.

## 2026-10-09 — Incremental endpoint hold ECO on preserved v2

`scripts/closure-v2-hold-eco.json` injects the installed
`Odb.InsertECOBuffers` step before detailed routing. It inserts one matched
`sg13cmos5l_dlygate4sd3_1` at each of `_54758_/D` and `_54771_/D`.
Preparation uses v2's pre-filler
`11-checker-disconnectedpins/state_out.json`, retaining existing routes.
The step locks existing cells and performs incremental global routing.

Preparation finished as `v2-hold-eco-prep`: standard-cell area is 696104 um2
(+33 um2 versus v2). `check-closure-eco.py` confirms 47125 existing
non-filler cells retain identical connectivity after collapsing the two
identity delays; all 5795 sequential cells and all-corner Boolean functions
are retained. Exported `v2-hold-eco.nl.v` passes mapped top-level serial
load, commit/resume, event action and timeout simulation at 20 ns.
`check-eco-layout.py` confirms zero changed existing placements, two changed
existing routes (`_05271_`, `_05284_`) and two new nets. This comparison is
diagnostic, not a timing/connectivity/signoff proof.

Fresh incremental detailed routing/RCX/STA runs as `v2-hold-eco-route`,
starting at `OpenROAD.DetailedRouting` and stopping at `OpenROAD.STAPostPNR`.
The exported modified netlist overrides the prep state's inherited old
netlist. The electrical repair is intentionally a subsequent experiment.
`scripts/repair-v2-electrical.py` prepares six driver-local slew buffers
and five geographically selected capacitance partitions from measured v2
loads, with original placements locked; it has not yet been applied.

### Extracted hold-only result and electrical candidate

The hold-only route completed fresh extraction. FF/TT/SS setup worst slack
is +10.863861/+7.625305/+0.273740 ns; hold is
+0.011746/+0.207277/+0.573530 ns. All setup/hold TNS and violation counts
are zero. SS slew remains 22, capacitance remains five per corner. The
new limiting FF hold endpoint is `_54346_/D`; the targeted two shift
register endpoints no longer violate. Routing DRC, antenna and critical
connectivity are clean. Area is 696104 um2 at 77.1377% utilization.
Post-route comparison retains every existing placement and changes ten
original routes plus two new nets, including nearby DRC adjustments.

The separate electrical preparation adds 11 BUF-4 cells as
`v2-electrical-eco.*`, using `repair-v2-electrical.py`. Every target master
and receiver net is validated before edits; six buffer whole weak-driver
outputs close to their drivers, five buffer selected remote load groups.
All 47127 existing non-filler placements remain fixed, and only 22 affected
nets are incrementally globally routed. Area is 696263 um2 before routing
(+159 um2 from the hold-only candidate). Connectivity/all-corner library
checks pass after collapsing the 11 identity buffers. Fresh electrical
candidate simulation and routed/extracted checks remain required.

The timing-passing hold-only route is also preserved outside `/tmp` in
`.physical-checkpoints/2026-10-09-v2-hold-pass/v2-hold-route.tar.zst`
(206 MiB; SHA-256
`9fa287a4801da937da8caf83ff2b9b2fd447482a0bff61021db2614c589b0a74`).
Archive comparison against the source files passes. This archive contains
the hold prep/route directories and exported netlist; the matched PDK,
libraries and earlier route dependencies remain in the original rollback
archive. It preserves setup/hold evidence, not complete physical signoff.

Electrical candidate mapped simulation passes serial load, commit/resume,
event action and timeout. Its fresh incremental detailed route/RCX/STA is
running as `v2-electrical-eco-route`; electrical and timing acceptance is
still pending.

## 2026-10-09 — Extracted timing and electrical closure passes

The electrical ECO completes fresh detailed routing, RCX and all-corner STA:

| Corner | Setup worst slack (ns) | Hold worst slack (ns) | Setup / hold TNS (ns) | Setup / hold / slew / cap violations |
| --- | ---: | ---: | --- | --- |
| FF | 11.125743 | 0.012662 | 0 / 0 | 0 / 0 / 0 / 0 |
| TT | 7.622675 | 0.208263 | 0 / 0 | 0 / 0 / 0 / 0 |
| SS | 0.265928 | 0.574717 | 0 / 0 | 0 / 0 / 0 / 0 |

Negative-only WNS is zero at every corner. Area is 696263 um2 at 77.1554%
utilization, +192 um2 (+0.0276%) versus preserved v2. Routed DRC, antenna,
critical connectivity and filtered unannotated-net counts are zero. All
5795 sequential cells are retained. Final netlist connectivity/functions
match the hold-only route after collapsing the eleven electrical buffers.
Post-route DEF comparison changes 44 original routes and no existing
placements, versus the hold-only input.

`scripts/check-eco-grid.tcl` checks VPWR and VGND on the final ODB, verifies
grid shapes and external terminals exist, rejects nonempty error reports,
and records actual die bounds. The read-only probe binds its metrics to
the ODB SHA-256, checked before and after execution:
`abc2cb144e87cab1ca7bc1d94763c1da09e3cc2826d3749ab226b9b1ee658707`.
Both grids are connected; die bounds are 0, 0, 1289.28, 710.64 um.

The completed preliminary audit passes:

```sh
rtk proxy python3 -B scripts/audit-physical-signoff.py --extracted-only --grid-probe /tmp/chimaera-ss-fix.JiNkH8/v2-electrical-grid.metrics.json /tmp/chimaera-ss-fix.JiNkH8/runs/v2-electrical-eco-route
```

The probe supplements only absent grid/bbox metrics, never timing or
electrical results. Supplying the hold-only route's probe for the electrical
route correctly fails the SHA-256 binding. The default audit still requires
full physical signoff. Its `--route-run` option accepts prior routing stage
evidence only with byte-identical ODB/netlist/SDC/SPEF and identical recorded
timing/electrical metrics; signoff stages must complete in the current run.

This passing extraction is preserved outside `/tmp` in
`.physical-checkpoints/2026-10-09-extracted-closure-pass/v2-electrical-route.tar.zst`,
SHA-256 `fce9b654d34f5ff1e88d589065a2ba2abd4208a5ff395dfeaf9b49c566b32392`.
The archive compares identically against its source files. It includes the
route, ECO views/netlist and grid probe. Earlier hold prep/route and matched
PDK dependencies are preserved in the other checkpoint archives.

Full GDS/DRC/LVS runs separately as `v2-closure-signoff`, resuming at
`OpenROAD.IRDropReport` from this passing STA state. It is currently in
Magic streamout. Phase 7 and exact hosted-build signoff remain open; these
local physical ECO scripts are tied to the validated saved route, not a
claim that an ordinary RTL-to-GDS workflow automatically reproduces it.
