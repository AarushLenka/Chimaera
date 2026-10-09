#!/usr/bin/env python3
"""Audit Chimaera's final physical artifacts: 0 PASS, 1 FAIL, 2 INCOMPLETE.

This checks a local or hosted run's recorded physical gates. Functional proof
and build-input provenance are separate obligations; --expected-commit checks
the hosted commit marker when one is available.
"""

import argparse
import fnmatch
import hashlib
import json
import math
from pathlib import Path


CORNERS = (
    "nom_fast_1p32V_m40C",
    "nom_typ_1p20V_25C",
    "nom_slow_1p08V_125C",
)
REQUIRED_STEPS = (
    "OpenROAD.DetailedRouting",
    "OpenROAD.RCX",
    "OpenROAD.STAPostPNR",
    "Magic.DRC",
    "KLayout.DRC",
    "Magic.SpiceExtraction",
    "Netgen.LVS",
    "Checker.TrDRC",
    "Checker.DisconnectedPins",
    "Checker.MagicDRC",
    "Checker.KLayoutDRC",
    "Checker.IllegalOverlap",
    "Checker.LVS",
    "Checker.SetupViolations",
    "Checker.HoldViolations",
    "Checker.MaxSlewViolations",
    "Checker.MaxCapViolations",
)
ZERO_METRICS = (
    "route__drc_errors",
    "antenna__violating__nets",
    "antenna__violating__pins",
    "design__critical_disconnected_pin__count",
    "design__power_grid_violation__count",
    "magic__drc_error__count",
    "klayout__drc_error__count",
    "magic__illegal_overlap__count",
    "design__lvs_error__count",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--expected-commit", help="Full hosted source commit SHA")
    parser.add_argument(
        "--grid-probe", type=Path,
        help="Read-only OpenROAD grid/bbox metrics bound to the final ODB SHA-256",
    )
    parser.add_argument(
        "--route-run", type=Path,
        help="Prior routing run with byte-identical ODB/netlist/SDC/SPEF final views",
    )
    parser.add_argument(
        "--extracted-only",
        action="store_true",
        help="Gate fresh routed timing/electrical metrics before GDS and full signoff",
    )
    args = parser.parse_args()
    failures = []
    missing = []

    def read_json(path):
        try:
            value = json.loads(path.read_text())
            if not isinstance(value, dict) or not value:
                raise ValueError("expected a nonempty JSON object")
            return value
        except (OSError, ValueError) as error:
            missing.append(f"{path}: {error}")
            return {}

    config = read_json(args.run_dir / "resolved.json")
    metrics = read_json(args.run_dir / "final/metrics.json")
    if args.grid_probe:
        supplemental = read_json(args.grid_probe)
        top = config.get("DESIGN_NAME", "tt_um_chimaera")
        odb = args.run_dir / "final/odb" / f"{top}.odb"
        try:
            with odb.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
        except OSError as error:
            missing.append(f"final ODB for grid-probe binding: {error}")
        else:
            if supplemental.get("chimaera__checked_odb__sha256") != digest:
                failures.append("grid probe does not match the final ODB SHA-256")
            else:
                # Only fill these two absent physical metrics. Timing/electrical
                # and all other signoff results always come from final metrics.
                for key in ("design__die__bbox", "design__power_grid_violation__count"):
                    if key in supplemental and key not in metrics:
                        metrics[key] = supplemental[key]

    def number(key):
        value = metrics.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            missing.append(f"metric {key}")
            return None
        if not math.isfinite(value):
            failures.append(f"{key} is not finite")
            return None
        return value

    def zero(key):
        value = number(key)
        if value is not None and value != 0:
            failures.append(f"{key} = {value}")

    def nonnegative(key):
        value = number(key)
        if value is not None and value < 0:
            failures.append(f"{key} = {value}")
        return value

    if config:
        if config.get("CLOCK_PERIOD") != 20:
            failures.append(f"CLOCK_PERIOD = {config.get('CLOCK_PERIOD')}, expected 20")
        if config.get("DIE_AREA") != [0, 0, 1289.28, 710.64]:
            failures.append(f"DIE_AREA = {config.get('DIE_AREA')}, expected 6x4 footprint")
        for flag in ("RUN_MAGIC_DRC", "RUN_KLAYOUT_DRC", "RUN_LVS"):
            if config.get(flag) != True:
                missing.append(f"{flag} is not enabled")
        for prefix in ("SETUP", "HOLD", "MAX_SLEW", "MAX_CAP"):
            key = f"{prefix}_VIOLATION_CORNERS"
            patterns = config.get(key)
            if not isinstance(patterns, list) or not all(isinstance(p, str) for p in patterns):
                missing.append(f"invalid {key}: {patterns}")
                continue
            for corner in CORNERS:
                if not any(fnmatch.fnmatchcase(corner, pattern) for pattern in patterns):
                    missing.append(f"{key} does not cover {corner}")

    def completed_steps(run):
        result = set()
        for path in sorted(run.glob("*/config.json")):
            if (path.parent / "state_out.json").is_file():
                result.add(read_json(path).get("meta", {}).get("step"))
        return result

    completed = completed_steps(args.run_dir)
    if args.route_run:
        prior_config = read_json(args.route_run / "resolved.json")
        prior_metrics = read_json(args.route_run / "final/metrics.json")
        prior_valid = True
        if prior_config.get("DESIGN_NAME") != config.get("DESIGN_NAME"):
            failures.append("prior routing run has a different design name")
            prior_valid = False
        top = config.get("DESIGN_NAME", "tt_um_chimaera")
        for relative in (f"odb/{top}.odb", f"nl/{top}.nl.v", f"sdc/{top}.sdc", f"spef/nom/{top}.nom.spef"):
            try:
                digests = []
                for run in (args.run_dir, args.route_run):
                    with (run / "final" / relative).open("rb") as stream:
                        digests.append(hashlib.file_digest(stream, "sha256").hexdigest())
            except OSError as error:
                missing.append(f"prior routing view binding {relative}: {error}")
                prior_valid = False
            else:
                if digests[0] != digests[1]:
                    failures.append(f"prior routing view differs: {relative}")
                    prior_valid = False
        # Signoff must retain the extracted results of that exact physical view.
        relevant = [key for key in prior_metrics if key.startswith((
            "timing__", "design__max_slew_violation", "design__max_cap_violation",
        ))]
        if not relevant:
            missing.append("prior routing timing/electrical metrics")
            prior_valid = False
        for key in relevant:
            if metrics.get(key) != prior_metrics[key]:
                failures.append(f"prior routing metric differs: {key}")
                prior_valid = False
        if prior_valid:
            route_steps = {
                "OpenROAD.DetailedRouting", "OpenROAD.RCX", "OpenROAD.STAPostPNR",
                "Checker.TrDRC", "Checker.DisconnectedPins",
            }
            completed.update(completed_steps(args.route_run) & route_steps)
    required_steps = REQUIRED_STEPS
    if args.extracted_only:
        required_steps = (
            "OpenROAD.DetailedRouting", "OpenROAD.RCX", "OpenROAD.STAPostPNR",
            "Checker.TrDRC", "Checker.DisconnectedPins",
        )
    for step in required_steps:
        if step not in completed:
            missing.append(f"completed stage {step}")

    for corner in CORNERS:
        slacks = []
        counts = []
        for kind in ("setup", "hold"):
            slacks.append(nonnegative(f"timing__{kind}__ws__corner:{corner}"))
            nonnegative(f"timing__{kind}__wns__corner:{corner}")
            zero(f"timing__{kind}__tns__corner:{corner}")
            key = f"timing__{kind}_vio__count__corner:{corner}"
            zero(key)
            counts.append(metrics.get(key))
        for kind in ("slew", "cap"):
            key = f"design__max_{kind}_violation__count__corner:{corner}"
            zero(key)
            counts.append(metrics.get(key))
        zero(f"timing__unannotated_net_filtered__count__corner:{corner}")
        print(f"{corner}: setup/hold slack {slacks}; setup/hold/slew/cap counts {counts}")

    for key in ZERO_METRICS:
        if args.extracted_only and key in (
            "magic__drc_error__count", "klayout__drc_error__count",
            "magic__illegal_overlap__count", "design__lvs_error__count",
        ):
            continue
        zero(key)
    utilization = number("design__instance__utilization__stdcell")
    if utilization is not None and not 0 < utilization <= 1:
        failures.append(f"invalid standard-cell utilization {utilization}")
    number("design__instance__area__stdcell")
    try:
        bbox = [float(value) for value in metrics["design__die__bbox"].split()]
    except (KeyError, AttributeError, ValueError):
        missing.append("valid metric design__die__bbox")
    else:
        if bbox != [0, 0, 1289.28, 710.64]:
            failures.append(f"routed die bounding box {bbox} differs from the 6x4 footprint")
    top = config.get("DESIGN_NAME", "tt_um_chimaera")
    for relative in (
        f"gds/{top}.gds",
        f"odb/{top}.odb",
        f"nl/{top}.nl.v",
        f"sdc/{top}.sdc",
        f"spef/nom/{top}.nom.spef",
    ):
        if args.extracted_only and relative == f"gds/{top}.gds":
            continue
        path = args.run_dir / "final" / relative
        if not path.is_file() or path.stat().st_size == 0:
            missing.append(f"nonempty final/{relative}")

    if args.expected_commit:
        marker = read_json(args.run_dir / "final/commit_id.json")
        if "commit" not in marker:
            missing.append("final/commit_id.json commit field")
        elif marker["commit"] != args.expected_commit:
            failures.append(f"commit marker {marker.get('commit')} != {args.expected_commit}")

    for message in failures:
        print(f"FAIL: {message}")
    for message in missing:
        print(f"INCOMPLETE: {message}")
    if failures:
        print("FAIL: measured violations or incompatible build constraints")
        return 1
    if missing:
        print("INCOMPLETE: required physical evidence is missing")
        return 2
    if args.extracted_only:
        print("PASS: extracted timing/electrical gates; full physical signoff still required")
    else:
        print("PASS: recorded physical gates; functional proof and source provenance remain separate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
