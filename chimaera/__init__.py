"""Host-side Chimaera DSL toolchain."""

from .compiler import Compilation, HostObject, compile_source, load_host_object
from .backend import PackedProgram, PackingError, crc16_ccitt, pack_program
from .errors import ChimaeraError, CompileError, ParseError
from .model import ChipReferenceModel, ChipStepResult, ReferenceModel, StepResult
from .parser import parse
from .rtl_replay import ReplayCycle, run_runtime_replay

__all__ = [
    "ChimaeraError",
    "ChipReferenceModel",
    "ChipStepResult",
    "Compilation",
    "CompileError",
    "HostObject",
    "ParseError",
    "PackedProgram",
    "PackingError",
    "ReferenceModel",
    "ReplayCycle",
    "StepResult",
    "compile_source",
    "crc16_ccitt",
    "load_host_object",
    "parse",
    "pack_program",
    "run_runtime_replay",
]
