#!/usr/bin/env python3
"""Check the production private-read topology and prove each read bus."""

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
        if len(rows) != 32 or not all(isinstance(bit, int) for bit in rows):
            raise SystemExit("A context selector did not retain 32 row-select outputs")
        row_select_bits.extend(rows)
    if len(set(row_select_bits)) != 4 * 32:
        raise SystemExit("Context selector row-select outputs were merged")
    context_row_fanout = max(fanout[bit] for bit in row_select_bits)
    for name in ("chimaera_context_selector", "chimaera_descriptor_decoder"):
        if any("DFF" in cell["type"].upper() or "LATCH" in cell["type"].upper() or
               "CLK" in cell.get("connections", {})
               for cell in modules[name]["cells"].values()):
            raise SystemExit(f"{name} contains storage")

    loader_text = (source_root / "src/chimaera_program_loader.v").read_text()
    selector_text = loader_text.split("module chimaera_context_selector", 1)[1]
    if "select_request_1" in selector_text.split("module chimaera_descriptor_selector", 1)[0]:
        raise SystemExit("Cross-context arbitration entered the context selector source")
    if "select_request_1" in loader_text:
        raise SystemExit("Runtime arbitration signal leaked into the loader read network")
    if "descriptor_select_1" in loader_text or "selected_row" in loader_text:
        raise SystemExit("Cross-context final row selection remains in the loader")
    runtime_text = (source_root / "src/chimaera_program_runtime.v").read_text()
    for equation in ("wire service_0", "wire select_request_1", "wire load_0", "wire load_1"):
        if equation not in runtime_text:
            raise SystemExit(f"Remaining arbitration/load equation missing: {equation}")
    print(
        "PASS: four context selector banks, four decoders each, distinct rows, "
        f"maximum row-select fanout {context_row_fanout}"
    )
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
    print("PASS: two private buses equal the context-local selector for all decisions and descriptor data")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_descriptor_read.py NETLIST")
    netlist = Path(sys.argv[1])
    repo_root = Path(__file__).resolve().parents[1]
    source_root = repo_root
    _check_structure(netlist, source_root)
    _prove(source_root, repo_root)


if __name__ == "__main__":
    main()
