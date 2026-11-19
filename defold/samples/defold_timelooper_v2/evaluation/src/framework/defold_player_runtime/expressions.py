"""Small, safe assertion language over public Dashboard snapshots.

The parser deliberately implements a strict subset of the draft checkpoint format.  It never
uses Python ``eval`` and has no registration hook for per-game helper functions.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Iterable


class ExpressionError(ValueError):
    pass


class ExpressionEvaluationError(RuntimeError):
    pass


@dataclass(frozen=True)
class SavedSnapshot:
    snapshot: dict[str, Any]
    monotonic_s: float


@dataclass(frozen=True)
class EvaluationContext:
    current: dict[str, Any]
    saved: dict[str, SavedSnapshot]
    monotonic_s: float
    captures: dict[str, dict[str, Any]] | None = None
    current_capture: str | None = None
    process_exited: bool = False
    process_exit_code: int | None = None
    selected_target: dict[str, Any] | None = None


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    offset: int


TOKEN_RE = re.compile(
    r"\s*(?:"
    r"(?P<number>(?:\d+\.\d+|\d+))|"
    r'(?P<string>"(?:\\.|[^"\\])*")|'
    r"(?P<operator>==|!=|<=|>=|&&|\|\||[<>!+\-(),.\[\]=])|"
    r"(?P<identifier>[A-Za-z_][A-Za-z0-9_-]*)"
    r")"
)

GENERIC_FUNCTION_ARITY = {
    "approx": 3,
    "approx_vec3": 3,
    "distance_xz": 2,
    "surface_distance_xz": 2,
    "aabb_overlap_xz": 2,
    "distance_cells": 2,
    "distance_from": 2,
    "same_entities": 2,
    "cells_within_manhattan": 3,
}


def tokenize(text: str) -> list[Token]:
    result: list[Token] = []
    offset = 0
    while offset < len(text):
        if not text[offset:].strip():
            break
        match = TOKEN_RE.match(text, offset)
        if not match:
            raise ExpressionError(f"unsupported token at offset {offset}: {text[offset:offset + 16]!r}")
        kind = next(name for name, value in match.groupdict().items() if value is not None)
        result.append(Token(kind, match.group(kind), offset))
        offset = match.end()
    result.append(Token("eof", "", len(text)))
    return result


Node = tuple[Any, ...]


class Parser:
    def __init__(self, text: str):
        self.text = text
        self.tokens = tokenize(text)
        self.index = 0

    @property
    def token(self) -> Token:
        return self.tokens[self.index]

    def take(self, value: str | None = None, kind: str | None = None) -> Token:
        token = self.token
        if value is not None and token.value != value:
            raise ExpressionError(f"expected {value!r} at offset {token.offset}")
        if kind is not None and token.kind != kind:
            raise ExpressionError(f"expected {kind} at offset {token.offset}")
        self.index += 1
        return token

    def accept(self, value: str) -> bool:
        if self.token.value != value:
            return False
        self.index += 1
        return True

    def parse(self) -> Node:
        node = self.parse_or()
        if self.token.kind != "eof":
            raise ExpressionError(
                f"unexpected token {self.token.value!r} at offset {self.token.offset}"
            )
        return node

    def parse_or(self) -> Node:
        node = self.parse_and()
        while self.accept("||"):
            node = ("binary", "||", node, self.parse_and())
        return node

    def parse_and(self) -> Node:
        node = self.parse_unary()
        while self.accept("&&"):
            node = ("binary", "&&", node, self.parse_unary())
        return node

    def parse_unary(self) -> Node:
        if self.accept("!"):
            return ("unary", "!", self.parse_unary())
        if self.accept("-"):
            return ("unary", "-", self.parse_unary())
        return self.parse_comparison()

    def parse_comparison(self) -> Node:
        node = self.parse_additive()
        if self.token.value in {"==", "!=", "<", "<=", ">", ">="}:
            operator = self.take().value
            node = ("binary", operator, node, self.parse_additive())
        return node

    def parse_additive(self) -> Node:
        node = self.parse_primary()
        while self.token.value in {"+", "-"}:
            operator = self.take().value
            node = ("binary", operator, node, self.parse_primary())
        return node

    def parse_primary(self) -> Node:
        token = self.token
        if token.kind == "number":
            self.take()
            value: int | float = float(token.value) if "." in token.value else int(token.value)
            return ("literal", value)
        if token.kind == "string":
            self.take()
            return ("literal", json.loads(token.value))
        if self.accept("["):
            items: list[Node] = []
            if not self.accept("]"):
                while True:
                    items.append(self.parse_or())
                    if self.accept("]"):
                        break
                    self.take(",")
            return self.parse_postfix(("list", items))
        if self.accept("("):
            node = self.parse_or()
            self.take(")")
            return self.parse_postfix(node)
        if token.kind != "identifier":
            raise ExpressionError(f"expected a value at offset {token.offset}")

        name = self.take(kind="identifier").value
        if name == "true":
            return ("literal", True)
        if name == "false":
            return ("literal", False)
        if name == "null":
            return ("literal", None)
        if self.token.value == "(":
            if name == "wall_clock_since":
                self.take("(")
                label = self.take(kind="identifier").value
                self.take(")")
                return self.parse_postfix(("wall_clock_since", label))
            if name in {"entity", "target", "exists", "exists_target", "count"}:
                return self.parse_postfix(self.parse_selector_call(name, ("current_snapshot",)))
            if name in {
                "capture_nonblank",
                "ocr_line_count",
                "ocr_contains",
                "ocr_contains_any",
                "ocr_absent",
                "ocr_numeric_values_match",
            }:
                return self.parse_postfix(self.parse_capture_call(name))
            if name in GENERIC_FUNCTION_ARITY:
                return self.parse_postfix(self.parse_generic_call(name))
            raise ExpressionError(f"unsupported function {name!r}")

        if name in {"phase", "revision", "slots", "entities", "targets"}:
            node: Node = ("get", ("current_snapshot",), name)
        elif name in {"process_exited", "process_exit_code", "selected_target"}:
            node = ("runtime_field", name)
        elif self.token.value == ".":
            node = ("saved_snapshot", name)
        else:
            node = ("literal", name)
        return self.parse_postfix(node)

    def parse_postfix(self, node: Node) -> Node:
        while True:
            if self.accept("."):
                name = self.take(kind="identifier").value
                if self.token.value == "(":
                    if name not in {"entity", "target", "exists", "exists_target", "count"}:
                        raise ExpressionError(f"unsupported member function {name!r}")
                    node = self.parse_selector_call(name, node)
                else:
                    node = ("get", node, name)
            elif self.accept("["):
                index = self.take(kind="number").value
                if "." in index:
                    raise ExpressionError("array index must be an integer")
                self.take("]")
                node = ("index", node, int(index))
            else:
                return node

    def parse_selector_call(self, name: str, snapshot_node: Node) -> Node:
        self.take("(")
        selector: dict[str, str] = {}
        if not self.accept(")"):
            first = self.take(kind="identifier").value
            if self.accept("="):
                selector[first] = self.take(kind="identifier").value
            else:
                selector["kind"] = first
            while self.accept(","):
                key = self.take(kind="identifier").value
                self.take("=")
                selector[key] = self.take(kind="identifier").value
            self.take(")")
        if set(selector) - {"kind", "state"} or "kind" not in selector:
            raise ExpressionError(f"{name} selector requires kind and optional state")
        return ("selector", name, snapshot_node, selector)

    def parse_capture_call(self, name: str) -> Node:
        self.take("(")
        arguments: list[Node] = []
        if not self.accept(")"):
            while True:
                arguments.append(self.parse_or())
                if self.accept(")"):
                    break
                self.take(",")
        expected_counts = {
            "capture_nonblank": {0, 1},
            "ocr_line_count": {0, 1},
            "ocr_contains": {1, 2},
            "ocr_contains_any": {1, 2},
            "ocr_absent": {1, 2},
            "ocr_numeric_values_match": {1, 2},
        }
        if len(arguments) not in expected_counts[name]:
            allowed = sorted(expected_counts[name])
            raise ExpressionError(f"{name} expects argument count in {allowed}")
        return ("capture_function", name, arguments)

    def parse_generic_call(self, name: str) -> Node:
        self.take("(")
        arguments: list[Node] = []
        if not self.accept(")"):
            while True:
                arguments.append(self.parse_or())
                if self.accept(")"):
                    break
                self.take(",")
        expected = GENERIC_FUNCTION_ARITY[name]
        if len(arguments) != expected:
            raise ExpressionError(f"{name} expects {expected} arguments")
        if name == "same_entities" and arguments[0][0] == "literal":
            label = arguments[0][1]
            if isinstance(label, str) and label and label[0].isupper():
                arguments[0] = ("saved_snapshot", label)
        return ("generic_function", name, arguments)


def compile_expression(text: str) -> Node:
    if not isinstance(text, str) or not text.strip():
        raise ExpressionError("expression must be a non-empty string")
    return Parser(text).parse()


def snapshot_labels(node: Node) -> set[str]:
    result: set[str] = set()

    def visit(value: Any) -> None:
        if not isinstance(value, tuple):
            if isinstance(value, list):
                for item in value:
                    visit(item)
            return
        if value[0] in {"saved_snapshot", "wall_clock_since"}:
            result.add(value[1])
        for item in value[1:]:
            visit(item)

    visit(node)
    return result


def selector_specs(node: Node) -> list[tuple[str, dict[str, str]]]:
    result: list[tuple[str, dict[str, str]]] = []

    def visit(value: Any) -> None:
        if not isinstance(value, tuple):
            if isinstance(value, list):
                for item in value:
                    visit(item)
            return
        if value[0] == "selector":
            result.append((value[1], dict(value[3])))
        for item in value[1:]:
            visit(item)

    visit(node)
    return result


def _snapshot(value: Any) -> dict[str, Any]:
    if isinstance(value, SavedSnapshot):
        return value.snapshot
    if isinstance(value, dict):
        return value
    raise ExpressionEvaluationError(f"expected a Dashboard snapshot, got {type(value).__name__}")


def _selector_matches(snapshot: dict[str, Any], collection: str, selector: dict[str, str]) -> list[dict[str, Any]]:
    return [
        item
        for item in snapshot.get(collection, [])
        if item.get("kind") == selector["kind"]
        and ("state" not in selector or item.get("state") == selector["state"])
    ]


def _normalize_text(value: Any) -> str:
    return re.sub(r"\s+", "", str(value)).casefold()


def _capture(context: EvaluationContext, label: Any | None = None) -> dict[str, Any]:
    captures = context.captures or {}
    selected = context.current_capture if label is None else str(label)
    if selected is None or selected not in captures:
        raise ExpressionEvaluationError(f"capture {selected!r} is unavailable")
    return captures[selected]


def _capture_arguments(node: Node, context: EvaluationContext) -> tuple[dict[str, Any], list[Any]]:
    name = node[1]
    arguments = [evaluate(argument, context) for argument in node[2]]
    label: Any | None = None
    if name in {"capture_nonblank", "ocr_line_count"}:
        if arguments:
            label = arguments.pop(0)
    elif len(arguments) == 2:
        label = arguments.pop(0)
    return _capture(context, label), arguments


def _ocr(capture: dict[str, Any]) -> dict[str, Any]:
    value = capture.get("ocr")
    if not isinstance(value, dict):
        raise ExpressionEvaluationError("capture has no OCR result")
    return value


def _numeric_tokens(ocr: dict[str, Any]) -> list[float]:
    text = " ".join(str(line) for line in ocr.get("lines", []))
    return [float(value) for value in re.findall(r"(?<![A-Za-z])[-+]?\d+(?:\.\d+)?", text)]


def _numeric_slot_matches(slot_value: Any, tokens: list[float]) -> bool:
    if isinstance(slot_value, bool) or not isinstance(slot_value, (int, float)):
        return False
    value = float(slot_value)
    candidates = {value, float(round(value)), float(int(value))}
    tolerance = max(0.05, abs(value) * 0.002)
    return any(abs(token - candidate) <= tolerance for token in tokens for candidate in candidates)


def _position(value: Any) -> list[float]:
    if isinstance(value, dict):
        value = value.get("position")
    if not isinstance(value, list) or len(value) < 2:
        raise ExpressionEvaluationError("expected position geometry")
    return [float(item) for item in value]


def _cell_value(value: Any) -> list[float]:
    if isinstance(value, dict):
        value = value.get("cell")
    if not isinstance(value, list) or len(value) != 2:
        raise ExpressionEvaluationError("expected cell geometry")
    return [float(item) for item in value]


def _size(value: Any, dimensions: int) -> list[float]:
    raw = value.get("size") if isinstance(value, dict) else None
    if not isinstance(raw, list) or len(raw) < dimensions:
        return [0.0] * dimensions
    return [float(item) for item in raw]


def evaluate(node: Node, context: EvaluationContext) -> Any:
    kind = node[0]
    if kind == "literal":
        return node[1]
    if kind == "list":
        return [evaluate(item, context) for item in node[1]]
    if kind == "current_snapshot":
        return context.current
    if kind == "runtime_field":
        return getattr(context, node[1])
    if kind == "saved_snapshot":
        try:
            return context.saved[node[1]]
        except KeyError as exc:
            raise ExpressionEvaluationError(f"unknown saved snapshot {node[1]!r}") from exc
    if kind == "wall_clock_since":
        try:
            return context.monotonic_s - context.saved[node[1]].monotonic_s
        except KeyError as exc:
            raise ExpressionEvaluationError(f"unknown saved snapshot {node[1]!r}") from exc
    if kind == "get":
        value = evaluate(node[1], context)
        if isinstance(value, SavedSnapshot):
            value = value.snapshot
        if isinstance(value, list) and node[2] in {"x", "y", "z", "w"}:
            index = {"x": 0, "y": 1, "z": 2, "w": 3}[node[2]]
            if index >= len(value):
                raise ExpressionEvaluationError(f"coordinate {node[2]!r} is unavailable")
            return value[index]
        if not isinstance(value, dict) or node[2] not in value:
            raise ExpressionEvaluationError(f"field {node[2]!r} is unavailable")
        return value[node[2]]
    if kind == "index":
        value = evaluate(node[1], context)
        if not isinstance(value, list) or not 0 <= node[2] < len(value):
            raise ExpressionEvaluationError(f"index {node[2]} is unavailable")
        return value[node[2]]
    if kind == "selector":
        name, snapshot_node, selector = node[1], node[2], node[3]
        snapshot = _snapshot(evaluate(snapshot_node, context))
        collection = "targets" if name in {"target", "exists_target"} else "entities"
        matches = _selector_matches(snapshot, collection, selector)
        if name in {"exists", "exists_target"}:
            return bool(matches)
        if name == "count":
            return len(matches)
        if len(matches) != 1:
            raise ExpressionEvaluationError(
                f"{name} selector {selector!r} matched {len(matches)} items, expected exactly one"
            )
        return matches[0]
    if kind == "capture_function":
        name = node[1]
        capture, arguments = _capture_arguments(node, context)
        if name == "capture_nonblank":
            return int(capture.get("byte_size", 0)) >= 4096
        ocr = _ocr(capture)
        if name == "ocr_line_count":
            return len(ocr.get("lines", []))
        if name == "ocr_contains":
            return _normalize_text(arguments[0]) in str(ocr.get("normalized", ""))
        if name in {"ocr_contains_any", "ocr_absent"}:
            alternatives = arguments[0]
            if not isinstance(alternatives, list):
                raise ExpressionEvaluationError(f"{name} requires a list")
            normalized = str(ocr.get("normalized", ""))
            found = any(_normalize_text(value) in normalized for value in alternatives)
            return found if name == "ocr_contains_any" else not found
        if name == "ocr_numeric_values_match":
            slots = arguments[0]
            if not isinstance(slots, list) or not all(isinstance(slot, str) for slot in slots):
                raise ExpressionEvaluationError("ocr_numeric_values_match requires slot-name strings")
            tokens = _numeric_tokens(ocr)
            return all(
                slot in context.current.get("slots", {})
                and _numeric_slot_matches(context.current["slots"][slot], tokens)
                for slot in slots
            )
        raise ExpressionEvaluationError(f"unsupported capture function {name!r}")
    if kind == "generic_function":
        name = node[1]
        arguments = [evaluate(argument, context) for argument in node[2]]
        if name == "approx":
            value, expected, tolerance = arguments
            if any(isinstance(item, bool) or not isinstance(item, (int, float)) for item in arguments):
                raise ExpressionEvaluationError("approx requires numeric arguments")
            return abs(float(value) - float(expected)) <= float(tolerance)
        if name == "approx_vec3":
            first, second, tolerance = arguments
            if not isinstance(first, list) or not isinstance(second, list):
                raise ExpressionEvaluationError("approx_vec3 requires vectors")
            if len(first) != len(second) or len(first) < 2:
                return False
            return all(abs(float(a) - float(b)) <= float(tolerance) for a, b in zip(first, second))
        if name in {"distance_xz", "surface_distance_xz", "aabb_overlap_xz"}:
            first, second = arguments
            first_position = _position(first)
            second_position = _position(second)
            axes = [0, 2] if len(first_position) > 2 and len(second_position) > 2 else [0, 1]
            gaps = [abs(first_position[index] - second_position[index]) for index in axes]
            if name == "distance_xz":
                return sum(gap * gap for gap in gaps) ** 0.5
            first_size = _size(first, max(axes) + 1)
            second_size = _size(second, max(axes) + 1)
            surface_gaps = [
                max(0.0, gap - (first_size[index] + second_size[index]) / 2)
                for gap, index in zip(gaps, axes)
            ]
            if name == "surface_distance_xz":
                return sum(gap * gap for gap in surface_gaps) ** 0.5
            return all(gap <= 0 for gap in surface_gaps)
        if name == "distance_cells":
            first = _cell_value(arguments[0])
            second = _cell_value(arguments[1])
            return abs(first[0] - second[0]) + abs(first[1] - second[1])
        if name == "distance_from":
            first = _position(arguments[0])
            second = _position(arguments[1])
            count = min(len(first), len(second))
            return sum((first[index] - second[index]) ** 2 for index in range(count)) ** 0.5
        if name == "same_entities":
            saved_snapshot = _snapshot(arguments[0])
            entity_kind = str(arguments[1])
            current_entities = sorted(
                (item for item in context.current.get("entities", []) if item.get("kind") == entity_kind),
                key=lambda item: str(item.get("id", "")),
            )
            saved_entities = sorted(
                (item for item in saved_snapshot.get("entities", []) if item.get("kind") == entity_kind),
                key=lambda item: str(item.get("id", "")),
            )
            return current_entities == saved_entities
        if name == "cells_within_manhattan":
            origin = _cell_value(arguments[0])
            entity_kind = str(arguments[1])
            radius = float(arguments[2])
            matches = [
                item for item in context.current.get("entities", [])
                if item.get("kind") == entity_kind
            ]
            return bool(matches) and all(
                abs(_cell_value(item)[0] - origin[0]) + abs(_cell_value(item)[1] - origin[1]) <= radius
                for item in matches
            )
        raise ExpressionEvaluationError(f"unsupported generic function {name!r}")
    if kind == "unary":
        value = evaluate(node[2], context)
        if node[1] == "!":
            return not bool(value)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ExpressionEvaluationError("unary - requires a numeric operand")
        return -value
    if kind == "binary":
        operator = node[1]
        if operator == "&&":
            return bool(evaluate(node[2], context)) and bool(evaluate(node[3], context))
        if operator == "||":
            return bool(evaluate(node[2], context)) or bool(evaluate(node[3], context))
        left = evaluate(node[2], context)
        right = evaluate(node[3], context)
        if operator == "==":
            return left == right
        if operator == "!=":
            return left != right
        if operator in {"+", "-"}:
            if isinstance(left, bool) or isinstance(right, bool) or not isinstance(left, (int, float)) or not isinstance(right, (int, float)):
                raise ExpressionEvaluationError(f"{operator} requires numeric operands")
            return left + right if operator == "+" else left - right
        try:
            if operator == "<":
                return left < right
            if operator == "<=":
                return left <= right
            if operator == ">":
                return left > right
            if operator == ">=":
                return left >= right
        except TypeError as exc:
            raise ExpressionEvaluationError(f"cannot compare {left!r} and {right!r}") from exc
    raise ExpressionEvaluationError(f"unknown expression node {kind!r}")


def assert_true(expression: str | Node, context: EvaluationContext) -> bool:
    node = compile_expression(expression) if isinstance(expression, str) else expression
    return bool(evaluate(node, context))


def compile_all(expressions: Iterable[str]) -> list[Node]:
    return [compile_expression(expression) for expression in expressions]
