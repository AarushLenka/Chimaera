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
    decoders = [cell for cell in top["cells"].values()
                if cell["type"] == "chimaera_descriptor_decoder"]
    if len(decoders) != 4:
        raise SystemExit(f"Expected four separate descriptor decoders, found {len(decoders)}")

    fanout: Counter[int] = Counter()
    for cell in top["cells"].values():
        for port, bits in cell["connections"].items():
            if cell["port_directions"][port] == "input":
                fanout.update(bit for bit in bits if isinstance(bit, int))

    output_bits = []
    for decoder in decoders:
        bits = decoder["connections"]["select_row"]
        if len(bits) != 32 or not all(isinstance(bit, int) for bit in bits):
            raise SystemExit("Descriptor decoder did not retain all 32 row selects")
        output_bits.extend(bits)
    if len(set(output_bits)) != 4 * 32:
        raise SystemExit("Descriptor decoders share row-select nets")
    maximum = max(fanout[bit] for bit in output_bits)
    if maximum > 32:
        raise SystemExit(f"Descriptor row-select fanout {maximum} exceeds 32")
    if any("DFF" in cell["type"] or "LATCH" in cell["type"]
           for cell in modules["chimaera_descriptor_decoder"]["cells"].values()):
        raise SystemExit("Descriptor decoder contains storage")
    print(f"PASS: four separate descriptor decoders, max row-select fanout {maximum}, no decoder storage")

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
    print("PASS: descriptor read equals the original indexed read for every address and data value")


if __name__ == "__main__":
    main()
