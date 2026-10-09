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
