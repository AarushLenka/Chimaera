#!/usr/bin/env python3
"""Measure placement and route preservation between OpenROAD DEF snapshots.

This is a diagnostic comparison, not a DRC, connectivity or timing checker.
"""

import argparse
import re
from pathlib import Path


def section(text, name):
    match = re.search(rf"^{name} \d+ ;\n(.*?)^END {name}$", text, re.M | re.S)
    if match is None:
        raise ValueError(f"missing DEF section {name}")
    return re.findall(r"^\s*-\s+(\S+)\s+(.*?);", match[1], re.M | re.S)


def snapshot(path):
    text = path.read_text()
    placements = {}
    for name, body in section(text, "COMPONENTS"):
        master = body.split()[0]
        if master.startswith(("sg13cmos5l_fill_", "sg13cmos5l_decap_")):
            continue
        placed = re.search(r"\+ (?:PLACED|FIXED|COVER)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\w+)", body)
        if placed is None:
            raise ValueError(f"missing placement for {name}")
        placements[name] = placed.groups()
    routes = {}
    for name, body in section(text, "NETS"):
        routing = re.search(r"\+ (?:ROUTED|FIXED|COVER)\b.*", body, re.S)
        routes[name] = " ".join(routing[0].split()) if routing else ""
    return placements, routes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gold", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    old_cells, old_routes = snapshot(args.gold)
    new_cells, new_routes = snapshot(args.candidate)
    missing = old_cells.keys() - new_cells.keys()
    if missing:
        raise ValueError(f"existing cells missing: {sorted(missing)[:10]}")
    moved = [name for name in old_cells if old_cells[name] != new_cells[name]]
    changed = [name for name in old_routes if old_routes[name] != new_routes.get(name)]
    print(f"Existing non-filler cells: {len(old_cells)}; changed placements: {len(moved)}")
    print(f"Existing signal nets: {len(old_routes)}; changed routes: {len(changed)}; new nets: {len(new_routes.keys() - old_routes.keys())}")
    print(f"First changed placements: {moved[:20]}")
    print(f"First changed routes: {changed[:20]}")


if __name__ == "__main__":
    main()
