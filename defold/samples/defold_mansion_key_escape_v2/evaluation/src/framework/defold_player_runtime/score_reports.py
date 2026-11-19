#!/usr/bin/env python3
"""Combine common D1 and checkpoint evidence into D1-D5 scores.

This module contains no game rules.  The fixed checkpoint script defines the scored units;
the common formula comes from the game-independent scoring guide.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


DIMENSION_MAXIMA = {"D1": 10.0, "D2": 30.0, "D3": 20.0, "D4": 20.0, "D5": 10.0}
DYNAMIC_DIMENSIONS = ("D2", "D3", "D4", "D5")
CANDIDATE_STATUSES = {"pass", "fail", "unable"}


class ReportError(ValueError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReportError(f"cannot read {path}: {exc}") from exc


def expected_checks(script: dict[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    for trajectory in script.get("trajectories", []):
        for step in trajectory.get("steps", []):
            check = step.get("check")
            if not isinstance(check, dict):
                continue
            check_id = check.get("id")
            dimension = check.get("dim")
            if not isinstance(check_id, str) or not check_id:
                raise ReportError("checkpoint script contains a check without an id")
            if dimension not in DYNAMIC_DIMENSIONS:
                raise ReportError(f"checkpoint {check_id!r} has invalid dimension {dimension!r}")
            if check_id in result and result[check_id] != dimension:
                raise ReportError(
                    f"repeated checkpoint {check_id!r} changed dimension from "
                    f"{result[check_id]!r} to {dimension!r}"
                )
            result[check_id] = dimension
    for dimension in DYNAMIC_DIMENSIONS:
        if dimension not in result.values():
            raise ReportError(f"checkpoint script has no scored checks for {dimension}")
    return result


def validated_score_caps(
    script: dict[str, Any],
    known_check_ids: set[str],
) -> list[dict[str, Any]]:
    """Validate and normalize evaluator-declared nonvisual score caps.

    A cap is triggered unless every check named by ``requires_all`` passed.  The
    policy lives in the fixed checkpoint script so the common scorer remains
    game-independent.
    """
    value = script.get("score_caps", [])
    if not isinstance(value, list):
        raise ReportError("score_caps must be an array")

    result: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    expected_fields = {"id", "requires_all", "max_nonvisual_score"}
    for index, cap in enumerate(value):
        context = f"score_caps[{index}]"
        if not isinstance(cap, dict):
            raise ReportError(f"{context} must be an object")
        unknown_fields = sorted(set(cap) - expected_fields)
        missing_fields = sorted(expected_fields - set(cap))
        if unknown_fields or missing_fields:
            raise ReportError(
                f"{context} fields mismatch; missing={missing_fields}, extra={unknown_fields}"
            )

        cap_id = cap["id"]
        if not isinstance(cap_id, str) or not cap_id:
            raise ReportError(f"{context}.id must be a non-empty string")
        if cap_id in seen_ids:
            raise ReportError(f"duplicate score cap id {cap_id!r}")
        seen_ids.add(cap_id)

        required = cap["requires_all"]
        if (
            not isinstance(required, list)
            or not required
            or any(not isinstance(check_id, str) or not check_id for check_id in required)
        ):
            raise ReportError(f"{context}.requires_all must be a non-empty string array")
        if len(set(required)) != len(required):
            raise ReportError(f"{context}.requires_all contains duplicate check ids")
        unknown_checks = sorted(set(required) - known_check_ids)
        if unknown_checks:
            raise ReportError(f"{context}.requires_all references unknown checks {unknown_checks}")

        maximum = cap["max_nonvisual_score"]
        if (
            isinstance(maximum, bool)
            or not isinstance(maximum, (int, float))
            or not math.isfinite(float(maximum))
            or not 0 <= float(maximum) <= 90
        ):
            raise ReportError(
                f"{context}.max_nonvisual_score must be a finite number in [0, 90]"
            )
        result.append(
            {
                "id": cap_id,
                "requires_all": list(required),
                "max_nonvisual_score": float(maximum),
            }
        )
    return result


def infrastructure_invalid_report(reason: str) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "evaluation_status": "infrastructure_invalid",
        "reason": reason,
        "dimensions": {dimension: None for dimension in DIMENSION_MAXIMA},
        "raw_nonvisual_score": None,
        "nonvisual_score": None,
        "nonvisual_max": 90.0,
        "applied_score_cap": None,
        "triggered_score_caps": [],
        "D6": None,
        "total_score": None,
    }


def evaluator_invalid_report(reason: str) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "evaluation_status": "evaluator_invalid",
        "reason": reason,
        "dimensions": {dimension: None for dimension in DIMENSION_MAXIMA},
        "raw_nonvisual_score": None,
        "nonvisual_score": None,
        "nonvisual_max": 90.0,
        "applied_score_cap": None,
        "triggered_score_caps": [],
        "D6": None,
        "total_score": None,
    }


def combine_reports(
    d1_report: dict[str, Any],
    checkpoint_report: dict[str, Any],
    script: dict[str, Any],
) -> dict[str, Any]:
    if d1_report.get("evaluation_status") != "valid":
        return infrastructure_invalid_report("D1 report is not valid")
    if checkpoint_report.get("evaluation_status") != "valid":
        return infrastructure_invalid_report("checkpoint report is not valid")

    d1_score = d1_report.get("d1_score")
    if (
        isinstance(d1_score, bool)
        or not isinstance(d1_score, (int, float))
        or not 0 <= float(d1_score) <= DIMENSION_MAXIMA["D1"]
    ):
        return evaluator_invalid_report("D1 score is absent or outside [0, 10]")

    try:
        expected = expected_checks(script)
        score_caps = validated_score_caps(script, set(expected))
    except ReportError as exc:
        return evaluator_invalid_report(str(exc))

    rows = checkpoint_report.get("checks")
    if not isinstance(rows, list):
        return evaluator_invalid_report("checkpoint report checks must be an array")
    report_ids = [row.get("id") for row in rows if isinstance(row, dict)]
    if len(report_ids) != len(rows):
        return evaluator_invalid_report("checkpoint report contains a non-object check row")
    missing = sorted(set(expected) - set(report_ids))
    extra = sorted(set(report_ids) - set(expected))
    if missing or extra:
        return evaluator_invalid_report(f"checkpoint report id mismatch; missing={missing}, extra={extra}")

    counts = {
        dimension: {"pass": 0, "total": 0}
        for dimension in DYNAMIC_DIMENSIONS
    }
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault(row["id"], []).append(row)
    check_passed: dict[str, bool] = {}
    for check_id, parts in grouped.items():
        dimension = expected[check_id]
        statuses: list[str] = []
        for row in parts:
            if row.get("dim") != dimension:
                return evaluator_invalid_report(
                    f"checkpoint {check_id!r} dimension is {row.get('dim')!r}, expected {dimension!r}"
                )
            status = row.get("status")
            if status == "invalid":
                return infrastructure_invalid_report(
                    f"checkpoint {check_id!r} was invalid because evaluator infrastructure failed"
                )
            if status not in CANDIDATE_STATUSES:
                return evaluator_invalid_report(
                    f"checkpoint {check_id!r} has unknown status {status!r}"
                )
            statuses.append(status)
        counts[dimension]["total"] += 1
        check_passed[check_id] = bool(statuses) and all(status == "pass" for status in statuses)
        if check_passed[check_id]:
            counts[dimension]["pass"] += 1

    dimensions: dict[str, Any] = {
        "D1": {
            "score": float(d1_score),
            "max": DIMENSION_MAXIMA["D1"],
            "source": "static D1 report",
        }
    }
    for dimension in DYNAMIC_DIMENSIONS:
        passed = counts[dimension]["pass"]
        total = counts[dimension]["total"]
        score = DIMENSION_MAXIMA[dimension] * passed / total
        dimensions[dimension] = {
            "score": score,
            "max": DIMENSION_MAXIMA[dimension],
            "passed_checks": passed,
            "total_checks": total,
        }
    raw_nonvisual = sum(item["score"] for item in dimensions.values())
    triggered_caps: list[dict[str, Any]] = []
    for cap in score_caps:
        failed = [
            check_id
            for check_id in cap["requires_all"]
            if not check_passed.get(check_id, False)
        ]
        if failed:
            triggered_caps.append(
                {
                    "id": cap["id"],
                    "max_nonvisual_score": cap["max_nonvisual_score"],
                    "failed_required_checks": failed,
                }
            )
    applied_cap = (
        min(cap["max_nonvisual_score"] for cap in triggered_caps)
        if triggered_caps
        else None
    )
    nonvisual = min(raw_nonvisual, applied_cap) if applied_cap is not None else raw_nonvisual
    return {
        "schema_version": 1,
        "evaluation_status": "valid",
        "dimensions": dimensions,
        "raw_nonvisual_score": raw_nonvisual,
        "nonvisual_score": nonvisual,
        "nonvisual_max": 90.0,
        "applied_score_cap": applied_cap,
        "triggered_score_caps": triggered_caps,
        "D6": None,
        "total_score": None,
        "note": "D6 is scored separately by the frozen visual protocol.",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--d1-report", type=Path, required=True)
    parser.add_argument("--checkpoint-report", type=Path, required=True)
    parser.add_argument("--script", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error(f"output already exists: {args.output}")
    report = combine_reports(
        load_json(args.d1_report),
        load_json(args.checkpoint_report),
        load_json(args.script),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
