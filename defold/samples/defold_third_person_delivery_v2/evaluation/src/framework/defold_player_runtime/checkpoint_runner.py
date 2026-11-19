#!/usr/bin/env python3
"""Minimal fixed checkpoint runner for Defold Dashboard tasks.

The runner is intentionally game-agnostic.  It operates only on the fixed checkpoint script,
the public naming tables, normal macOS keyboard/mouse events, and Dashboard JSONL snapshots.  It
records checkpoint outcomes but does not calculate benchmark scores.
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import json
import math
import random
import re
import secrets
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from framework.defold_player_runtime import RUNTIME_VERSION
from framework.defold_player_runtime.evidence import (
    EvidenceInfrastructureError,
    capture_window,
    normalize_text,
    ocr_image,
)
from framework.defold_player_runtime.expressions import (
    EvaluationContext,
    ExpressionError,
    ExpressionEvaluationError,
    SavedSnapshot,
    assert_true,
    compile_expression,
    selector_specs,
    snapshot_labels,
)
from framework.defold_player_runtime.player import (
    DashboardReader,
    NormalInputError,
    choose_physical_key,
    drive_to,
    driver_supported_keys,
    retreat_discrete_grid,
)
from framework.defold_player_runtime.runtime_errors import candidate_runtime_error_line
from framework.defold_player_runtime.score_reports import ReportError, validated_score_caps


SUPPORTED_VERBS = {
    "start",
    "press",
    "hold",
    "dual_hold",
    "click",
    "move_toward",
    "wait_until",
    "snapshot",
    "capture",
    "ocr_capture",
    "restart",
    "reopen",
}
DIRECTION_STATES = {"up_open", "down_open", "left_open", "right_open"}
MOVE_TOWARD_TEMPLATES = {
    "discrete_keys",
    "discrete_keys_with_hold_repeat",
    "continuous_platformer",
    "continuous_2d_keyboard",
    "continuous_world_3d_keyboard_with_pointer_ui",
}
DIRECTION_KEYS = {
    "up_open": "up",
    "down_open": "down",
    "left_open": "left",
    "right_open": "right",
}
CHECK_SOURCE_RE = re.compile(r"^(?:gdd:[^\s]+|common-baseline:CB-[0-9]{2})$")
LABEL_RE = re.compile(r"^[A-Z][A-Za-z0-9]*$")
ROOT_FIELDS = {
    "schema_version", "game", "naming_tables", "player_runtime_min_version",
    "controls_from_naming_tables", "trajectories", "honesty_spot_checks", "score_caps",
}
TRAJECTORY_FIELDS = {"id", "title", "clean_start", "steps"}
STEP_FIELDS = {
    "do", "target", "from", "to", "key", "second_key", "seconds", "cond", "timeout_s",
    "max_steps", "save_as", "defer_ocr", "honesty_safe", "check",
}
CHECK_FIELDS = {"id", "source", "dim", "assert"}


class ScriptValidationError(ValueError):
    def __init__(self, errors: list[str]):
        super().__init__("checkpoint script is outside the minimal runtime subset")
        self.errors = errors


class CandidateStepFailure(RuntimeError):
    pass


class CandidateRuntimeFailure(CandidateStepFailure):
    pass


class RuntimeInfrastructureError(RuntimeError):
    pass


INFRASTRUCTURE_FAILURES = (
    RuntimeInfrastructureError,
    EvidenceInfrastructureError,
    OSError,
)


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        return json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
        )
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        raise ScriptValidationError([f"cannot read {path}: {exc}"]) from exc


def version_tuple(value: str) -> tuple[int, ...]:
    try:
        parts = [int(part) for part in value.split(".")]
    except ValueError as exc:
        raise ValueError(f"invalid dotted numeric version {value!r}") from exc
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def honesty_candidate_indices(
    steps: list[dict[str, Any]],
    process_alive_at_start: bool = False,
) -> list[int]:
    """Return explicitly safe, live, non-exit honesty observation boundaries."""
    alive = process_alive_at_start
    result: list[int] = []
    for index, step in enumerate(steps):
        verb = step.get("do")
        if verb in {"start", "reopen"}:
            alive = True
        condition = step.get("cond")
        assertion = (
            step.get("check", {}).get("assert")
            if isinstance(step.get("check"), dict)
            else None
        )
        observes_exit = any(
            isinstance(value, str) and "process_exited" in value
            for value in (condition, assertion)
        )
        target_kind = (
            step.get("target", {}).get("kind")
            if isinstance(step.get("target"), dict)
            else None
        )
        triggers_exit = (
            (
                verb == "click"
                and isinstance(target_kind, str)
                and target_kind.endswith("exit_button")
            )
            or (verb == "press" and step.get("key") == "quit")
        )
        if step.get("honesty_safe") is True and alive and not observes_exit and not triggers_exit:
            result.append(index)
        if observes_exit or triggers_exit:
            alive = False
    return result


def exclusive_phase_ocr_matches(
    ocr_text: str,
    dashboard_phase: str,
    exclusive_by_phase: Any,
) -> list[dict[str, str]]:
    """Return evaluator-declared phase markers that contradict the Dashboard phase."""
    if not isinstance(exclusive_by_phase, dict):
        return []
    matches: list[dict[str, str]] = []
    for phase, alternatives in exclusive_by_phase.items():
        if phase == dashboard_phase or not isinstance(alternatives, list):
            continue
        for value in alternatives:
            if isinstance(value, str) and ocr_marker_matches(ocr_text, value):
                matches.append({"phase": phase, "text": value})
    return matches


def ocr_marker_matches(ocr_text: str, marker: str) -> bool:
    """Match Unicode words while tolerating OCR punctuation between marker words.

    OCR commonly substitutes spaces with punctuation or line breaks. Those separators are
    harmless, but matching whitespace-stripped text as an unrestricted substring makes ordinary
    words contradictory (for example, ``END GAME`` inside ``FRIEND GAMEPLAY``). Treat underscore
    as punctuation as well because it is a common OCR artifact rather than a natural word joiner.
    """
    words = re.findall(r"[^\W_]+", marker.casefold(), flags=re.UNICODE)
    if not words:
        return False
    separator = r"[\W_]+"
    pattern = (
        r"(?<![^\W_])"
        + separator.join(re.escape(word) for word in words)
        + r"(?![^\W_])"
    )
    return re.search(pattern, ocr_text.casefold(), flags=re.UNICODE) is not None


def _declared_physical_keys(keys: dict[str, Any]) -> set[str]:
    result: set[str] = set()
    for value in keys.values():
        if isinstance(value, str):
            result.add(value)
        elif isinstance(value, list):
            result.update(item for item in value if isinstance(item, str))
    return result


def _unknown_fields(value: dict[str, Any], allowed: set[str]) -> list[str]:
    return sorted(set(value) - allowed)


def _validate_selector(
    selector_name: str,
    selector: dict[str, str],
    entity_rules: dict[str, dict[str, Any]],
    target_kinds: set[str],
    context: str,
    errors: list[str],
) -> None:
    kind = selector.get("kind")
    if selector_name in {"target", "exists_target"}:
        if kind not in target_kinds:
            errors.append(f"{context}: target kind {kind!r} is absent from naming tables")
        if "state" in selector:
            errors.append(f"{context}: Dashboard targets have no state field")
        return
    if kind not in entity_rules:
        errors.append(f"{context}: entity kind {kind!r} is absent from naming tables")
        return
    state = selector.get("state")
    if state is not None and state not in entity_rules[kind].get("states", []):
        errors.append(f"{context}: state {state!r} is invalid for entity kind {kind!r}")


def validate_script(script: Any, naming: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(script, dict):
        return ["script root must be an object"]
    unknown_root = _unknown_fields(script, ROOT_FIELDS)
    if unknown_root:
        errors.append(f"script has unsupported fields: {unknown_root}")
    if script.get("schema_version") != 1:
        errors.append("script schema_version must be 1")
    if not isinstance(script.get("game"), str) or not script.get("game"):
        errors.append("script game must be a non-empty string")
    if not isinstance(script.get("naming_tables"), str) or not script.get("naming_tables"):
        errors.append("script naming_tables must be a non-empty string")
    if script.get("controls_from_naming_tables") is not True:
        errors.append("controls_from_naming_tables must be true")
    spot_checks = script.get("honesty_spot_checks")
    if spot_checks is not None:
        if not isinstance(spot_checks, dict):
            errors.append("honesty_spot_checks must be an object")
        else:
            unknown_spot_fields = _unknown_fields(
                spot_checks,
                {"per_trajectory", "mode", "exclusive_phase_ocr"},
            )
            if unknown_spot_fields:
                errors.append(f"honesty_spot_checks has unsupported fields: {unknown_spot_fields}")
            per_trajectory = spot_checks.get("per_trajectory", 0)
            if (
                isinstance(per_trajectory, bool)
                or not isinstance(per_trajectory, int)
                or per_trajectory < 0
            ):
                errors.append("honesty_spot_checks.per_trajectory must be a non-negative integer")
            if "mode" in spot_checks and spot_checks["mode"] != "random":
                errors.append("honesty_spot_checks.mode must be random")
            exclusive = spot_checks.get("exclusive_phase_ocr")
            if exclusive is not None:
                if not isinstance(exclusive, dict) or not exclusive:
                    errors.append(
                        "honesty_spot_checks.exclusive_phase_ocr must be a non-empty object"
                    )
                else:
                    normalized_exclusive: dict[str, tuple[str, str]] = {}
                    for phase, alternatives in exclusive.items():
                        if phase not in {"menu", "playing", "paused", "won", "lost"}:
                            errors.append(
                                "honesty_spot_checks.exclusive_phase_ocr has invalid "
                                f"phase {phase!r}"
                            )
                        valid_alternatives = (
                            isinstance(alternatives, list)
                            and bool(alternatives)
                            and all(isinstance(value, str) and bool(value) for value in alternatives)
                        )
                        if not valid_alternatives:
                            errors.append(
                                "honesty_spot_checks.exclusive_phase_ocr."
                                f"{phase} must contain normalized-unique non-empty strings"
                            )
                            continue
                        normalized = [normalize_text(value) for value in alternatives]
                        if (
                            any(not value for value in normalized)
                            or len(set(normalized)) != len(normalized)
                        ):
                            errors.append(
                                "honesty_spot_checks.exclusive_phase_ocr."
                                f"{phase} must contain normalized-unique non-empty strings"
                            )
                        for value, marker in zip(alternatives, normalized):
                            if not marker:
                                continue
                            prior = normalized_exclusive.get(marker)
                            if prior is not None:
                                errors.append(
                                    "honesty_spot_checks.exclusive_phase_ocr markers must be "
                                    "globally unique after normalization; "
                                    f"{value!r} in {phase!r} duplicates {prior[1]!r} "
                                    f"in {prior[0]!r}"
                                )
                            else:
                                normalized_exclusive[marker] = (phase, value)
    minimum = script.get("player_runtime_min_version")
    if minimum is not None:
        try:
            if version_tuple(str(minimum)) > version_tuple(RUNTIME_VERSION):
                errors.append(
                    f"script requires player runtime {minimum}, current runtime is {RUNTIME_VERSION}"
                )
        except ValueError as exc:
            errors.append(str(exc))

    if not isinstance(naming, dict) or naming.get("schema_version") != 2:
        errors.append("naming tables must use schema_version 2")
        return errors
    if isinstance(spot_checks, dict) and spot_checks.get("per_trajectory", 0) > 0:
        honesty = naming.get("honesty")
        phase_labels = honesty.get("phase_ocr_any") if isinstance(honesty, dict) else None
        if not isinstance(phase_labels, dict) or not phase_labels:
            errors.append(
                "nonzero honesty_spot_checks require naming tables honesty.phase_ocr_any"
            )
        else:
            for phase, alternatives in phase_labels.items():
                if phase not in {"menu", "playing", "paused", "won", "lost"}:
                    errors.append(f"honesty.phase_ocr_any has invalid phase {phase!r}")
                if (
                    not isinstance(alternatives, list)
                    or not alternatives
                    or any(not isinstance(value, str) or not value for value in alternatives)
                ):
                    errors.append(
                        f"honesty.phase_ocr_any.{phase} must be a non-empty string array"
                    )
    if isinstance(spot_checks, dict) and isinstance(
        spot_checks.get("exclusive_phase_ocr"), dict
    ):
        honesty = naming.get("honesty")
        phase_labels = honesty.get("phase_ocr_any") if isinstance(honesty, dict) else None
        if isinstance(phase_labels, dict):
            for phase, alternatives in spot_checks["exclusive_phase_ocr"].items():
                declared = phase_labels.get(phase, [])
                if isinstance(alternatives, list) and isinstance(declared, list):
                    normalized_declared = {
                        normalize_text(value)
                        for value in declared
                        if isinstance(value, str) and normalize_text(value)
                    }
                    undeclared = sorted(
                        value
                        for value in alternatives
                        if isinstance(value, str)
                        and normalize_text(value) not in normalized_declared
                    )
                    if undeclared:
                        errors.append(
                            "honesty_spot_checks.exclusive_phase_ocr."
                            f"{phase} contains markers absent from naming tables: {undeclared}"
                        )
                    for value in alternatives:
                        if not isinstance(value, str):
                            continue
                        marker = normalize_text(value)
                        if not marker:
                            continue
                        for other_phase, other_values in phase_labels.items():
                            if other_phase == phase or not isinstance(other_values, list):
                                continue
                            for other_value in other_values:
                                if not isinstance(other_value, str):
                                    continue
                                other_marker = normalize_text(other_value)
                                if not other_marker:
                                    continue
                                if marker == other_marker:
                                    errors.append(
                                        "honesty_spot_checks.exclusive_phase_ocr."
                                        f"{phase} marker {value!r} is also declared by "
                                        f"honesty.phase_ocr_any.{other_phase} after normalization"
                                    )
                                elif (
                                    ocr_marker_matches(other_value, value)
                                    or ocr_marker_matches(value, other_value)
                                ):
                                    errors.append(
                                        "honesty_spot_checks.exclusive_phase_ocr."
                                        f"{phase} marker {value!r} has a cross-phase whole-word "
                                        f"conflict with honesty.phase_ocr_any.{other_phase} "
                                        f"marker {other_value!r}"
                                    )
    controls = naming.get("controls")
    if not isinstance(controls, dict) or not isinstance(controls.get("movement_template"), str):
        errors.append("naming tables controls.movement_template is required")
        return errors
    keys = controls.get("keys", {})
    if not isinstance(keys, dict):
        errors.append("naming tables controls.keys must be an object when keyboard verbs are used")
        keys = {}
    for logical_key, declaration in keys.items():
        valid_string = isinstance(declaration, str) and bool(declaration)
        valid_list = (
            isinstance(declaration, list)
            and bool(declaration)
            and all(isinstance(item, str) and bool(item) for item in declaration)
        )
        if not valid_string and not valid_list:
            errors.append(
                f"naming tables control key {logical_key!r} must be a non-empty string "
                "or non-empty string array"
            )
    physical_keys = _declared_physical_keys(keys)
    entity_rules = {
        item.get("kind"): item
        for item in naming.get("entities", [])
        if isinstance(item, dict) and isinstance(item.get("kind"), str)
    }
    target_kinds = {
        item.get("kind")
        for item in naming.get("targets", [])
        if isinstance(item, dict) and isinstance(item.get("kind"), str)
    }

    trajectories = script.get("trajectories")
    if not isinstance(trajectories, list) or not trajectories:
        errors.append("script trajectories must be a non-empty array")
        return errors

    seen_trajectory_ids: set[str] = set()
    seen_check_ids: dict[str, tuple[Any, Any]] = {}
    for trajectory_index, trajectory in enumerate(trajectories):
        prefix = f"trajectory[{trajectory_index}]"
        if not isinstance(trajectory, dict):
            errors.append(f"{prefix}: must be an object")
            continue
        unknown_trajectory = _unknown_fields(trajectory, TRAJECTORY_FIELDS)
        if unknown_trajectory:
            errors.append(f"{prefix}: unsupported fields {unknown_trajectory}")
        trajectory_id = trajectory.get("id")
        if not isinstance(trajectory_id, str) or not re.fullmatch(r"[a-z0-9_]+", trajectory_id):
            errors.append(f"{prefix}: id must be lowercase snake_case")
        elif trajectory_id in seen_trajectory_ids:
            errors.append(f"{prefix}: duplicate trajectory id {trajectory_id!r}")
        else:
            seen_trajectory_ids.add(trajectory_id)
        if not isinstance(trajectory.get("title"), str):
            errors.append(f"{prefix}: title must be a string")
        if trajectory.get("clean_start") not in {"fresh_process", "restart", "none"}:
            errors.append(f"{prefix}: invalid clean_start")
        elif (
            trajectory.get("clean_start") == "restart"
            and "restart" not in keys
            and "restart_button" not in target_kinds
        ):
            errors.append(
                f"{prefix}: clean_start=restart needs controls.keys.restart "
                "or target kind restart_button"
            )
        steps = trajectory.get("steps")
        if not isinstance(steps, list) or not steps:
            errors.append(f"{prefix}: steps must be a non-empty array")
            continue
        requested_spots = (
            spot_checks.get("per_trajectory", 0)
            if isinstance(spot_checks, dict)
            else 0
        )
        eligible_spots = honesty_candidate_indices(
            steps,
            process_alive_at_start=trajectory.get("clean_start") == "restart",
        )
        eligible_spot_set = set(eligible_spots)
        if isinstance(requested_spots, int) and requested_spots > 0:
            if len(eligible_spots) < requested_spots:
                errors.append(
                    f"{prefix}: has {len(eligible_spots)} explicit live honesty_safe moments, "
                    f"fewer than requested {requested_spots}"
                )

        saved_labels: set[str] = set()
        deferred_capture_labels: set[str] = set()
        for step_index, step in enumerate(steps):
            context = f"{prefix}.steps[{step_index}]"
            if not isinstance(step, dict):
                errors.append(f"{context}: must be an object")
                continue
            unknown_step = _unknown_fields(step, STEP_FIELDS)
            if unknown_step:
                errors.append(f"{context}: unsupported fields {unknown_step}")
            verb = step.get("do")
            check = step.get("check")
            honesty_safe = step.get("honesty_safe")
            if "honesty_safe" in step and not isinstance(honesty_safe, bool):
                errors.append(f"{context}: honesty_safe must be boolean")
            if honesty_safe is True and step_index not in eligible_spot_set:
                errors.append(
                    f"{context}: honesty_safe requires a live game window and cannot "
                    "observe or trigger process exit"
                )
            if verb is None and check is None:
                errors.append(f"{context}: needs do or check")
            if verb is not None and verb not in SUPPORTED_VERBS:
                errors.append(
                    f"{context}: verb {verb!r} is not implemented; simplify the private script"
                )
            timeout_s = step.get("timeout_s")
            if timeout_s is not None and (
                isinstance(timeout_s, bool)
                or not isinstance(timeout_s, (int, float))
                or timeout_s < 0
            ):
                errors.append(f"{context}: timeout_s must be a non-negative number")
            if verb == "move_toward" and controls["movement_template"] not in MOVE_TOWARD_TEMPLATES:
                errors.append(
                    f"{context}: move_toward does not support movement_template="
                    f"{controls['movement_template']!r}"
                )
            elif verb == "move_toward" and controls["movement_template"] == "discrete_keys":
                player_rule = entity_rules.get("player")
                edge_rule = entity_rules.get("movement_edge")
                if not player_rule or player_rule.get("geometry") != "cell":
                    errors.append(
                        f"{context}: discrete_keys move_toward requires a cell-geometry player"
                    )
                if not edge_rule or edge_rule.get("geometry") != "cell":
                    errors.append(
                        f"{context}: discrete_keys move_toward requires cell-geometry movement_edge entities"
                    )
                elif not set(edge_rule.get("states", [])) & set(DIRECTION_STATES):
                    errors.append(
                        f"{context}: movement_edge must declare at least one supported open direction state"
                    )
                elif missing_direction_keys := {
                    DIRECTION_KEYS[state]
                    for state in set(edge_rule.get("states", [])) & DIRECTION_STATES
                    if DIRECTION_KEYS[state] not in keys
                }:
                    errors.append(
                        f"{context}: discrete_keys controls are missing directions "
                        f"{sorted(missing_direction_keys)}"
                    )
            elif verb == "move_toward" and controls["movement_template"] == "discrete_keys_with_hold_repeat":
                player_rule = entity_rules.get("player")
                selector = step.get("target")
                target_rule = entity_rules.get(selector.get("kind")) if isinstance(selector, dict) else None
                if not player_rule or player_rule.get("geometry") != "cell":
                    errors.append(f"{context}: grid move_toward requires a cell-geometry player")
                if not target_rule or target_rule.get("geometry") != "cell":
                    errors.append(f"{context}: grid move_toward requires a cell-geometry target")
                missing = {key for key in ("up", "down", "left", "right") if key not in keys}
                if missing:
                    errors.append(f"{context}: grid controls are missing directions {sorted(missing)}")
                for dimension in ("level_width_cells", "level_height_cells"):
                    value = naming.get(dimension)
                    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
                        errors.append(
                            f"{context}: grid move_toward requires positive public {dimension}"
                        )
                navigation = controls.get("navigation")
                if not isinstance(navigation, dict) or not isinstance(
                    navigation.get("blocking_kinds"), list
                ):
                    errors.append(
                        f"{context}: grid controls.navigation.blocking_kinds is required"
                    )
            elif verb == "move_toward":
                player_rule = entity_rules.get("player")
                if not player_rule or player_rule.get("geometry") != "position":
                    errors.append(
                        f"{context}: continuous move_toward requires a position-geometry player"
                    )
                selector = step.get("target")
                target_rule = entity_rules.get(selector.get("kind")) if isinstance(selector, dict) else None
                if not target_rule or target_rule.get("geometry") != "position":
                    errors.append(
                        f"{context}: continuous move_toward requires a position-geometry target"
                    )
                required_keys = (
                    {"left", "right", "jump"}
                    if controls["movement_template"] == "continuous_platformer"
                    else {"up", "down", "left", "right"}
                )
                missing = required_keys - set(keys)
                if missing:
                    errors.append(
                        f"{context}: continuous controls are missing keys {sorted(missing)}"
                    )
            if "max_steps" in step:
                max_steps = step["max_steps"]
                if (
                    verb != "move_toward"
                    or controls["movement_template"] != "discrete_keys"
                ):
                    errors.append(
                        f"{context}: max_steps is supported only by discrete_keys move_toward"
                    )
                if isinstance(max_steps, bool) or not isinstance(max_steps, int) or max_steps < 1:
                    errors.append(f"{context}: max_steps must be a positive integer")
            if verb in {"press", "hold"} or (verb == "move_toward" and "key" in step):
                key = step.get("key")
                if not isinstance(key, str):
                    errors.append(f"{context}: {verb} requires key")
                elif key not in keys and key not in physical_keys:
                    errors.append(f"{context}: key {key!r} is absent from naming-table controls")
            if verb == "dual_hold":
                first_key = step.get("key")
                second_key = step.get("second_key")
                for field_name, key in (("key", first_key), ("second_key", second_key)):
                    if not isinstance(key, str):
                        errors.append(f"{context}: dual_hold requires {field_name}")
                    elif key not in keys and key not in physical_keys:
                        errors.append(
                            f"{context}: {field_name} {key!r} is absent from naming-table controls"
                        )
                if isinstance(first_key, str) and first_key == second_key:
                    errors.append(f"{context}: dual_hold requires two distinct keys")
            if verb in {"hold", "dual_hold"} and (
                isinstance(step.get("seconds"), bool)
                or not isinstance(step.get("seconds"), (int, float))
                or step["seconds"] < 0
            ):
                errors.append(f"{context}: {verb} requires non-negative numeric seconds")
            if verb in {"click", "move_toward"}:
                selector = step.get("target")
                if not isinstance(selector, dict) or not isinstance(selector.get("kind"), str):
                    errors.append(f"{context}: {verb} requires target.kind")
                else:
                    unknown_selector = _unknown_fields(selector, {"kind", "state"})
                    if unknown_selector:
                        errors.append(f"{context}: target has unsupported fields {unknown_selector}")
                    if "state" in selector and not isinstance(selector["state"], str):
                        errors.append(f"{context}: target.state must be a string")
                    selector_name = "target" if verb == "click" else "entity"
                    _validate_selector(
                        selector_name, selector, entity_rules, target_kinds, context, errors
                    )
            if verb == "wait_until" and not isinstance(step.get("cond"), str):
                errors.append(f"{context}: wait_until requires cond")
            if verb == "snapshot" or (verb == "wait_until" and "save_as" in step):
                label = step.get("save_as")
                if not isinstance(label, str) or not LABEL_RE.fullmatch(label):
                    errors.append(f"{context}: {verb} requires a valid save_as label")
                elif label in saved_labels:
                    errors.append(f"{context}: duplicate snapshot label {label!r}")
                else:
                    saved_labels.add(label)
            elif verb == "capture":
                label = step.get("save_as")
                if label is not None and (
                    not isinstance(label, str) or not LABEL_RE.fullmatch(label)
                ):
                    errors.append(f"{context}: capture save_as must be a valid label")
                defer_ocr = step.get("defer_ocr", False)
                if not isinstance(defer_ocr, bool):
                    errors.append(f"{context}: capture defer_ocr must be boolean")
                elif defer_ocr:
                    if not isinstance(label, str) or not LABEL_RE.fullmatch(label):
                        errors.append(f"{context}: deferred capture requires a valid save_as label")
                    else:
                        deferred_capture_labels.add(label)
            elif verb == "ocr_capture":
                label = step.get("from")
                if not isinstance(label, str) or not LABEL_RE.fullmatch(label):
                    errors.append(f"{context}: ocr_capture requires a valid from label")
                elif label not in deferred_capture_labels:
                    errors.append(
                        f"{context}: ocr_capture from {label!r} must follow a deferred capture"
                    )
                else:
                    deferred_capture_labels.remove(label)
            if "defer_ocr" in step and verb != "capture":
                errors.append(f"{context}: defer_ocr is supported only by capture")
            if verb == "restart" and "restart" not in keys and "restart_button" not in target_kinds:
                errors.append(
                    f"{context}: restart needs controls.keys.restart or target kind restart_button"
                )

            for field_name in ("cond",):
                expression = step.get(field_name)
                if not isinstance(expression, str):
                    continue
                try:
                    node = compile_expression(expression)
                except ExpressionError as exc:
                    errors.append(f"{context}.{field_name}: {exc}")
                    continue
                missing = snapshot_labels(node) - saved_labels
                if missing:
                    errors.append(
                        f"{context}.{field_name}: unknown earlier snapshots {sorted(missing)}"
                    )
                for selector_name, selector in selector_specs(node):
                    _validate_selector(
                        selector_name, selector, entity_rules, target_kinds,
                        f"{context}.{field_name}", errors,
                    )

            if check is not None:
                if not isinstance(check, dict):
                    errors.append(f"{context}.check: must be an object")
                    continue
                unknown_check = _unknown_fields(check, CHECK_FIELDS)
                if unknown_check:
                    errors.append(f"{context}.check: unsupported fields {unknown_check}")
                check_id = check.get("id")
                if not isinstance(check_id, str) or not check_id:
                    errors.append(f"{context}.check: id is required")
                else:
                    signature = (check.get("source"), check.get("dim"))
                    if check_id in seen_check_ids and seen_check_ids[check_id] != signature:
                        errors.append(
                            f"{context}.check: repeated id {check_id!r} changed source or dimension"
                        )
                    else:
                        seen_check_ids[check_id] = signature
                if not isinstance(check.get("source"), str) or not CHECK_SOURCE_RE.fullmatch(check["source"]):
                    errors.append(f"{context}.check: invalid source")
                if check.get("dim") not in {"D2", "D3", "D4", "D5"}:
                    errors.append(f"{context}.check: dim must be D2, D3, D4, or D5")
                expression = check.get("assert")
                if not isinstance(expression, str):
                    errors.append(f"{context}.check: assert must be a string")
                    continue
                try:
                    node = compile_expression(expression)
                except ExpressionError as exc:
                    errors.append(f"{context}.check.assert: {exc}")
                    continue
                missing = snapshot_labels(node) - saved_labels
                if missing:
                    errors.append(
                        f"{context}.check.assert: unknown earlier snapshots {sorted(missing)}"
                    )
                for selector_name, selector in selector_specs(node):
                    _validate_selector(
                        selector_name, selector, entity_rules, target_kinds,
                        f"{context}.check.assert", errors,
                    )
    try:
        validated_score_caps(script, set(seen_check_ids))
    except ReportError as exc:
        errors.append(str(exc))
    return errors


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


class EvidenceStore:
    def __init__(self, output: Path):
        self.output = output
        self.events_path = output / "events.jsonl"
        self.dashboard_path = output / "dashboard-observed.jsonl"
        self.seen_revisions: set[tuple[int, int]] = set()

    def event(self, **values: Any) -> None:
        row = {
            "utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "monotonic_s": time.monotonic(),
            **values,
        }
        with self.events_path.open("a", encoding="utf-8") as target:
            target.write(json.dumps(row, sort_keys=True) + "\n")

    def dashboards(self, launch_index: int, trajectory: str, snapshots: list[dict[str, Any]]) -> None:
        with self.dashboard_path.open("a", encoding="utf-8") as target:
            for snapshot in snapshots:
                identity = (launch_index, int(snapshot["revision"]))
                if identity in self.seen_revisions:
                    continue
                self.seen_revisions.add(identity)
                target.write(
                    json.dumps(
                        {
                            "launch_index": launch_index,
                            "trajectory": trajectory,
                            "observed_monotonic_s": time.monotonic(),
                            "snapshot": snapshot,
                        },
                        sort_keys=True,
                    )
                    + "\n"
                )


class GameSession:
    def __init__(self, executable: Path, run_directory: Path, evidence: EvidenceStore):
        self.executable = executable.resolve()
        self.run_directory = run_directory
        self.evidence = evidence
        self.process: subprocess.Popen[str] | None = None
        self.log_handle: Any = None
        self.reader: DashboardReader | None = None
        self.launch_index = 0
        self.started_monotonic: float | None = None
        self.log_path: Path | None = None
        self.log_offset = 0
        self.log_fragment = b""
        self.pending_candidate_runtime_errors: list[dict[str, Any]] = []

    @property
    def dashboard_path(self) -> Path:
        return self.run_directory / "dashboard.jsonl"

    @property
    def pid(self) -> int:
        if self.process is None or self.process.poll() is not None:
            raise RuntimeInfrastructureError("game process is not running")
        return self.process.pid

    def start(self) -> None:
        if self.process is not None and self.process.poll() is None:
            raise RuntimeInfrastructureError("start requested while game process is already running")
        if self.process is not None or self.log_handle is not None:
            self.stop()
        self.run_directory.mkdir(parents=True, exist_ok=True)
        self.dashboard_path.unlink(missing_ok=True)
        self.launch_index += 1
        log_path = self.run_directory / f"process-{self.launch_index}.log"
        self.log_path = log_path
        self.log_offset = 0
        self.log_fragment = b""
        self.log_handle = log_path.open("w", encoding="utf-8")
        try:
            self.process = subprocess.Popen(
                [str(self.executable)],
                cwd=self.run_directory,
                stdout=self.log_handle,
                stderr=subprocess.STDOUT,
                text=True,
            )
            self.started_monotonic = time.monotonic()
        except OSError as exc:
            self.log_handle.close()
            self.log_handle = None
            raise RuntimeInfrastructureError(f"could not launch game: {exc}") from exc
        self.reader = DashboardReader(self.dashboard_path)

    def scan_candidate_runtime_errors(self, finalize: bool = False) -> list[dict[str, Any]]:
        """Incrementally classify new candidate-owned fatal log lines."""
        if self.log_path is None or not self.log_path.exists():
            return []
        try:
            with self.log_path.open("rb") as source:
                source.seek(self.log_offset)
                chunk = source.read()
                self.log_offset = source.tell()
        except OSError as exc:
            raise RuntimeInfrastructureError(
                f"could not read candidate runtime log {self.log_path}: {exc}"
            ) from exc

        combined = self.log_fragment + chunk
        parts = combined.split(b"\n")
        if finalize:
            self.log_fragment = b""
        else:
            self.log_fragment = parts.pop()

        found: list[dict[str, Any]] = []
        seen_in_scan: set[str] = set()
        for raw_line in parts:
            line = raw_line.decode("utf-8", errors="replace").rstrip("\r")
            fatal = candidate_runtime_error_line(line)
            if fatal is None or fatal in seen_in_scan:
                continue
            seen_in_scan.add(fatal)
            result = {
                "launch_index": self.launch_index,
                "log": str(self.log_path),
                "line": fatal,
            }
            self.pending_candidate_runtime_errors.append(result)
            found.append(result)
        return found

    def take_candidate_runtime_errors(self) -> list[dict[str, Any]]:
        result = self.pending_candidate_runtime_errors
        self.pending_candidate_runtime_errors = []
        return result

    def stop(self) -> None:
        scan_error: RuntimeInfrastructureError | None = None
        try:
            self.scan_candidate_runtime_errors(finalize=False)
        except RuntimeInfrastructureError as exc:
            scan_error = exc
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        self.process = None
        self.reader = None
        self.started_monotonic = None
        if self.log_handle is not None:
            self.log_handle.close()
            self.log_handle = None
        try:
            self.scan_candidate_runtime_errors(finalize=True)
        except RuntimeInfrastructureError as exc:
            if scan_error is None:
                scan_error = exc
        if scan_error is not None:
            raise scan_error

    def reopen(self) -> None:
        self.stop()
        self.start()

    def wait_for_window_settle(self, minimum_age_s: float = 0.5) -> None:
        if self.started_monotonic is None:
            raise RuntimeInfrastructureError("window settle requested without a running process")
        remaining = minimum_age_s - (time.monotonic() - self.started_monotonic)
        if remaining > 0:
            time.sleep(remaining)


class NormalInputAdapter:
    def __init__(self, driver: Path, naming: dict[str, Any]):
        self.driver = driver.resolve()
        self.naming = naming
        self.keys = naming.get("controls", {}).get("keys", {})
        try:
            self.supported = driver_supported_keys(self.driver)
        except NormalInputError as exc:
            raise RuntimeInfrastructureError(str(exc)) from exc

    def physical_key(self, requested: str) -> str:
        if requested in self.keys:
            declared = self.keys[requested]
        elif requested in _declared_physical_keys(self.keys):
            declared = requested
        else:
            raise RuntimeInfrastructureError(
                f"key {requested!r} is not declared by naming-table controls"
            )
        try:
            return choose_physical_key(declared, self.supported)
        except NormalInputError as exc:
            raise RuntimeInfrastructureError(str(exc)) from exc

    def command(self, arguments: list[str]) -> None:
        completed = subprocess.run(
            [str(self.driver), *arguments],
            text=True,
            capture_output=True,
        )
        if completed.returncode:
            detail = completed.stderr.strip() or completed.stdout.strip() or f"exit {completed.returncode}"
            raise RuntimeInfrastructureError(f"normal-input driver failed: {detail}")

    def press(self, pid: int, key: str) -> None:
        self.command([str(pid), "key", self.physical_key(key), "press"])

    def hold(self, pid: int, key: str, seconds: float) -> None:
        self.command([str(pid), "key", self.physical_key(key), "hold", str(seconds)])

    def dual_hold(self, pid: int, first: str, second: str, seconds: float) -> None:
        self.command(
            [
                str(pid),
                "dual_hold",
                self.physical_key(first),
                self.physical_key(second),
                str(seconds),
            ]
        )

    def click_target(self, pid: int, target: dict[str, Any]) -> None:
        if not target.get("visible") or not target.get("interactable"):
            raise CandidateStepFailure(f"target {target.get('kind')!r} is not currently operable")
        rect = target.get("rect")
        if not isinstance(rect, list) or len(rect) != 4:
            raise CandidateStepFailure(f"target {target.get('kind')!r} has no valid rect")
        try:
            left, bottom, rect_width, rect_height = (float(value) for value in rect)
        except (TypeError, ValueError) as exc:
            raise CandidateStepFailure(
                f"target {target.get('kind')!r} rect is not numeric"
            ) from exc
        width = float(self.naming["target_rect_space"]["width"])
        height = float(self.naming["target_rect_space"]["height"])
        if not (
            all(math.isfinite(value) for value in (left, bottom, rect_width, rect_height))
            and rect_width > 0 and rect_height > 0
            and 0 <= left < left + rect_width <= width
            and 0 <= bottom < bottom + rect_height <= height
        ):
            raise CandidateStepFailure(f"target {target.get('kind')!r} rect is outside game view or empty")
        # Both Dashboard target rectangles and the driver use game-view pixels from bottom-left.
        self.command(
            [
                str(pid),
                "click",
                str(left),
                str(bottom),
                str(rect_width),
                str(rect_height),
                str(width),
                str(height),
            ]
        )


class CheckpointRunner:
    def __init__(
        self,
        script: dict[str, Any],
        naming: dict[str, Any],
        naming_path: Path,
        executable: Path,
        input_driver: Path,
        output: Path,
    ):
        self.script = script
        self.naming = naming
        self.naming_path = naming_path
        self.output = output
        self.evidence = EvidenceStore(output)
        self.session = GameSession(executable, output / "run", self.evidence)
        self.input = NormalInputAdapter(input_driver, naming)
        self.saved: dict[str, SavedSnapshot] = {}
        self.captures: dict[str, dict[str, Any]] = {}
        self.current_capture: str | None = None
        self.selected_target: dict[str, Any] | None = None
        self.checks: list[dict[str, Any]] = []
        self.honesty_checks: list[dict[str, Any]] = []
        self.candidate_runtime_errors: list[dict[str, Any]] = []
        self.candidate_runtime_failed_trajectories: set[str] = set()
        self.runtime_log_scan_errors: list[dict[str, Any]] = []
        self.runtime_log_scan_failed_trajectories: set[str] = set()
        self.dashboard_trusted = True
        self.current_trajectory = ""
        self.last_action_trajectory = ""
        self.last_action_step_index = -1
        self.last_action: str | None = None

    def collect_candidate_runtime_errors(
        self,
        step_index: int,
        boundary: str,
        *,
        finalize: bool = False,
        action: str | None = None,
    ) -> list[dict[str, Any]]:
        self.session.scan_candidate_runtime_errors(finalize=finalize)
        return self.record_candidate_runtime_errors(
            self.session.take_candidate_runtime_errors(),
            step_index,
            boundary,
            action,
        )

    def record_candidate_runtime_errors(
        self,
        raw_errors: list[dict[str, Any]],
        step_index: int,
        boundary: str,
        action: str | None = None,
    ) -> list[dict[str, Any]]:
        """Attach already-scanned candidate failures to the active trajectory."""
        results: list[dict[str, Any]] = []
        for raw in raw_errors:
            result = {
                **raw,
                "trajectory": self.current_trajectory,
                "step_index": step_index,
                "boundary": boundary,
                "action": action,
            }
            self.candidate_runtime_errors.append(result)
            results.append(result)
            self.evidence.event(
                trajectory=self.current_trajectory,
                step_index=step_index,
                event="candidate_runtime_error",
                boundary=boundary,
                action=action,
                launch_index=result["launch_index"],
                log=result["log"],
                line=result["line"],
            )
        return results

    def record_runtime_log_scan_error(
        self,
        error: RuntimeInfrastructureError,
        step_index: int,
        boundary: str,
        action: str | None = None,
        trajectory: str | None = None,
    ) -> None:
        """Persist a log-reader infrastructure failure with its true boundary owner."""
        trajectory_id = self.current_trajectory if trajectory is None else trajectory
        result = {
            "trajectory": trajectory_id,
            "step_index": step_index,
            "boundary": boundary,
            "action": action,
            "detail": str(error),
        }
        self.runtime_log_scan_errors.append(result)
        if trajectory_id:
            self.runtime_log_scan_failed_trajectories.add(trajectory_id)
        self.evidence.event(
            trajectory=trajectory_id,
            step_index=step_index,
            event="runtime_log_scan_error",
            boundary=boundary,
            action=action,
            detail=str(error),
        )

    def require_clean_candidate_runtime_log(
        self,
        step_index: int,
        boundary: str,
        action: str | None = None,
    ) -> None:
        try:
            errors = self.collect_candidate_runtime_errors(
                step_index,
                boundary,
                action=action,
            )
        except RuntimeInfrastructureError as exc:
            self.record_runtime_log_scan_error(exc, step_index, boundary, action)
            raise
        if errors:
            summary = "; ".join(str(item["line"]) for item in errors[:3])
            if len(errors) > 3:
                summary += f"; and {len(errors) - 3} more"
            raise CandidateRuntimeFailure(f"candidate runtime error: {summary}")

    def execute_monitored_action(
        self,
        trajectory_dir: Path,
        step_index: int,
        step: dict[str, Any],
    ) -> None:
        """Execute one action with incremental candidate-log gates on both boundaries."""
        action = step.get("do")
        self.require_clean_candidate_runtime_log(step_index, "before_action", action)
        try:
            self.execute_action(trajectory_dir, step_index, step)
        except Exception as action_error:
            try:
                self.require_clean_candidate_runtime_log(step_index, "after_action", action)
            except CandidateRuntimeFailure as runtime_error:
                if isinstance(action_error, INFRASTRUCTURE_FAILURES):
                    raise action_error
                raise runtime_error from action_error
            except RuntimeInfrastructureError:
                if isinstance(action_error, INFRASTRUCTURE_FAILURES):
                    raise action_error
                raise
            raise
        self.require_clean_candidate_runtime_log(step_index, "after_action", action)

    def fail_check_for_candidate_runtime_error(
        self,
        trajectory_id: str,
        step_index: int,
        detail: str,
        check: dict[str, Any] | None = None,
        *,
        fallback_to_previous: bool = False,
    ) -> None:
        """Fail the current, or latest prior, scored check without duplicating rows."""
        existing = next(
            (
                row
                for row in reversed(self.checks)
                if row.get("trajectory") == trajectory_id
                and row.get("step_index") == step_index
            ),
            None,
        )
        if existing is None and fallback_to_previous:
            existing = next(
                (
                    row
                    for row in reversed(self.checks)
                    if row.get("trajectory") == trajectory_id
                    and isinstance(row.get("step_index"), int)
                    and int(row["step_index"]) <= step_index
                ),
                None,
            )
        if existing is not None:
            existing["status"] = "fail"
            existing["detail"] = detail
            return
        if check is not None:
            self.checks.append(
                {
                    "id": check["id"],
                    "source": check["source"],
                    "dim": check["dim"],
                    "trajectory": trajectory_id,
                    "step_index": step_index,
                    "status": "fail",
                    "assert": check["assert"],
                    "detail": detail,
                }
            )

    def drain(self) -> dict[str, Any] | None:
        if self.session.reader is None:
            return None
        updates = self.session.reader.poll_updates()
        self.evidence.dashboards(
            self.session.launch_index, self.current_trajectory, updates
        )
        return self.session.reader.latest

    def latest(self, timeout_s: float = 2.0) -> dict[str, Any]:
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            latest = self.drain()
            if latest is not None:
                return latest
            if self.session.process is not None and self.session.process.poll() is not None:
                raise CandidateStepFailure(
                    f"game exited with code {self.session.process.returncode} before Dashboard became ready"
                )
            time.sleep(0.03)
        raise CandidateStepFailure("Dashboard did not produce a snapshot before timeout")

    def wait_for_dashboard_advance(
        self,
        previous_revision: int,
        timeout_s: float = 1.2,
    ) -> dict[str, Any] | None:
        # A game may publish timer/animation revisions continuously.  Give the
        # normal OS input one frame to be consumed before accepting a newer
        # snapshot, otherwise an unrelated timer revision can race the input.
        time.sleep(0.10)
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            snapshot = self.drain()
            if snapshot is not None and int(snapshot["revision"]) > previous_revision:
                return snapshot
            if self.session.process is not None and self.session.process.poll() is not None:
                return None
            time.sleep(0.03)
        # Ignored input is a legitimate result in terminal states and at blocked
        # movement boundaries.  The fixed settle above prevents stale reads;
        # lack of a new revision is therefore gameplay evidence, not a runtime
        # failure.
        return self.drain()

    def context(self, snapshot: dict[str, Any] | None = None) -> EvaluationContext:
        process = self.session.process
        process_exit_code = process.poll() if process is not None else None
        return EvaluationContext(
            current=snapshot or self.latest(),
            saved=self.saved,
            monotonic_s=time.monotonic(),
            captures=self.captures,
            current_capture=self.current_capture,
            process_exited=process is not None and process_exit_code is not None,
            process_exit_code=process_exit_code,
            selected_target=self.selected_target,
        )

    def wait_condition(self, expression: str, timeout_s: float) -> dict[str, Any]:
        node = compile_expression(expression)
        deadline = time.monotonic() + timeout_s
        last_error: str | None = None
        while time.monotonic() < deadline:
            snapshot = self.drain()
            if snapshot is not None:
                try:
                    if assert_true(node, self.context(snapshot)):
                        return snapshot
                except ExpressionEvaluationError as exc:
                    last_error = str(exc)
            if self.session.process is not None and self.session.process.poll() is not None:
                raise CandidateStepFailure(
                    f"game exited with code {self.session.process.returncode}; last expression error={last_error}"
                )
            time.sleep(0.03)
        detail = f"; last expression error={last_error}" if last_error else ""
        raise CandidateStepFailure(
            f"condition was not reached within {timeout_s:.2f}s: {expression!r}{detail}"
        )

    def condition_is_true(self, expression: str) -> bool:
        snapshot = self.drain() or self.latest()
        try:
            return assert_true(expression, self.context(snapshot))
        except ExpressionEvaluationError:
            return False

    def run_honesty_spot_check(
        self,
        trajectory_dir: Path,
        trajectory_id: str,
        step_index: int,
        check_index: int,
        rng: random.Random,
    ) -> dict[str, Any]:
        """Cross-check a random stable Dashboard moment against the real window.

        This is a trust gate, never a gameplay checkpoint.  It uses only a real window
        capture, narrow OCR alternatives declared in the public naming table, and a
        short no-input observation.
        """
        before = copy.deepcopy(self.latest())
        phase = before["phase"]
        alternatives = self.naming["honesty"]["phase_ocr_any"].get(phase)
        if not isinstance(alternatives, list) or not alternatives:
            raise RuntimeInfrastructureError(
                f"honesty phase OCR alternatives are absent for observed phase {phase!r}"
            )

        capture_path = (
            trajectory_dir
            / "honesty"
            / f"spot-{check_index:02d}-step-{step_index:03d}.png"
        )
        self.session.wait_for_window_settle()
        capture_window(self.session.pid, capture_path)
        no_input_seconds = rng.uniform(0.09, 0.18)
        time.sleep(no_input_seconds)
        after = copy.deepcopy(self.latest())
        phase_stable = after["phase"] == phase
        result = {
            "trajectory": trajectory_id,
            "spot_index": check_index,
            "step_index": step_index,
            "status": "pending_ocr",
            "dashboard_revision_before": before["revision"],
            "dashboard_revision_after": after["revision"],
            "dashboard_phase": phase,
            "phase_after_no_input": after["phase"],
            "phase_stable_without_input": phase_stable,
            "no_input_seconds": no_input_seconds,
            "phase_ocr_any": alternatives,
            "matched_ocr": None,
            "capture": str(capture_path),
            "ocr": None,
            "capture_attempts": [],
        }
        self.honesty_checks.append(result)
        self.evidence.event(
            trajectory=trajectory_id,
            step_index=step_index,
            event="honesty_spot_captured",
            dashboard_phase=phase,
            phase_stable_without_input=phase_stable,
        )
        return result

    def finalize_honesty_spot_checks(self) -> None:
        """OCR already-captured spot checks after gameplay has stopped.

        Tesseract is intentionally kept off the live gameplay path: OCR latency
        must not consume fuses, timers, invulnerability windows, or enemy turns.
        """
        for result in self.honesty_checks:
            if result.get("status") != "pending_ocr":
                continue
            capture_path = Path(str(result["capture"]))
            ocr = ocr_image(capture_path)
            alternatives = result["phase_ocr_any"]
            normalized = normalize_text(str(ocr["normalized"]))
            matched = next(
                (value for value in alternatives if normalize_text(value) in normalized),
                None,
            )
            visual_check = next(
                (
                    check["id"]
                    for check in self.checks
                    if check.get("trajectory") == result["trajectory"]
                    and check.get("step_index") == result["step_index"]
                    and check.get("dim") == "D5"
                    and check.get("status") == "pass"
                ),
                None,
            )
            contradictory_matches = []
            for phase, phase_values in self.naming["honesty"]["phase_ocr_any"].items():
                if phase == result["dashboard_phase"]:
                    continue
                for value in phase_values:
                    if normalize_text(value) in normalized:
                        contradictory_matches.append({"phase": phase, "text": value})
                        break
            exclusive_matches = exclusive_phase_ocr_matches(
                "\n".join(
                    str(line)
                    for line in ocr.get("lines", [])
                    if isinstance(line, str)
                ),
                result["dashboard_phase"],
                self.script.get("honesty_spot_checks", {}).get("exclusive_phase_ocr"),
            )
            stable = bool(result["phase_stable_without_input"])
            if not stable or exclusive_matches:
                status = "fail"
            elif matched is not None or visual_check is not None:
                status = "pass"
            else:
                # Missing OCR is absence of confirmation, not evidence that the read-only
                # Dashboard lied. Other phase labels are also not contradictions: menus and
                # overlays commonly leave gameplay HUD text visible underneath. Keep the run
                # valid; the task's D5 checks deduct unreadable or missing UI independently.
                status = "inconclusive"
            result["status"] = status
            result["matched_ocr"] = matched
            result["accepted_visual_check"] = visual_check
            result["contradictory_phase_ocr"] = contradictory_matches
            result["exclusive_phase_ocr"] = exclusive_matches
            result["ocr"] = ocr
            result["capture_attempts"] = [
                {
                    "capture": str(capture_path),
                    "ocr": ocr,
                    "matched_ocr": matched,
                }
            ]
            write_json(capture_path.with_suffix(".json"), result)
            if status == "fail":
                self.dashboard_trusted = False
            self.evidence.event(
                trajectory=result["trajectory"],
                step_index=result["step_index"],
                event="honesty_spot_check",
                status=result["status"],
                dashboard_phase=result["dashboard_phase"],
                matched_ocr=matched,
                accepted_visual_check=visual_check,
                contradictory_phase_ocr=contradictory_matches,
                exclusive_phase_ocr=exclusive_matches,
                phase_stable_without_input=result["phase_stable_without_input"],
            )

    def complete_public_post_action_cycle(self, deadline: float) -> None:
        """Retreat from and wait out public grid hazards created by an action.

        The behavior is driven exclusively by the public naming table and Dashboard
        entities.  Games without these declarations are unaffected.
        """
        navigation = self.naming.get("controls", {}).get("navigation", {})
        avoid_kinds = set(navigation.get("post_action_avoid_kinds", []))
        settle_kinds = set(navigation.get("post_action_settle_kinds", []))
        if not avoid_kinds and not settle_kinds:
            return

        # Give the next normal game frame a brief chance to expose the newly created
        # hazard before planning the retreat.  A rejected action is not an evaluator
        # failure; the surrounding public condition determines whether to retry.
        manifestation_deadline = min(deadline, time.monotonic() + 0.5)
        while time.monotonic() < manifestation_deadline:
            snapshot = self.drain() or self.latest()
            if snapshot["phase"] in {"won", "lost"}:
                return
            if any(item.get("kind") in avoid_kinds for item in snapshot["entities"]):
                break
            time.sleep(0.03)

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise CandidateStepFailure("post-action retreat exceeded the step timeout")
        try:
            retreat_discrete_grid(
                self.session.dashboard_path,
                self.naming,
                self.input.driver,
                self.session.pid,
                remaining,
            )
        except NormalInputError as exc:
            raise RuntimeInfrastructureError(str(exc)) from exc
        except RuntimeError as exc:
            raise CandidateStepFailure(str(exc)) from exc
        self.drain()

        while time.monotonic() < deadline:
            snapshot = self.drain() or self.latest()
            if snapshot["phase"] in {"won", "lost"}:
                return
            if not any(item.get("kind") in settle_kinds for item in snapshot["entities"]):
                return
            time.sleep(0.03)
        raise CandidateStepFailure("public post-action hazards did not settle before timeout")

    def select_target(self, selector: dict[str, Any]) -> dict[str, Any]:
        snapshot = self.latest()
        matches = [
            target
            for target in snapshot["targets"]
            if target.get("kind") == selector["kind"]
        ]
        if len(matches) != 1:
            raise CandidateStepFailure(
                f"target selector {selector!r} matched {len(matches)} targets, expected one"
            )
        return matches[0]

    def select_entity_target(self, selector: dict[str, Any]) -> dict[str, Any] | None:
        snapshot = self.latest()
        matches = [
            item
            for item in snapshot["entities"]
            if item.get("kind") == selector["kind"]
            and ("state" not in selector or item.get("state") == selector["state"])
            and item.get("visible") is not False
        ]
        players = [item for item in snapshot["entities"] if item.get("kind") == "player"]
        if not matches or len(players) != 1:
            return None
        player = players[0]
        if isinstance(player.get("cell"), list):
            def metric(item: dict[str, Any]) -> float:
                cell = item.get("cell")
                if not isinstance(cell, list):
                    return float("inf")
                return abs(float(cell[0]) - float(player["cell"][0])) + abs(
                    float(cell[1]) - float(player["cell"][1])
                )
        else:
            def metric(item: dict[str, Any]) -> float:
                position = item.get("position")
                player_position = player.get("position")
                if not isinstance(position, list) or not isinstance(player_position, list):
                    return float("inf")
                return sum(
                    (float(a) - float(b)) ** 2
                    for a, b in zip(position, player_position)
                )
        return copy.deepcopy(min(matches, key=lambda item: (metric(item), str(item.get("id", "")))))

    def execute_action(self, trajectory_dir: Path, step_index: int, step: dict[str, Any]) -> None:
        verb = step.get("do")
        if verb is None:
            return
        if verb == "start":
            self.session.start()
        elif verb == "reopen":
            self.session.reopen()
        elif verb == "press":
            condition = step.get("cond")
            if not isinstance(condition, str):
                before_revision = int(self.latest()["revision"])
                self.input.press(self.session.pid, step["key"])
                self.wait_for_dashboard_advance(before_revision)
            else:
                deadline = time.monotonic() + float(step.get("timeout_s", 3))
                while time.monotonic() < deadline:
                    if self.condition_is_true(condition):
                        break
                    before_revision = int(self.latest()["revision"])
                    self.input.press(self.session.pid, step["key"])
                    self.wait_for_dashboard_advance(
                        before_revision,
                        min(0.6, max(0.05, deadline - time.monotonic())),
                    )
                    if self.condition_is_true(condition):
                        break
                else:
                    raise CandidateStepFailure(
                        f"repeated normal key presses did not reach condition: {condition!r}"
                    )
        elif verb == "hold":
            condition = step.get("cond")
            if not isinstance(condition, str):
                before_revision = int(self.latest()["revision"])
                self.input.hold(self.session.pid, step["key"], float(step["seconds"]))
                self.wait_for_dashboard_advance(before_revision)
            else:
                deadline = time.monotonic() + float(step.get("timeout_s", 10))
                while time.monotonic() < deadline:
                    if self.condition_is_true(condition):
                        break
                    before_revision = int(self.latest()["revision"])
                    self.input.hold(
                        self.session.pid,
                        step["key"],
                        min(float(step["seconds"]), max(0.05, deadline - time.monotonic())),
                    )
                    self.wait_for_dashboard_advance(
                        before_revision,
                        min(0.8, max(0.05, deadline - time.monotonic())),
                    )
                    if self.condition_is_true(condition):
                        break
                else:
                    raise CandidateStepFailure(
                        f"repeated normal key holds did not reach condition: {condition!r}"
                    )
        elif verb == "dual_hold":
            before_revision = int(self.latest()["revision"])
            self.input.dual_hold(
                self.session.pid,
                step["key"],
                step["second_key"],
                float(step["seconds"]),
            )
            self.wait_for_dashboard_advance(before_revision)
        elif verb == "click":
            condition = step.get("cond")
            if not isinstance(condition, str):
                before_revision = int(self.latest()["revision"])
                self.input.click_target(self.session.pid, self.select_target(step["target"]))
                self.wait_for_dashboard_advance(before_revision)
            else:
                deadline = time.monotonic() + float(step.get("timeout_s", 10))
                while time.monotonic() < deadline:
                    if self.condition_is_true(condition):
                        break
                    before_revision = int(self.latest()["revision"])
                    self.input.click_target(self.session.pid, self.select_target(step["target"]))
                    self.wait_for_dashboard_advance(
                        before_revision,
                        min(1.2, max(0.05, deadline - time.monotonic())),
                    )
                    if self.condition_is_true(condition):
                        break
                else:
                    raise CandidateStepFailure(
                        f"repeated normal clicks did not reach condition: {condition!r}"
                    )
        elif verb == "move_toward":
            selector = step["target"]
            condition = step.get("cond")
            deadline = time.monotonic() + float(step.get("timeout_s", 30))
            while True:
                if isinstance(condition, str) and self.condition_is_true(condition):
                    break
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise CandidateStepFailure(
                        f"move_toward did not reach condition: {condition!r}"
                    )
                try:
                    self.selected_target = self.select_entity_target(selector)
                    drive_to(
                        self.session.dashboard_path,
                        self.naming_path,
                        self.input.driver,
                        self.session.pid,
                        selector["kind"],
                        selector.get("state"),
                        remaining,
                        step.get("key"),
                        step.get("max_steps"),
                    )
                except NormalInputError as exc:
                    raise RuntimeInfrastructureError(str(exc)) from exc
                except RuntimeError as exc:
                    raise CandidateStepFailure(str(exc)) from exc
                self.drain()
                self.selected_target = self.select_entity_target(selector) or self.selected_target
                if isinstance(step.get("key"), str):
                    self.input.press(self.session.pid, step["key"])
                    time.sleep(0.04)
                    self.drain()
                    navigation = self.naming.get("controls", {}).get("navigation", {})
                    if step["key"] == navigation.get("action_key"):
                        self.complete_public_post_action_cycle(deadline)
                if not isinstance(condition, str):
                    break
                time.sleep(0.04)
        elif verb == "wait_until":
            self.wait_condition(step["cond"], float(step.get("timeout_s", 10)))
            if "save_as" in step:
                snapshot = copy.deepcopy(self.latest())
                label = step["save_as"]
                self.saved[label] = SavedSnapshot(snapshot, time.monotonic())
                write_json(trajectory_dir / "snapshots" / f"{label}.json", snapshot)
        elif verb == "snapshot":
            snapshot = copy.deepcopy(self.latest())
            label = step["save_as"]
            self.saved[label] = SavedSnapshot(snapshot, time.monotonic())
            write_json(trajectory_dir / "snapshots" / f"{label}.json", snapshot)
        elif verb == "capture":
            label = step.get("save_as", f"Step{step_index:03d}")
            self.session.wait_for_window_settle()
            path = capture_window(
                self.session.pid, trajectory_dir / "captures" / f"{label}.png"
            )
            result = {
                "path": str(path),
                "byte_size": path.stat().st_size,
                "ocr": None if step.get("defer_ocr", False) else ocr_image(path),
            }
            self.captures[label] = result
            self.current_capture = label
            write_json(trajectory_dir / "captures" / f"{label}.ocr.json", result)
        elif verb == "ocr_capture":
            label = step["from"]
            result = self.captures.get(label)
            if not isinstance(result, dict):
                raise RuntimeInfrastructureError(f"deferred capture {label!r} is unavailable")
            path = Path(str(result["path"]))
            result["ocr"] = ocr_image(path)
            self.current_capture = label
            write_json(trajectory_dir / "captures" / f"{label}.ocr.json", result)
        elif verb == "restart":
            snapshot = self.latest()
            targets = [
                target
                for target in snapshot["targets"]
                if target.get("kind") == "restart_button"
                and target.get("visible")
                and target.get("interactable")
            ]
            if len(targets) == 1:
                self.input.click_target(self.session.pid, targets[0])
            elif "restart" in self.input.keys:
                self.input.press(self.session.pid, "restart")
            else:
                raise CandidateStepFailure("no operable public restart entry")
            self.drain()
        else:  # guarded by preflight
            raise RuntimeInfrastructureError(f"unsupported verb reached dispatcher: {verb!r}")

    def evaluate_check(
        self,
        trajectory_id: str,
        step_index: int,
        check: dict[str, Any],
    ) -> dict[str, Any]:
        snapshot = self.latest()
        try:
            passed = assert_true(check["assert"], self.context(snapshot))
            status = "pass" if passed else "fail"
            detail = "assertion evaluated true" if passed else "assertion evaluated false"
        except ExpressionEvaluationError as exc:
            status = "fail"
            detail = f"assertion could not resolve against candidate state: {exc}"
        result = {
            "id": check["id"],
            "source": check["source"],
            "dim": check["dim"],
            "trajectory": trajectory_id,
            "step_index": step_index,
            "status": status,
            "assert": check["assert"],
            "detail": detail,
            "dashboard_revision": snapshot["revision"],
        }
        self.checks.append(result)
        return result

    def unavailable_remaining(
        self,
        trajectory_id: str,
        steps: list[dict[str, Any]],
        start_index: int,
        reason: str,
    ) -> None:
        for step_index in range(start_index, len(steps)):
            check = steps[step_index].get("check")
            if not isinstance(check, dict):
                continue
            self.checks.append(
                {
                    "id": check["id"],
                    "source": check["source"],
                    "dim": check["dim"],
                    "trajectory": trajectory_id,
                    "step_index": step_index,
                    "status": "unable",
                    "assert": check["assert"],
                    "detail": reason,
                }
            )

    def run_trajectory(self, trajectory: dict[str, Any]) -> dict[str, Any]:
        trajectory_id = trajectory["id"]
        if trajectory["clean_start"] == "fresh_process":
            previous_trajectory = self.current_trajectory
            try:
                self.session.stop()
                transition_errors = self.collect_candidate_runtime_errors(
                    self.last_action_step_index,
                    "trajectory_shutdown",
                    finalize=True,
                    action=self.last_action,
                )
            except RuntimeInfrastructureError as exc:
                self.record_runtime_log_scan_error(
                    exc,
                    self.last_action_step_index,
                    "trajectory_shutdown",
                    self.last_action,
                    previous_trajectory,
                )
                transition_errors = self.record_candidate_runtime_errors(
                    self.session.take_candidate_runtime_errors(),
                    self.last_action_step_index,
                    "trajectory_shutdown",
                    self.last_action,
                )
            if transition_errors and previous_trajectory:
                detail = "candidate runtime error while ending trajectory: " + "; ".join(
                    str(item["line"]) for item in transition_errors[:3]
                )
                self.fail_check_for_candidate_runtime_error(
                    previous_trajectory,
                    self.last_action_step_index,
                    detail,
                    fallback_to_previous=True,
                )
                self.candidate_runtime_failed_trajectories.add(previous_trajectory)
        self.current_trajectory = trajectory_id
        self.saved = {}
        self.captures = {}
        self.current_capture = None
        self.selected_target = None
        trajectory_dir = self.output / "trajectories" / trajectory_id
        trajectory_dir.mkdir(parents=True)
        steps = trajectory["steps"]
        requested_spots = int(
            self.script.get("honesty_spot_checks", {}).get("per_trajectory", 0)
        )
        stable_indices = honesty_candidate_indices(
            steps,
            process_alive_at_start=trajectory["clean_start"] == "restart",
        )
        seed = secrets.randbits(64)
        rng = random.Random(seed)
        scheduled_spots = set(
            rng.sample(stable_indices, min(requested_spots, len(stable_indices)))
        )
        completed_spots = 0
        self.evidence.event(
            trajectory=trajectory_id,
            step_index=-1,
            event="honesty_schedule",
            seed=seed,
            requested=requested_spots,
            scheduled=sorted(scheduled_spots),
        )
        try:
            if trajectory["clean_start"] == "restart":
                if self.session.process is None or self.session.process.poll() is not None:
                    self.execute_monitored_action(trajectory_dir, -1, {"do": "start"})
                    try:
                        self.latest()
                    except Exception as readiness_error:
                        try:
                            self.require_clean_candidate_runtime_log(
                                -1, "after_clean_start_readiness"
                            )
                        except CandidateRuntimeFailure as runtime_error:
                            raise runtime_error from readiness_error
                        raise
                    self.require_clean_candidate_runtime_log(
                        -1, "after_clean_start_readiness"
                    )
                self.execute_monitored_action(trajectory_dir, -1, {"do": "restart"})
        except CandidateStepFailure as exc:
            self.unavailable_remaining(
                trajectory_id, steps, 0, f"clean start could not be established: {exc}"
            )
            self.evidence.event(
                trajectory=trajectory_id,
                step_index=-1,
                event="candidate_clean_start_failed",
                detail=str(exc),
            )
            return {"id": trajectory_id, "status": "candidate_step_failed"}
        except (RuntimeInfrastructureError, EvidenceInfrastructureError, OSError) as exc:
            self.unavailable_remaining(
                trajectory_id, steps, 0, f"clean start infrastructure failure: {exc}"
            )
            self.evidence.event(
                trajectory=trajectory_id,
                step_index=-1,
                event="clean_start_infrastructure_invalid",
                detail=str(exc),
            )
            return {"id": trajectory_id, "status": "infrastructure_invalid"}

        outcome = "completed"
        for step_index, step in enumerate(steps):
            self.last_action_trajectory = trajectory_id
            self.last_action_step_index = step_index
            self.last_action = step.get("do")
            self.evidence.event(
                trajectory=trajectory_id,
                step_index=step_index,
                event="step_started",
                verb=step.get("do"),
                action={
                    key: step[key]
                    for key in ("do", "target", "key", "seconds", "cond", "timeout_s", "save_as")
                    if key in step
                },
                check_id=step.get("check", {}).get("id") if isinstance(step.get("check"), dict) else None,
            )
            try:
                self.execute_monitored_action(trajectory_dir, step_index, step)
                check_result = None
                if isinstance(step.get("check"), dict):
                    check_result = self.evaluate_check(trajectory_id, step_index, step["check"])
                if step_index in scheduled_spots:
                    self.run_honesty_spot_check(
                        trajectory_dir,
                        trajectory_id,
                        step_index,
                        completed_spots,
                        rng,
                    )
                    completed_spots += 1
                self.require_clean_candidate_runtime_log(
                    step_index,
                    "end_of_step",
                    step.get("do"),
                )
            except CandidateRuntimeFailure as exc:
                outcome = "candidate_step_failed"
                check = step.get("check")
                has_downstream_check = any(
                    isinstance(later_step.get("check"), dict)
                    for later_step in steps[step_index + 1:]
                )
                fallback_to_previous = not isinstance(check, dict) and not has_downstream_check
                detail = str(exc)
                if fallback_to_previous:
                    detail = (
                        f"candidate runtime error at terminal unscored step {step_index} "
                        f"({step.get('do') or 'observation'}); attributed to the latest prior "
                        f"scored check because no downstream scored check remained: {exc}"
                    )
                self.fail_check_for_candidate_runtime_error(
                    trajectory_id,
                    step_index,
                    detail,
                    check if isinstance(check, dict) else None,
                    fallback_to_previous=fallback_to_previous,
                )
                self.unavailable_remaining(
                    trajectory_id,
                    steps,
                    step_index + 1,
                    f"unreachable after candidate runtime error at step {step_index}: {exc}",
                )
                self.evidence.event(
                    trajectory=trajectory_id,
                    step_index=step_index,
                    event="candidate_runtime_step_failed",
                    detail=str(exc),
                )
                break
            except CandidateStepFailure as exc:
                outcome = "candidate_step_failed"
                check = step.get("check")
                if isinstance(check, dict):
                    self.checks.append(
                        {
                            "id": check["id"], "source": check["source"], "dim": check["dim"],
                            "trajectory": trajectory_id, "step_index": step_index,
                            "status": "fail", "assert": check["assert"], "detail": str(exc),
                        }
                    )
                self.unavailable_remaining(
                    trajectory_id, steps, step_index + 1,
                    f"unreachable after step {step_index}: {exc}",
                )
                self.evidence.event(
                    trajectory=trajectory_id, step_index=step_index,
                    event="candidate_step_failed", detail=str(exc),
                )
                break
            except (RuntimeInfrastructureError, EvidenceInfrastructureError, OSError) as exc:
                outcome = "infrastructure_invalid"
                check = step.get("check")
                if isinstance(check, dict):
                    self.checks.append(
                        {
                            "id": check["id"], "source": check["source"], "dim": check["dim"],
                            "trajectory": trajectory_id, "step_index": step_index,
                            "status": "invalid", "assert": check["assert"], "detail": str(exc),
                        }
                    )
                self.unavailable_remaining(
                    trajectory_id, steps, step_index + 1,
                    f"not evaluated after infrastructure failure at step {step_index}: {exc}",
                )
                self.evidence.event(
                    trajectory=trajectory_id, step_index=step_index,
                    event="infrastructure_invalid", detail=str(exc),
                )
                break
            else:
                self.evidence.event(
                    trajectory=trajectory_id,
                    step_index=step_index,
                    event="step_completed",
                    check_status=check_result and check_result["status"],
                )
        if outcome == "completed" and completed_spots != requested_spots:
            outcome = "infrastructure_invalid"
            self.evidence.event(
                trajectory=trajectory_id,
                step_index=len(steps),
                event="honesty_schedule_incomplete",
                requested=requested_spots,
                completed=completed_spots,
            )
        return {"id": trajectory_id, "status": outcome}

    def run(self, selected_trajectories: set[str] | None = None) -> dict[str, Any]:
        trajectory_results: list[dict[str, Any]] = []
        shutdown_errors: list[dict[str, Any]] = []
        try:
            for trajectory in self.script["trajectories"]:
                if selected_trajectories and trajectory["id"] not in selected_trajectories:
                    continue
                trajectory_results.append(self.run_trajectory(trajectory))
        finally:
            try:
                self.session.stop()
            except RuntimeInfrastructureError as exc:
                self.record_runtime_log_scan_error(
                    exc,
                    self.last_action_step_index,
                    "shutdown",
                    self.last_action,
                    self.last_action_trajectory,
                )
                shutdown_errors = self.record_candidate_runtime_errors(
                    self.session.take_candidate_runtime_errors(),
                    self.last_action_step_index,
                    "shutdown",
                    self.last_action,
                )
            else:
                try:
                    shutdown_errors = self.collect_candidate_runtime_errors(
                        self.last_action_step_index,
                        "shutdown",
                        finalize=True,
                        action=self.last_action,
                    )
                except RuntimeInfrastructureError as exc:
                    self.record_runtime_log_scan_error(
                        exc,
                        self.last_action_step_index,
                        "shutdown",
                        self.last_action,
                        self.last_action_trajectory,
                    )
        if shutdown_errors and self.last_action_trajectory:
            detail = "candidate runtime error at shutdown: " + "; ".join(
                str(item["line"]) for item in shutdown_errors[:3]
            )
            self.fail_check_for_candidate_runtime_error(
                self.last_action_trajectory,
                self.last_action_step_index,
                detail,
                fallback_to_previous=True,
            )
            for result in reversed(trajectory_results):
                if result.get("id") == self.last_action_trajectory:
                    if result.get("status") != "infrastructure_invalid":
                        result["status"] = "candidate_step_failed"
                    break
        for result in trajectory_results:
            if (
                result.get("id") in self.candidate_runtime_failed_trajectories
                and result.get("status") != "infrastructure_invalid"
            ):
                result["status"] = "candidate_step_failed"
            if result.get("id") in self.runtime_log_scan_failed_trajectories:
                result["status"] = "infrastructure_invalid"
        self.finalize_honesty_spot_checks()
        invalid = any(result["status"] == "infrastructure_invalid" for result in trajectory_results)
        if self.runtime_log_scan_errors:
            invalid = True
        if not self.dashboard_trusted:
            invalid = True
        report = {
            "schema_version": 1,
            "runtime_version": RUNTIME_VERSION,
            "game": self.script["game"],
            "evaluation_status": "infrastructure_invalid" if invalid else "valid",
            "dashboard_trusted": self.dashboard_trusted,
            "honesty_spot_checks": self.honesty_checks,
            "candidate_runtime_errors": self.candidate_runtime_errors,
            "runtime_log_scan_error": (
                "; ".join(item["detail"] for item in self.runtime_log_scan_errors)
                if self.runtime_log_scan_errors
                else None
            ),
            "trajectories": trajectory_results,
            "checks": self.checks,
            "score": None,
            "note": "Checkpoint evidence only; dimension scoring and D6 are outside this runner.",
        }
        write_json(self.output / "checkpoint-report.json", report)
        return report


def resolve_naming_path(script_path: Path, script: dict[str, Any], explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit.resolve()
    value = script.get("naming_tables")
    if not isinstance(value, str):
        raise ScriptValidationError(["script naming_tables path is required"])
    return (script_path.parent / value).resolve()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--script", type=Path, required=True)
    parser.add_argument("--naming-tables", type=Path)
    parser.add_argument("--executable", type=Path)
    parser.add_argument("--input-driver", type=Path, default=Path(__file__).with_name("macos_input.sh"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--trajectory", action="append", default=[])
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()

    script_path = args.script.resolve()
    try:
        script = load_json(script_path)
        naming_path = resolve_naming_path(script_path, script, args.naming_tables)
        naming = load_json(naming_path)
    except ScriptValidationError as exc:
        print(json.dumps({"status": "rejected", "errors": exc.errors}, indent=2))
        raise SystemExit(2) from exc
    errors = validate_script(script, naming)
    selected_trajectories = set(args.trajectory)
    known_trajectories = {
        trajectory.get("id")
        for trajectory in script.get("trajectories", [])
        if isinstance(trajectory, dict)
    }
    unknown_trajectories = selected_trajectories - known_trajectories
    if unknown_trajectories:
        errors.append(f"unknown selected trajectories: {sorted(unknown_trajectories)}")
    if errors:
        print(json.dumps({"status": "rejected", "errors": errors}, indent=2))
        raise SystemExit(2)
    if args.validate_only:
        print(json.dumps({"status": "accepted", "runtime_version": RUNTIME_VERSION}, indent=2))
        return
    if args.executable is None or args.output is None:
        parser.error("--executable and --output are required unless --validate-only is used")
    if not args.executable.is_file():
        parser.error(f"executable does not exist: {args.executable}")
    if args.output.exists():
        parser.error(f"output must not already exist: {args.output}")
    args.output.mkdir(parents=True)

    try:
        runner = CheckpointRunner(
            script=script,
            naming=naming,
            naming_path=naming_path,
            executable=args.executable,
            input_driver=args.input_driver,
            output=args.output,
        )
    except RuntimeInfrastructureError as exc:
        report = {
            "schema_version": 1,
            "runtime_version": RUNTIME_VERSION,
            "game": script["game"],
            "evaluation_status": "infrastructure_invalid",
            "trajectories": [],
            "checks": [],
            "score": None,
            "note": str(exc),
        }
        write_json(args.output / "checkpoint-report.json", report)
        print(json.dumps(report, indent=2))
        raise SystemExit(3) from exc
    report = runner.run(selected_trajectories or None)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
