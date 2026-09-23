"""Typed abstract syntax tree for the Chimaera DSL."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class SourceLocation:
    line: int
    column: int

    def format(self) -> str:
        return f"{self.line}:{self.column}"


@dataclass(frozen=True)
class Expr:
    kind: str
    value: Any = None
    left: Expr | None = None
    right: Expr | None = None

    def names(self) -> set[str]:
        if self.kind == "name":
            return {str(self.value)}
        names: set[str] = set()
        if self.left is not None:
            names.update(self.left.names())
        if self.right is not None:
            names.update(self.right.names())
        return names

    def to_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {"kind": self.kind}
        if self.value is not None:
            result["value"] = self.value
        if self.left is not None:
            result["left"] = self.left.to_dict()
        if self.right is not None:
            result["right"] = self.right.to_dict()
        return result


@dataclass(frozen=True)
class Duration:
    value: int
    unit: str
    location: SourceLocation


@dataclass(frozen=True)
class Pin:
    name: str
    mode: str
    location: SourceLocation


@dataclass(frozen=True)
class Event:
    kind: str
    pin: str | None
    value: int | None
    location: SourceLocation


@dataclass(frozen=True)
class Action:
    kind: str
    location: SourceLocation
    pin: str | None = None
    value: str | None = None
    variable: str | None = None


@dataclass(frozen=True)
class Transition:
    target: str
    location: SourceLocation
    condition: Expr | None = None


@dataclass(frozen=True)
class Timeout:
    duration: Duration
    target: str
    location: SourceLocation


@dataclass
class State:
    name: str
    location: SourceLocation
    event: Event | None = None
    event_guard: Expr | None = None
    event_target: str | None = None
    actions: list[Action] = field(default_factory=list)
    transitions: list[Transition] = field(default_factory=list)
    timeout: Timeout | None = None


@dataclass
class Protocol:
    name: str
    location: SourceLocation
    pins: list[Pin] = field(default_factory=list)
    states: list[State] = field(default_factory=list)


@dataclass(frozen=True)
class MutationEffect:
    kind: str
    location: SourceLocation
    amount: int | None = None
    pin: str | None = None
    variable: str | None = None
    mask: int | None = None


@dataclass(frozen=True)
class Mutation:
    name: str
    protocol: str
    condition: Expr
    effect: MutationEffect
    location: SourceLocation


@dataclass(frozen=True)
class Contract:
    name: str
    protocol: str
    assertions: tuple[str, ...]
    location: SourceLocation


@dataclass
class Program:
    protocols: list[Protocol] = field(default_factory=list)
    mutations: list[Mutation] = field(default_factory=list)
    contracts: list[Contract] = field(default_factory=list)
