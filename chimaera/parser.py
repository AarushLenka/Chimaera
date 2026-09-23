"""Lexer and recursive-descent parser for the Phase 5 Chimaera DSL."""

from __future__ import annotations

from dataclasses import dataclass

from .ast import (
    Action,
    Contract,
    Duration,
    Event,
    Expr,
    Mutation,
    MutationEffect,
    Pin,
    Program,
    Protocol,
    SourceLocation,
    State,
    Timeout,
    Transition,
)
from .errors import ParseError


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    location: SourceLocation


_DOUBLE_SYMBOLS = ("->", "==", "!=", "<=", ">=", "&&", "||")
_SINGLE_SYMBOLS = set("{}(),%!<>")


def _lex(source: str) -> list[Token]:
    tokens: list[Token] = []
    index = 0
    line = 1
    column = 1
    while index < len(source):
        char = source[index]
        if char in " \t\r":
            index += 1
            column += 1
            continue
        if char == "\n":
            tokens.append(Token("EOL", "\n", SourceLocation(line, column)))
            index += 1
            line += 1
            column = 1
            continue
        if source.startswith("//", index):
            while index < len(source) and source[index] != "\n":
                index += 1
                column += 1
            continue
        location = SourceLocation(line, column)
        symbol = next(
            (candidate for candidate in _DOUBLE_SYMBOLS if source.startswith(candidate, index)),
            None,
        )
        if symbol is not None:
            tokens.append(Token("SYMBOL", symbol, location))
            index += 2
            column += 2
            continue
        if char in _SINGLE_SYMBOLS:
            tokens.append(Token("SYMBOL", char, location))
            index += 1
            column += 1
            continue
        if char.isdigit():
            start = index
            if source.startswith(("0x", "0X"), index):
                index += 2
                column += 2
                digit_start = index
                while index < len(source) and source[index] in "0123456789abcdefABCDEF_":
                    index += 1
                    column += 1
                if index == digit_start:
                    raise ParseError(f"{location.format()}: expected hexadecimal digits")
            else:
                while index < len(source) and (source[index].isdigit() or source[index] == "_"):
                    index += 1
                    column += 1
            tokens.append(Token("NUMBER", source[start:index], location))
            continue
        if char.isalpha() or char == "_":
            start = index
            while index < len(source) and (source[index].isalnum() or source[index] == "_"):
                index += 1
                column += 1
            tokens.append(Token("IDENT", source[start:index], location))
            continue
        raise ParseError(f"{location.format()}: unexpected character {char!r}")
    tokens.append(Token("EOF", "", SourceLocation(line, column)))
    return tokens


class _Parser:
    def __init__(self, source: str):
        self.tokens = _lex(source)
        self.index = 0

    @property
    def token(self) -> Token:
        return self.tokens[self.index]

    def advance(self) -> Token:
        token = self.token
        self.index += 1
        return token

    def skip_eol(self) -> None:
        while self.token.kind == "EOL":
            self.advance()

    def accept(self, value: str) -> Token | None:
        if self.token.value == value:
            return self.advance()
        return None

    def expect(self, value: str) -> Token:
        if self.token.value != value:
            self.fail(f"expected {value!r}, got {self.token.value!r}")
        return self.advance()

    def expect_kind(self, kind: str, description: str) -> Token:
        if self.token.kind != kind:
            self.fail(f"expected {description}, got {self.token.value!r}")
        return self.advance()

    def line_end(self) -> None:
        if self.token.kind not in {"EOL", "EOF"} and self.token.value != "}":
            self.fail(f"unexpected token {self.token.value!r} at end of statement")
        self.skip_eol()

    def fail(self, message: str) -> None:
        raise ParseError(f"{self.token.location.format()}: {message}")

    def parse(self) -> Program:
        program = Program()
        self.skip_eol()
        while self.token.kind != "EOF":
            if self.token.value == "protocol":
                program.protocols.append(self.parse_protocol())
            elif self.token.value == "mutation":
                program.mutations.append(self.parse_mutation())
            elif self.token.value == "contract":
                program.contracts.append(self.parse_contract())
            else:
                self.fail("expected 'protocol', 'mutation', or 'contract'")
            self.skip_eol()
        if not program.protocols:
            self.fail("a source file must contain at least one protocol")
        return program

    def parse_protocol(self) -> Protocol:
        keyword = self.expect("protocol")
        name = self.expect_kind("IDENT", "protocol name").value
        self.expect("{")
        protocol = Protocol(name, keyword.location)
        self.skip_eol()
        while self.token.value != "}":
            if self.token.kind == "EOF":
                self.fail("unterminated protocol block")
            if self.token.value == "pin":
                protocol.pins.append(self.parse_pin())
            elif self.token.value == "state":
                protocol.states.append(self.parse_state())
            else:
                self.fail("expected pin or state declaration")
            self.skip_eol()
        self.advance()
        return protocol

    def parse_pin(self) -> Pin:
        keyword = self.expect("pin")
        name = self.expect_kind("IDENT", "pin role name").value
        mode = self.expect_kind("IDENT", "pin mode").value
        self.line_end()
        return Pin(name, mode, keyword.location)

    def parse_state(self) -> State:
        keyword = self.expect("state")
        name = self.expect_kind("IDENT", "state name").value
        self.expect("{")
        state = State(name, keyword.location)
        self.skip_eol()
        while self.token.value != "}":
            if self.token.kind == "EOF":
                self.fail("unterminated state block")
            if self.token.value == "on":
                self.parse_on(state)
            elif self.token.value in {"sample", "count", "reset", "drive", "release", "goto"}:
                item = self.parse_action_or_goto()
                if isinstance(item, Action):
                    state.actions.append(item)
                else:
                    state.transitions.append(item)
            elif self.token.value == "when":
                state.transitions.append(self.parse_transition())
            elif self.token.value == "within":
                if state.timeout is not None:
                    self.fail("a state may contain only one timeout")
                state.timeout = self.parse_timeout()
            else:
                self.fail("expected event, action, transition, or timeout")
            self.skip_eol()
        self.advance()
        return state

    def parse_on(self, state: State) -> None:
        if state.event is not None:
            self.fail("a reaction-cell state may contain only one event")
        self.expect("on")
        state.event = self.parse_event()
        if self.accept("when") is not None:
            state.event_guard = self.parse_expression(stop_values={"->", "{"}, stop_at_eol=True)
        if self.accept("->") is not None:
            state.event_target = self.expect_kind("IDENT", "successor state").value
            self.line_end()
            return
        self.expect("{")
        self.skip_eol()
        while self.token.value != "}":
            if self.token.kind == "EOF":
                self.fail("unterminated event action block")
            item = self.parse_action_or_goto()
            if isinstance(item, Action):
                state.actions.append(item)
            else:
                state.transitions.append(item)
            self.skip_eol()
        self.advance()
        self.line_end()

    def parse_event(self) -> Event:
        kind_token = self.expect_kind("IDENT", "event kind")
        kind = kind_token.value
        if kind not in {"rise", "fall", "level"}:
            self.fail(f"unsupported event kind {kind!r}")
        self.expect("(")
        pin = self.expect_kind("IDENT", "event pin").value
        value: int | None = None
        if kind == "level":
            self.expect(",")
            value = self.parse_number()
            if value not in {0, 1}:
                self.fail("level event value must be 0 or 1")
        self.expect(")")
        return Event(kind, pin, value, kind_token.location)

    def parse_action_or_goto(self) -> Action | Transition:
        keyword = self.advance()
        if keyword.value == "sample":
            pin = self.expect_kind("IDENT", "sample pin").value
            self.expect("into")
            variable = self.expect_kind("IDENT", "sample variable").value
            self.line_end()
            return Action("sample", keyword.location, pin=pin, variable=variable)
        if keyword.value == "count":
            variable = self.expect_kind("IDENT", "counter name").value
            self.line_end()
            return Action("count", keyword.location, variable=variable)
        if keyword.value == "reset":
            variable = self.expect_kind("IDENT", "variable name").value
            self.line_end()
            return Action("reset", keyword.location, variable=variable)
        if keyword.value == "drive":
            pin = self.expect_kind("IDENT", "drive pin").value
            value = self.expect_kind("IDENT", "drive value").value
            if value not in {"low", "high", "release"}:
                self.fail("drive value must be low, high, or release")
            self.line_end()
            if value == "release":
                return Action("release", keyword.location, pin=pin, value=value)
            return Action("drive", keyword.location, pin=pin, value=value)
        if keyword.value == "release":
            pin = self.expect_kind("IDENT", "release pin").value
            self.line_end()
            return Action("release", keyword.location, pin=pin, value="release")
        if keyword.value == "goto":
            target = self.expect_kind("IDENT", "successor state").value
            self.line_end()
            return Transition(target, keyword.location)
        self.fail(f"unsupported action {keyword.value!r}")

    def parse_transition(self) -> Transition:
        keyword = self.expect("when")
        condition = self.parse_expression(stop_values={"->"}, stop_at_eol=True)
        self.expect("->")
        target = self.expect_kind("IDENT", "successor state").value
        self.line_end()
        return Transition(target, keyword.location, condition)

    def parse_timeout(self) -> Timeout:
        keyword = self.expect("within")
        duration = self.parse_duration()
        self.expect("else")
        self.expect("->")
        target = self.expect_kind("IDENT", "timeout successor state").value
        self.line_end()
        return Timeout(duration, target, keyword.location)

    def parse_duration(self) -> Duration:
        token = self.expect_kind("NUMBER", "duration value")
        value = int(token.value.replace("_", ""), 0)
        unit = self.expect_kind("IDENT", "duration unit").value
        if unit not in {"cycle", "cycles", "ns", "us"}:
            self.fail("duration unit must be cycles, ns, or us")
        return Duration(value, unit, token.location)

    def parse_mutation(self) -> Mutation:
        keyword = self.expect("mutation")
        name = self.expect_kind("IDENT", "mutation name").value
        self.expect("for")
        protocol = self.expect_kind("IDENT", "protocol name").value
        self.expect("{")
        self.skip_eol()
        self.expect("when")
        condition = self.parse_expression(stop_values=set(), stop_at_eol=True)
        self.line_end()
        effect = self.parse_mutation_effect()
        self.skip_eol()
        self.expect("}")
        return Mutation(name, protocol, condition, effect, keyword.location)

    def parse_mutation_effect(self) -> MutationEffect:
        token = self.token
        if self.accept("delay") is not None:
            self.expect("next")
            self.expect("action")
            self.expect("by")
            amount = self.parse_number()
            self.expect("cycles")
            self.line_end()
            return MutationEffect("delay", token.location, amount=amount)
        if self.accept("nack") is not None:
            self.line_end()
            return MutationEffect("nack", token.location)
        if self.accept("drop") is not None:
            self.expect("byte")
            self.line_end()
            return MutationEffect("drop_byte", token.location)
        if self.accept("flip") is not None:
            self.expect("bits")
            mask = self.parse_number()
            self.expect("in")
            variable = self.expect_kind("IDENT", "variable name").value
            self.line_end()
            return MutationEffect("flip_bits", token.location, variable=variable, mask=mask)
        if self.accept("hold") is not None:
            pin = self.expect_kind("IDENT", "pin name").value
            self.expect("low")
            self.expect("for")
            amount = self.parse_number()
            self.expect("cycles")
            self.line_end()
            return MutationEffect("hold_low", token.location, pin=pin, amount=amount)
        if self.accept("duplicate") is not None:
            self.expect("edge")
            self.expect("on")
            pin = self.expect_kind("IDENT", "pin name").value
            self.line_end()
            return MutationEffect("duplicate_edge", token.location, pin=pin)
        if self.accept("release") is not None:
            pin = self.expect_kind("IDENT", "pin name").value
            self.expect("after")
            amount = self.parse_number()
            self.expect("extra")
            self.expect("cycles")
            self.line_end()
            return MutationEffect("late_release", token.location, pin=pin, amount=amount)
        self.fail("unsupported mutation effect")

    def parse_contract(self) -> Contract:
        keyword = self.expect("contract")
        name = self.expect_kind("IDENT", "contract name").value
        self.expect("for")
        protocol = self.expect_kind("IDENT", "protocol name").value
        self.expect("{")
        self.skip_eol()
        assertions: list[str] = []
        while self.token.value != "}":
            self.expect("assert")
            parts: list[str] = []
            while self.token.kind not in {"EOL", "EOF"} and self.token.value != "}":
                parts.append(self.advance().value)
            if not parts:
                self.fail("empty contract assertion")
            self.line_end()
            while self.token.value == "except":
                while self.token.kind not in {"EOL", "EOF"} and self.token.value != "}":
                    parts.append(self.advance().value)
                self.line_end()
            assertions.append(" ".join(parts))
        self.advance()
        return Contract(name, protocol, tuple(assertions), keyword.location)

    def parse_number(self) -> int:
        token = self.expect_kind("NUMBER", "integer")
        return int(token.value.replace("_", ""), 0)

    def parse_expression(self, stop_values: set[str], stop_at_eol: bool) -> Expr:
        start = self.index
        end = start
        depth = 0
        while True:
            token = self.tokens[end]
            if token.kind == "EOF":
                break
            if stop_at_eol and token.kind == "EOL" and depth == 0:
                break
            if token.value in stop_values and depth == 0:
                break
            if token.value == "(":
                depth += 1
            elif token.value == ")":
                if depth == 0:
                    break
                depth -= 1
            end += 1
        if end == start:
            self.fail("expected expression")
        expression_tokens = self.tokens[start:end] + [Token("EOF", "", self.tokens[end].location)]
        expression = _ExpressionParser(expression_tokens).parse()
        self.index = end
        return expression


class _ExpressionParser:
    _PRECEDENCE = {"||": 1, "&&": 2, "==": 3, "!=": 3, "<": 4, "<=": 4, ">": 4, ">=": 4, "%": 5}

    def __init__(self, tokens: list[Token]):
        self.tokens = tokens
        self.index = 0

    @property
    def token(self) -> Token:
        return self.tokens[self.index]

    def parse(self) -> Expr:
        expression = self.parse_binary(1)
        if self.token.kind != "EOF":
            self.fail(f"unexpected token {self.token.value!r} in expression")
        return expression

    def parse_binary(self, minimum: int) -> Expr:
        left = self.parse_unary()
        while self.token.value in self._PRECEDENCE and self._PRECEDENCE[self.token.value] >= minimum:
            operator = self.token.value
            precedence = self._PRECEDENCE[operator]
            self.index += 1
            right = self.parse_binary(precedence + 1)
            left = Expr("binary", operator, left, right)
        return left

    def parse_unary(self) -> Expr:
        if self.token.value == "!":
            self.index += 1
            return Expr("unary", "!", left=self.parse_unary())
        if self.token.value == "(":
            self.index += 1
            expression = self.parse_binary(1)
            if self.token.value != ")":
                self.fail("expected ')' in expression")
            self.index += 1
            return expression
        if self.token.kind == "NUMBER":
            token = self.token
            self.index += 1
            return Expr("number", int(token.value.replace("_", ""), 0))
        if self.token.kind == "IDENT":
            token = self.token
            self.index += 1
            if token.value in {"true", "false"}:
                return Expr("number", 1 if token.value == "true" else 0)
            return Expr("name", token.value)
        self.fail("expected value in expression")

    def fail(self, message: str) -> None:
        raise ParseError(f"{self.token.location.format()}: {message}")


def parse(source: str) -> Program:
    """Parse *source* into a typed :class:`Program`."""

    return _Parser(source).parse()
