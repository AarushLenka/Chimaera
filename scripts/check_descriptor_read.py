#!/usr/bin/env python3
"""Check that local decoders survive synthesis and prove indexed-read equivalence."""

from collections import Counter
import json
from pathlib import Path
import subprocess
import sys


def main() -> None:
    modules = json.loads(Path(sys.argv[1]).read_text())["modules"]
    top = modules["tt_um_chimaera"]
    selectors = [cell for cell in top["cells"].values()
                 if cell["type"] == "chimaera_descriptor_selector"]
    if len(selectors) != 4:
        raise SystemExit(f"Expected four separate descriptor selectors, found {len(selectors)}")
    selector = modules["chimaera_descriptor_selector"]
    decoders = [cell for cell in selector["cells"].values()
                if cell["type"] == "chimaera_descriptor_decoder"]
    if len(decoders) != 8:
        raise SystemExit(f"Expected eight candidate decoders per selector, found {len(decoders)}")
    # Late decisions cannot enter any decoder: its address must consist only of
    # candidate input bits, structurally forbidding binary arbitration first.
    candidate_bits = set(selector["ports"]["candidates"]["bits"])
    for decoder in decoders:
        if not set(decoder["connections"]["address"]).issubset(candidate_bits):
            raise SystemExit("Late decision logic entered a candidate decoder")

    # In the full design every candidate address is already registered; input
    # events must not acquire an indirect path into the early address decoders.
    registered_bits = set()
    for cell in top["cells"].values():
        if "port_directions" not in cell:
            raise SystemExit("Netlist lacks cell port directions; read_liberty -lib before write_json")
        if "CLK" in cell["connections"] or "C" in cell["connections"]:
            if "Q" in cell["connections"] and cell["port_directions"]["Q"] == "output":
                registered_bits.update(cell["connections"]["Q"])
    for read_selector in selectors:
        if not set(read_selector["connections"]["candidates"]).issubset(registered_bits):
            raise SystemExit("A candidate address is not driven directly by a register")

    fanout: Counter[int] = Counter()
    for cell in top["cells"].values():
        for port, bits in cell["connections"].items():
            if cell["port_directions"][port] == "input":
                fanout.update(bit for bit in bits if isinstance(bit, int))

    output_bits = []
    for read_selector in selectors:
        bits = read_selector["connections"]["select_row"]
        if len(bits) != 32 or not all(isinstance(bit, int) for bit in bits):
            raise SystemExit("Descriptor selector did not retain all 32 row selects")
        output_bits.extend(bits)
    if len(set(output_bits)) != 4 * 32:
        raise SystemExit("Descriptor selectors share row-select nets")
    maximum = max(fanout[bit] for bit in output_bits)
    if maximum > 32:
        raise SystemExit(f"Descriptor row-select fanout {maximum} exceeds 32")
    for name in ("chimaera_descriptor_decoder", "chimaera_descriptor_selector"):
        if any("DFF" in cell["type"].upper() or "LATCH" in cell["type"].upper() or
               "CLK" in cell["connections"]
               for cell in modules[name]["cells"].values()):
            raise SystemExit(f"{name} contains storage")
    print(f"PASS: four local selectors, eight early decoders each, max row-select fanout {maximum}, no added storage")

    root = Path(__file__).resolve().parents[1]
    source = root / "src/chimaera_program_loader.v"
    proof = root / "test/descriptor_read_equiv.v"
    # Remove preservation attributes only in the proof model to let SAT see
    # every gate. The supplied synthesis JSON above checks the real boundaries.
    script = (f'read_verilog -sv "{source}" "{proof}"; '
              'hierarchy -top descriptor_read_equiv; '
              'setattr -mod -unset keep_hierarchy; setattr -unset keep_hierarchy; '
              'flatten; prep -top descriptor_read_equiv; '
              'sat -verify -prove equivalent 1')
    result = subprocess.run(["yosys", "-Q", "-T", "-q", "-p", script],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit(result.stdout)
    print("PASS: speculative read equals indexed read for all candidates, decisions and data")


if __name__ == "__main__":
    main()
