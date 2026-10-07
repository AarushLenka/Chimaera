#!/usr/bin/env python3
"""Run one identical Yosys+ABC screen for production and the candidate."""

from __future__ import annotations

import re
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
PRODUCTION = ROOT
CANDIDATE = Path(__file__).resolve().parent


def mapped_cells(source_root: Path) -> int:
    source_files = sorted((source_root / "src").glob("*.v"))
    read_sources = " ".join(f'"{path}"' for path in source_files)
    script = (
        f"read_verilog -sv {read_sources}; "
        "hierarchy -top tt_um_chimaera; proc; opt; memory_map; opt; "
        "techmap; opt; flatten; opt_clean; abc -g simple; stat"
    )
    result = subprocess.run(
        ["yosys", "-Q", "-T", "-p", script],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode:
        raise SystemExit(result.stdout)
    try:
        hierarchy = result.stdout.rsplit("=== design hierarchy ===", 1)[1]
        return int(re.search(r"^\s+(\d+) cells$", hierarchy, re.MULTILINE).group(1))
    except (IndexError, AttributeError) as error:
        raise SystemExit("could not parse final mapped hierarchy from Yosys output") from error


def main() -> None:
    production = mapped_cells(PRODUCTION)
    candidate = mapped_cells(CANDIDATE)
    delta = candidate - production
    percentage = (100.0 * delta / production) if production else 0.0
    print("Mapped-area screen: identical full-top Yosys proc/opt/memory_map/techmap/flatten/ABC(simple)/stat")
    print(f"production mapped generic cells: {production}")
    print(f"two-read candidate mapped generic cells: {candidate}")
    print(f"candidate delta: {delta:+d} cells ({percentage:+.2f}%)")
    print("NOTE: generic mapped-cell count is screening evidence, not IHP physical area or routed timing")


if __name__ == "__main__":
    main()
