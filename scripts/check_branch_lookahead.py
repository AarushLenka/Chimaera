#!/usr/bin/env python3
"""Prove branch lookahead and check that mapped predicates have no live pin inputs."""

import json
from pathlib import Path
import subprocess
import sys


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_branch_lookahead.py NETLIST")
    modules = json.loads(Path(sys.argv[1]).read_text())["modules"]
    top = modules["tt_um_chimaera"]
    predicates = [cell for cell in top["cells"].values()
                  if "chimaera_branch_predicate" in cell["type"]]
    if len(predicates) != 2:
        raise SystemExit(f"Expected two retained branch predicates, found {len(predicates)}")
    if any(len(cell["connections"]["condition_by_sample"]) != 2 for cell in predicates):
        raise SystemExit("A branch predicate lost one sampled-bit hypothesis")

    # Walk backwards from every predicate input. Flip-flop outputs end the
    # walk: this rejects any reintroduced combinational path from a live pin,
    # event matcher, sample bus, or arbitration decision into the byte logic.
    drivers = {}
    registered = set()
    for cell in top["cells"].values():
        ports = cell.get("port_directions", {})
        outputs = [bit for name, bits in cell.get("connections", {}).items()
                   if ports.get(name) == "output" for bit in bits if isinstance(bit, int)]
        if "Q" in cell.get("connections", {}) and (
                "CLK" in cell["connections"] or "C" in cell["connections"]):
            registered.update(cell["connections"]["Q"])
        for bit in outputs:
            drivers[bit] = [input_bit for name, bits in cell["connections"].items()
                            if ports.get(name) == "input" for input_bit in bits
                            if isinstance(input_bit, int)]
    live_inputs = {bit for port in top["ports"].values()
                   if port["direction"] == "input" for bit in port["bits"]}
    seen = set()
    pending = [bit for cell in predicates for name, bits in cell["connections"].items()
               if cell["port_directions"][name] == "input" for bit in bits
               if isinstance(bit, int)]
    while pending:
        bit = pending.pop()
        if bit in seen or bit in registered:
            continue
        seen.add(bit)
        if bit in live_inputs:
            raise SystemExit(f"Live top-level input bit {bit} reaches a branch predicate")
        if bit not in drivers:
            raise SystemExit(f"Unresolved driver of branch predicate input bit {bit}")
        pending.extend(drivers[bit])
    for cell in predicates:
        if any("CLK" in gate.get("connections", {}) or
               "DFF" in gate["type"].upper() or "LATCH" in gate["type"].upper()
               for gate in modules[cell["type"]]["cells"].values()):
            raise SystemExit("Branch lookahead unexpectedly added storage")
    print("PASS: two combinational branch predicates each compute both sampled-bit cases from registered state")

    root = Path(__file__).resolve().parents[1]
    script = (
        'read_verilog -sv src/chimaera_generic_execution_engine.v '
        'test/branch_lookahead_equiv.v; hierarchy -top branch_lookahead_equiv; '
        'setattr -mod -unset keep_hierarchy; setattr -unset keep_hierarchy; '
        'flatten; prep -top branch_lookahead_equiv; sat -verify -prove equivalent 1'
    )
    result = subprocess.run(["yosys", "-Q", "-T", "-q", "-p", script],
                            cwd=root, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    if result.returncode:
        raise SystemExit(result.stdout)
    print("PASS: branch lookahead equals the original branch for arbitrary state, samples, and all four mutations")


if __name__ == "__main__":
    main()
