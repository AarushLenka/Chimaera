#!/usr/bin/env python3
"""Check the isolated two-read netlist and prove each private read bus."""

from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import subprocess
import sys


def _check_structure(netlist: Path, source_root: Path) -> None:
    modules = json.loads(netlist.read_text())["modules"]
    top = modules["tt_um_chimaera"]
    selectors = [cell for cell in top["cells"].values()
                 if cell["type"] == "chimaera_context_selector"]
    if len(selectors) != 4:
        raise SystemExit(f"Expected four retained context selector banks, found {len(selectors)}")
    selector = modules["chimaera_context_selector"]
    decoders = [cell for cell in selector["cells"].values()
                if cell["type"] == "chimaera_descriptor_decoder"]
    if len(decoders) != 4:
        raise SystemExit(f"Expected four early decoders per context selector, found {len(decoders)}")
    candidate_bits = set(selector["ports"]["candidates"]["bits"])
    for decoder in decoders:
        if not set(decoder["connections"]["address"]).issubset(candidate_bits):
            raise SystemExit("A late decision entered a context decoder address")

    registered_bits = set()
    for cell in top["cells"].values():
        directions = cell.get("port_directions", {})
        if ("Q" in cell.get("connections", {}) and
                directions.get("Q") == "output" and
                ("CLK" in cell.get("connections", {}) or
                 "C" in cell.get("connections", {}))):
            registered_bits.update(cell["connections"]["Q"])
    for selector_cell in selectors:
        if not set(selector_cell["connections"]["candidates"]).issubset(registered_bits):
            raise SystemExit("A descriptor candidate address is not register-driven")

    fanout: Counter[int] = Counter()
    for cell in top["cells"].values():
        for port, bits in cell.get("connections", {}).items():
            if cell.get("port_directions", {}).get(port) == "input":
                fanout.update(bit for bit in bits if isinstance(bit, int))
    row_select_bits = []
    for selector_cell in selectors:
        rows = selector_cell["connections"]["select_row"]
        if len(rows) != 32:
            raise SystemExit("A context selector did not retain 32 row-select outputs")
        row_select_bits.extend(rows)
    if len(set(row_select_bits)) != 4 * 32:
        raise SystemExit("Context selector row-select outputs were merged")
    maximum = max(fanout[bit] for bit in row_select_bits)

    loader_text = (source_root / "src/chimaera_program_loader.v").read_text()
    selector_text = loader_text.split("module chimaera_context_selector", 1)[1]
    if "select_request_1" in selector_text.split("module chimaera_descriptor_selector", 1)[0]:
        raise SystemExit("Cross-context arbitration entered the context selector source")
    if "select_request_1" in loader_text:
        raise SystemExit("Runtime arbitration signal leaked into the loader read network")
    runtime_text = (source_root / "src/chimaera_program_runtime.v").read_text()
    for equation in ("wire service_0", "wire select_request_1", "wire load_0", "wire load_1"):
        if equation not in runtime_text:
            raise SystemExit(f"Remaining arbitration/load equation missing: {equation}")
    print(f"PASS: four context selector banks, four decoders each, distinct rows, max row-select fanout {maximum}")
    print("PASS: selector source has no cross-context grant; arbitration remains on load_0/load_1")


def _prove(source_root: Path, repo_root: Path) -> None:
    source = source_root / "src/chimaera_program_loader.v"
    proof = source_root / "test/descriptor_two_read_equiv.v"
    script = (
        f'read_verilog -sv "{source}" "{proof}"; '
        "hierarchy -top descriptor_two_read_equiv; "
        "setattr -mod -unset keep_hierarchy; setattr -unset keep_hierarchy; "
        "flatten; prep -top descriptor_two_read_equiv; "
        "sat -verify -prove equivalent 1"
    )
    result = subprocess.run(
        ["yosys", "-Q", "-T", "-q", "-p", script],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode:
        raise SystemExit(result.stdout)
    print("PASS: two private buses equal the shared selector for all decisions and descriptor data")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: check_two_read_topology.py NETLIST CANDIDATE_ROOT")
    netlist = Path(sys.argv[1])
    source_root = Path(sys.argv[2]).resolve()
    repo_root = source_root.parents[1]
    _check_structure(netlist, source_root)
    _prove(source_root, repo_root)


if __name__ == "__main__":
    main()
