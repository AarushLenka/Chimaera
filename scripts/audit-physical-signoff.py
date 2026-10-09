#!/usr/bin/env python3
"""Audit Chimaera's final physical artifacts: 0 PASS, 1 FAIL, 2 INCOMPLETE.

This checks a local or hosted run's recorded physical gates. Functional proof
and build-input provenance are separate obligations; --expected-commit checks
the hosted commit marker when one is available.
"""

import argparse
import fnmatch
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

    completed = set()
    for path in sorted(args.run_dir.glob("*/config.json")):
        if (path.parent / "state_out.json").is_file():
            step = read_json(path).get("meta", {}).get("step")
            completed.add(step)
    for step in REQUIRED_STEPS:
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
    print("PASS: recorded physical gates; functional proof and source provenance remain separate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
