#!/usr/bin/env python3
"""Check the retained combinational matcher boundaries and prove their function."""

import json
from pathlib import Path
import subprocess
import sys


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_event_matcher.py NETLIST")
    modules = json.loads(Path(sys.argv[1]).read_text())["modules"]
    top = modules["tt_um_chimaera"]
    matchers = {
        name: cell for name, cell in top["cells"].items()
        if cell["type"] == "chimaera_event_matcher"
    }
    expected = {
        "reaction_cell_0.event_matcher", "reaction_cell_1.event_matcher",
        "loaded_runtime.reaction_cell_0.event_matcher",
        "loaded_runtime.reaction_cell_1.event_matcher",
    }
    if set(matchers) != expected:
        raise SystemExit(f"Incorrect retained event matchers: {sorted(matchers)}")
    for cell in matchers.values():
        if len(cell["connections"]["event_match"]) != 1:
            raise SystemExit("An event matcher lost its Boolean output")
    for gate in modules["chimaera_event_matcher"]["cells"].values():
        if any(key in gate.get("connections", {}) for key in ("CLK", "C")) or any(
                name in gate["type"].upper() for name in ("DFF", "LATCH", "MEM")):
            raise SystemExit("Event matching unexpectedly added storage")
    print("PASS: four retained event matchers are combinational")

    root = Path(__file__).resolve().parents[1]
    script = (
        "read_verilog -sv src/chimaera_reaction_cell.v test/event_matcher_equiv.v; "
        "hierarchy -top event_matcher_equiv; "
        "setattr -mod -unset keep_hierarchy; setattr -unset keep_hierarchy; "
        "flatten; prep -top event_matcher_equiv; "
        "sat -verify -prove equivalent 1"
    )
    result = subprocess.run(["yosys", "-Q", "-T", "-q", "-p", script],
                            cwd=root, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise SystemExit(result.stdout)
    print("PASS: event matching is equivalent for arbitrary pins, masks, values and all 16 kinds")


if __name__ == "__main__":
    main()
