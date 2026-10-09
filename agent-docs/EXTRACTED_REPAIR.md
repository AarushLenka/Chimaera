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
