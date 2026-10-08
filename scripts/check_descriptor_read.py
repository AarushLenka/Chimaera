#!/usr/bin/env python3
"""Check the production hybrid read netlist and prove its shared read slice."""

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
    if len(selectors) != 2:
        raise SystemExit(f"Expected two retained context selectors, found {len(selectors)}")
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
        if cell.get("connections") and "port_directions" not in cell:
            raise SystemExit("Netlist lacks cell directions; read_liberty -lib before write_json")
        directions = cell.get("port_directions", {})
        if ("Q" in cell.get("connections", {}) and
                directions.get("Q") == "output" and
                ("CLK" in cell.get("connections", {}) or
                 "C" in cell.get("connections", {}))):
            registered_bits.update(cell["connections"]["Q"])
    for selector_cell in selectors:
        if not set(selector_cell["connections"]["candidates"]).issubset(registered_bits):
            raise SystemExit("A descriptor candidate address is not register-driven")

    # Check the integrated manifest-selected top, not just selector source text:
    # every late input must be that context's own runtime signal.
    for cell_name, cell in top["cells"].items():
        if cell["type"] != "chimaera_context_selector":
            continue
        contexts = [index for index in range(2)
                    if f"context_read[{index}]" in cell_name]
        if len(contexts) != 1:
            raise SystemExit(f"Unrecognized context selector: {cell_name}")
        context = contexts[0]
        for port in ("pending", "fire_timeout", "branch_condition"):
            aliases = [f"loaded_runtime.{port}_{context}"]
            if port == "fire_timeout":
                # opt_clean -purge can retain the execution-engine port name
                # instead of the runtime wire's equivalent alias.
                aliases.append(f"loaded_runtime.execution_engine.fire_timeout_{context}")
            names = [name for name in aliases if name in top["netnames"]]
            if not names:
                raise SystemExit(f"Missing runtime net for context {context} {port}")
            expected = top["netnames"][names[0]]["bits"]
            if cell["connections"][port] != expected:
                raise SystemExit(f"{cell_name}.{port} is not context-local")

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
    if len(set(row_select_bits)) != 2 * 32:
        raise SystemExit("Context selector row-select outputs were merged")
    context_row_fanout = max(fanout[bit] for bit in row_select_bits)
    if context_row_fanout > 2:
        raise SystemExit(
            f"Context row-select fanout into the final mux {context_row_fanout} exceeds 2"
        )
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
    if "descriptor_select_1" not in loader_text or "assign selected_row[0]" not in loader_text:
        raise SystemExit("Hybrid final row selection is missing from the loader")
    runtime_text = (source_root / "src/chimaera_program_runtime.v").read_text()
    for equation in ("wire service_0", "wire select_request_1", "wire load_0", "wire load_1",
                     "assign descriptor_select_1 = select_request_1"):
        if equation not in runtime_text:
            raise SystemExit(f"Remaining arbitration/load equation missing: {equation}")
    print(
        "PASS: two context selectors, four decoders each, distinct rows, "
        f"context-row fanout into final mux {context_row_fanout}"
    )
    print("PASS: context decisions are local; arbitration reaches only the final decoded-row mux and reload enables")


def _prove(source_root: Path, repo_root: Path) -> None:
    source = source_root / "src/chimaera_program_loader.v"
    proof = source_root / "test/descriptor_hybrid_read_equiv.v"
    script = (
        f'read_verilog -sv "{source}" "{proof}"; '
        "hierarchy -top descriptor_hybrid_read_equiv; "
        "setattr -mod -unset keep_hierarchy; setattr -unset keep_hierarchy; "
        "flatten; prep -top descriptor_hybrid_read_equiv; "
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
    print("PASS: hybrid shared bus equals the selected context read for all decisions and descriptor data")


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
