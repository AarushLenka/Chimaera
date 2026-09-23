"""Errors reported by the Chimaera host toolchain."""


class ChimaeraError(Exception):
    """Base class for a user-facing toolchain error."""


class ParseError(ChimaeraError):
    """The DSL source is not syntactically valid."""


class CompileError(ChimaeraError):
    """The DSL program failed a static proof obligation."""
