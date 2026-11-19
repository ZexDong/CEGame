#!/usr/bin/env python3
"""Validate a Defold Dashboard JSONL trace against task naming tables."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, NoReturn


PHASES = {"not_ready", "menu", "playing", "paused", "won", "lost"}
TOP_KEYS = {"revision", "phase", "slots", "entities", "targets"}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"dashboard self-check failed: {message}")


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {path}: {exc}")


def is_number(value: Any) -> bool:
    return not isinstance(value, bool) and isinstance(value, (int, float))


def validate_rect(rect: Any, context: str, tables: dict[str, Any]) -> None:
    if not isinstance(rect, list) or len(rect) != 4 or not all(is_number(v) for v in rect):
        fail(f"{context} rect must be [x, y, width, height]")
    if rect[2] < 0 or rect[3] < 0:
        fail(f"{context} rect width and height must be non-negative")
    space = tables.get("target_rect_space", {})
    width = space.get("width")
    height = space.get("height")
    if width is not None and (rect[0] < 0 or rect[0] + rect[2] > width):
        fail(f"{context} rect is outside the game-view width")
    if height is not None and (rect[1] < 0 or rect[1] + rect[3] > height):
        fail(f"{context} rect is outside the game-view height")


def validate_cell(cell: Any, context: str, tables: dict[str, Any]) -> None:
    if not isinstance(cell, list) or len(cell) not in {2, 3}:
        fail(f"{context} cell must contain two or three integers")
    if not all(isinstance(value, int) and not isinstance(value, bool) for value in cell):
        fail(f"{context} cell must contain only integers")

    width = tables.get("level_width_cells")
    height = tables.get("level_height_cells")
    if width is not None and not 0 <= cell[0] < int(width):
        fail(f"{context} cell x is outside the task grid")
    if height is not None and not 0 <= cell[1] < int(height):
        fail(f"{context} cell y is outside the task grid")


def validate_vector(vector: Any, context: str) -> None:
    if not isinstance(vector, list) or len(vector) not in {2, 3}:
        fail(f"{context} must contain two or three numbers")
    if not all(is_number(value) for value in vector):
        fail(f"{context} must contain only numbers")


def validate_naming_tables(tables: Any) -> dict[str, Any]:
    if not isinstance(tables, dict) or tables.get("schema_version") != 2:
        fail("naming tables must use schema_version 2")
    for key in ("task_id", "coordinate_space", "target_rect_space", "slots", "entities", "targets", "controls"):
        if key not in tables:
            fail(f"naming tables are missing {key!r}")
    space = tables["coordinate_space"]
    if not isinstance(space, dict) or not {"name", "dimensions", "origin", "axes", "units"} <= set(space):
        fail("coordinate_space is incomplete")
    if space["dimensions"] not in {2, 3} or len(space["axes"]) != space["dimensions"]:
        fail("coordinate_space axes must match its two or three dimensions")
    target_space = tables["target_rect_space"]
    if (
        not isinstance(target_space, dict)
        or target_space.get("origin") != "bottom-left"
        or target_space.get("units") != "game-view pixels"
        or not is_number(target_space.get("width"))
        or not is_number(target_space.get("height"))
        or target_space["width"] <= 0
        or target_space["height"] <= 0
    ):
        fail("target_rect_space must define a positive bottom-left game-view pixel space")
    entity_kinds = [item.get("kind") for item in tables["entities"] if isinstance(item, dict)]
    target_kinds = [item.get("kind") for item in tables["targets"] if isinstance(item, dict)]
    if len(entity_kinds) != len(tables["entities"]) or len(set(entity_kinds)) != len(entity_kinds):
        fail("entity kinds must be complete and unique")
    if len(target_kinds) != len(tables["targets"]) or len(set(target_kinds)) != len(target_kinds):
        fail("target kinds must be complete and unique")
    for item in tables["entities"]:
        if item.get("geometry") not in {"cell", "position", "rect", "none"}:
            fail(f"entity kind {item.get('kind')!r} has invalid geometry")
        states = item.get("states")
        if not isinstance(states, list) or not states or len(set(states)) != len(states):
            fail(f"entity kind {item.get('kind')!r} must define unique states")
    return tables


def validate_snapshot(
    snapshot: Any,
    line_number: int,
    previous_revision: int,
    tables: dict[str, Any],
) -> int:
    context = f"line {line_number}"
    if not isinstance(snapshot, dict) or set(snapshot) != TOP_KEYS:
        fail(f"{context} top-level keys must be exactly {sorted(TOP_KEYS)}")

    revision = snapshot["revision"]
    if not isinstance(revision, int) or isinstance(revision, bool) or revision <= previous_revision:
        fail(f"{context} revision must be an integer that strictly increases")
    if snapshot["phase"] not in PHASES:
        fail(f"{context} has invalid phase {snapshot['phase']!r}")

    slots = snapshot["slots"]
    required_slots = set(tables.get("slots", []))
    if not isinstance(slots, dict) or not required_slots.issubset(slots):
        missing = sorted(required_slots - set(slots) if isinstance(slots, dict) else required_slots)
        fail(f"{context} is missing required numeric slots: {missing}")
    if any(not is_number(value) for value in slots.values()):
        fail(f"{context} contains a non-numeric slot")

    entity_rules = {item["kind"]: item for item in tables.get("entities", [])}
    target_kinds = {item["kind"] for item in tables.get("targets", [])}
    entities = snapshot["entities"]
    targets = snapshot["targets"]
    if not isinstance(entities, list) or not isinstance(targets, list):
        fail(f"{context} entities and targets must be arrays")

    entity_ids = [entity.get("id") for entity in entities if isinstance(entity, dict)]
    if len(entity_ids) != len(set(entity_ids)):
        fail(f"{context} contains duplicate entity ids")

    for index, entity in enumerate(entities):
        entity_context = f"{context} entity {index}"
        if not isinstance(entity, dict) or not {"id", "kind", "state", "visible"}.issubset(entity):
            fail(f"{entity_context} must contain id, kind, state, and visible")
        if set(entity) - {"id", "kind", "state", "visible", "cell", "position", "size", "rect"}:
            fail(f"{entity_context} contains unknown fields")
        geometry_fields = [name for name in ("cell", "position", "rect") if name in entity]
        if len(geometry_fields) > 1:
            fail(f"{entity_context} cannot mix cell, position, and rect")
        if "size" in entity and "position" not in entity:
            fail(f"{entity_context} size requires position")
        if not isinstance(entity["id"], str) or not entity["id"]:
            fail(f"{entity_context} id must be a non-empty string")
        if not isinstance(entity["visible"], bool):
            fail(f"{entity_context} visible must be boolean")
        kind = entity["kind"]
        state = entity["state"]
        if kind not in entity_rules or state not in set(entity_rules[kind].get("states", [])):
            fail(f"{entity_context} has unknown kind/state {kind!r}/{state!r}")
        expected_geometry = entity_rules[kind].get("geometry")
        actual_geometry = geometry_fields[0] if geometry_fields else "none"
        if expected_geometry is not None and actual_geometry != expected_geometry:
            fail(
                f"{entity_context} must use {expected_geometry!r} geometry, "
                f"not {actual_geometry!r}"
            )
        if "cell" in entity:
            validate_cell(entity["cell"], entity_context, tables)
        if "position" in entity:
            validate_vector(entity["position"], f"{entity_context} position")
        if "size" in entity:
            validate_vector(entity["size"], f"{entity_context} size")
            if len(entity["size"]) != len(entity["position"]):
                fail(f"{entity_context} size and position dimensions must match")
            if any(value < 0 for value in entity["size"]):
                fail(f"{entity_context} size values must be non-negative")
        if "rect" in entity:
            validate_rect(entity["rect"], entity_context, tables)

    for index, target in enumerate(targets):
        target_context = f"{context} target {index}"
        if not isinstance(target, dict) or set(target) != {
            "kind", "rect", "visible", "interactable"
        }:
            fail(f"{target_context} has invalid fields")
        if target["kind"] not in target_kinds:
            fail(f"{target_context} has unknown kind {target['kind']!r}")
        if not isinstance(target["visible"], bool) or not isinstance(target["interactable"], bool):
            fail(f"{target_context} visibility flags must be booleans")
        validate_rect(target["rect"], target_context, tables)

    return revision


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dashboard", type=Path)
    parser.add_argument("naming_tables", type=Path)
    args = parser.parse_args()

    tables = validate_naming_tables(load_json(args.naming_tables))
    try:
        raw_lines = args.dashboard.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        fail(f"cannot read {args.dashboard}: {exc}")
    lines = [line for line in raw_lines if line.strip()]
    if not lines:
        fail("dashboard trace is empty")

    previous_revision = -1
    for line_number, line in enumerate(lines, 1):
        try:
            snapshot = json.loads(line)
        except json.JSONDecodeError as exc:
            fail(f"line {line_number} is not JSON: {exc}")
        previous_revision = validate_snapshot(snapshot, line_number, previous_revision, tables)

    print(f"dashboard self-check passed: {len(lines)} snapshots, last revision {previous_revision}")


if __name__ == "__main__":
    main()
