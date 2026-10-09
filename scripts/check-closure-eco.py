#!/usr/bin/env python3
"""Check this ECO's identity buffers, library functions and cell connectivity.

This verifies OpenROAD-emitted flat cell netlists, not arbitrary Verilog. It
rejects other logic changes; physical filler/decap removal is permitted. Routed STA
and mapped simulation remain separate checks.
"""

import argparse
import re
from pathlib import Path


CELL = re.compile(
    r"^\s*(sg13cmos5l_\w+)\s+(\\\S+|\w+)\s*\((.*?)\);", re.M | re.S
)
PIN = re.compile(r"\.(\w+)\(([^()]*)\)")


def cells(path):
    text = path.read_text()
    result = {}
    for master, name, body in CELL.findall(text):
        if master.startswith(("sg13cmos5l_fill_", "sg13cmos5l_decap_")):
            continue
        pins = {p: "".join(v.split()) for p, v in PIN.findall(body)}
        if not pins or name in result:
            raise ValueError(f"unparsed or duplicate cell {name}")
        result[name] = (master, pins)
    if not result:
        raise ValueError(f"no cells parsed in {path}")
    assigns = sorted("".join(a.split()) for a in re.findall(r"^\s*assign\s+(.*?);", text, re.M))
    return result, assigns


def functions(library, master, allow_antenna=False):
    start = re.search(r"\bcell\s*\(\s*" + re.escape(master) + r"\s*\)\s*\{", library)
    if start is None:
        raise ValueError(f"missing library master {master}")
    end = re.search(r"\bcell\s*\(", library[start.end():])
    block = library[start.end(): start.end() + end.start()] if end else library[start.end():]
    values = tuple("".join(v.split()) for v in re.findall(r'\bfunction\s*:\s*"([^"]+)"', block))
    if allow_antenna and master == "sg13cmos5l_antennanp":
        if values or re.search(r"\bdirection\s*:\s*(output|inout)\b", block):
            raise ValueError("antenna cell has a logic output")
        return values
    if not values:
        raise ValueError(f"no Boolean output function for {master}")
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gold", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("lib_dir", type=Path)
    args = parser.parse_args()
    gold, gold_assigns = cells(args.gold)
    candidate, candidate_assigns = cells(args.candidate)
    added = candidate.keys() - gold.keys()
    if gold.keys() - candidate.keys():
        raise ValueError("existing non-filler cells were removed")
    if not added:
        raise ValueError("no inserted ECO buffers")
    aliases = {}
    inserted_masters = set()
    antenna_count = 0
    for name in added:
        master, pins = candidate[name]
        if master == "sg13cmos5l_antennanp" and set(pins) == {"A"}:
            antenna_count += 1
            continue
        expected = (
            name.startswith("closure_v4_") and master == "sg13cmos5l_buf_4"
        ) or (
            re.fullmatch(r"eco_buffer_\d+", name)
            and master in {"sg13cmos5l_buf_1", "sg13cmos5l_buf_4", "sg13cmos5l_dlygate4sd3_1"}
        )
        if not expected or set(pins) != {"A", "X"}:
            raise ValueError(f"unexpected inserted cell {name}: {master}")
        if pins["X"] in aliases:
            raise ValueError("multiple ECO drivers on a net")
        aliases[pins["X"]] = pins["A"]
        inserted_masters.add(master)

    def resolve(value):
        visited = set()
        while value in aliases:
            if value in visited:
                raise ValueError("ECO buffer cycle")
            visited.add(value)
            value = aliases[value]
        return value

    resized = []
    for name, (old_master, old_pins) in gold.items():
        new_master, new_pins = candidate[name]
        if old_pins != {p: resolve(v) for p, v in new_pins.items()}:
            raise ValueError(f"nonidentity connectivity change at {name}")
        if old_master != new_master:
            if old_master.startswith("sg13cmos5l_df") or new_master.startswith("sg13cmos5l_df"):
                raise ValueError(f"sequential cell changed at {name}")
            resized.append((name, old_master, new_master))
    if gold_assigns != candidate_assigns:
        raise ValueError("continuous assignments changed")
    for suffix in ("slow_1p08V_125C", "typ_1p20V_25C", "fast_1p32V_m40C"):
        library = (args.lib_dir / f"sg13cmos5l_stdcell_{suffix}.lib").read_text()
        for master in inserted_masters:
            if functions(library, master) != ("A",):
                raise ValueError(f"inserted buffer {master} is not an identity function")
        if antenna_count:
            functions(library, "sg13cmos5l_antennanp", allow_antenna=True)
        for name, old, new in resized:
            if functions(library, old) != functions(library, new):
                raise ValueError(f"Boolean function changed at {name}, {suffix}")
    sequential = sum(master.startswith("sg13cmos5l_df") for master, _ in gold.values())
    print(f"PASS: {len(gold)} existing non-filler cells retain connectivity after collapsing {len(aliases)} identity buffers; {antenna_count} added antenna cells have no outputs")
    print(f"PASS: {len(resized)} resized cells have matching Boolean functions at FF/TT/SS; {sequential} sequential cells retained")


if __name__ == "__main__":
    main()
