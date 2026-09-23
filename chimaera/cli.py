"""Command-line entry point for the Chimaera compiler front end."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

from .compiler import compile_source
from .errors import ChimaeraError


def _binding(value: str) -> tuple[str, str]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("binding must be ROLE=uio[N]")
    role, physical = value.split("=", 1)
    if not role or not physical:
        raise argparse.ArgumentTypeError("binding must be ROLE=uio[N]")
    return role, physical


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Compile a Chimaera DSL source file")
    parser.add_argument("source", type=Path)
    parser.add_argument("--clock-hz", type=int, required=True)
    parser.add_argument(
        "--bind",
        action="append",
        type=_binding,
        default=[],
        metavar="PROTOCOL.ROLE=uio[N]",
        help="bind a logical pin role to a bidirectional hardware pin",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="artifact prefix (default: source path without suffix)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(argv)
    bindings = dict(arguments.bind)
    if len(bindings) != len(arguments.bind):
        parser.error("each logical role may be bound only once")
    prefix = arguments.output or arguments.source.with_suffix("")
    try:
        compilation = compile_source(
            arguments.source.read_text(encoding="utf-8"),
            clock_hz=arguments.clock_hz,
            bindings=bindings,
        )
    except (OSError, ChimaeraError) as error:
        parser.exit(1, f"chimaera: error: {error}\n")

    prefix.parent.mkdir(parents=True, exist_ok=True)
    prefix.with_suffix(".chobj").write_bytes(compilation.object_bytes)
    prefix.with_suffix(".manifest.json").write_text(compilation.manifest_json(), encoding="utf-8")
    prefix.with_suffix(".states.dot").write_text(compilation.state_diagram, encoding="utf-8")
    prefix.with_suffix(".wave.txt").write_text(compilation.waveform_expectation, encoding="utf-8")
    prefix.with_suffix(".random_test.py").write_text(compilation.randomized_test, encoding="utf-8")
    if compilation.packed_program is not None:
        prefix.with_suffix(".loader.bin").write_bytes(compilation.packed_program.loader_bytes)
    print(
        f"compiled {arguments.source}: {compilation.manifest['state_descriptors']} states, "
        f"CRC32 {compilation.manifest['program_crc32']}"
    )
    if compilation.packed_program is not None:
        print(
            f"chip-loader stream: {len(compilation.packed_program.descriptors)} descriptors, "
            f"CRC16 {compilation.packed_program.crc16:04x}"
        )
    else:
        print("host object emitted; source uses features not yet lowerable to the chip-loader ABI")
    return 0
