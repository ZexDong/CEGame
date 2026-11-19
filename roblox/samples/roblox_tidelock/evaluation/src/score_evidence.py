#!/usr/bin/env python3
"""Apply the frozen D1-D6 rubric to Tide Lock evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


VALID = {"pass", "fail", "inconclusive", "not_run"}


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rules", type=Path, required=True)
    parser.add_argument("--static", type=Path, required=True)
    parser.add_argument("--dynamic", type=Path, required=True)
    parser.add_argument("--visual", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--allow-incomplete", action="store_true")
    args = parser.parse_args()

    rules = load(args.rules)
    static = load(args.static)
    dynamic = load(args.dynamic)
    visual = load(args.visual) if args.visual and args.visual.is_file() else None
    checkpoints: dict[str, dict[str, Any]] = {}
    checkpoints.update(static.get("checkpoints", {}))
    checkpoints.update(dynamic.get("checkpoints", {}))

    problems: list[str] = []
    breakdown = []
    subtotal = 0.0
    unresolved = []
    for dimension in rules["dimensions"]:
        if dimension["id"] == "D6":
            if visual is None:
                score = None
                unresolved.append("D6 visual evaluation not available")
            else:
                score = float(visual.get("final_score"))
                rounds = visual.get("round_scores", [])
                if len(rounds) != 3 or not 0 <= score <= 10:
                    problems.append("invalid D6 visual result")
            breakdown.append({
                "dimension": "D6", "possible": 10, "score": score,
                "method": dimension["method"],
                "round_scores": visual.get("round_scores") if visual else None,
            })
            if score is not None:
                subtotal += score
            continue

        records = []
        passed = 0
        for checkpoint_id in dimension["checkpoints"]:
            record = checkpoints.get(checkpoint_id)
            if not isinstance(record, dict) or record.get("status") not in VALID:
                problems.append(f"missing or invalid checkpoint {checkpoint_id}")
                record = {"status": "not_run", "detail": "missing checkpoint record", "trace_ids": []}
            status = record["status"]
            if status == "pass":
                passed += 1
            if status in {"inconclusive", "not_run"}:
                unresolved.append(checkpoint_id)
            if status in {"pass", "fail"} and not (record.get("trace_ids") or record.get("evidence")):
                problems.append(f"{status} without evidence: {checkpoint_id}")
            records.append({"id": checkpoint_id, **record})
        score = round(float(dimension["points"]) * passed / len(records), 10)
        subtotal += score
        breakdown.append({
            "dimension": dimension["id"], "name": dimension["name"],
            "possible": dimension["points"], "score": round(score, 1),
            "passed_checkpoints": passed, "total_checkpoints": len(records),
            "checkpoints": records,
        })

    runner_valid = dynamic.get("runner_status") == "completed" and dynamic.get("host_fault") is None
    adjudication_complete = runner_valid and not unresolved and not problems
    official_score = round(subtotal, 1) if adjudication_complete else None
    if args.allow_incomplete:
        provisional = round(subtotal, 1)
    else:
        provisional = None
    result = {
        "schema_version": "tide-lock-score-v1",
        "candidate_zip_sha256": static.get("candidate_zip_sha256"),
        "runner_valid": runner_valid,
        "adjudication_complete": adjudication_complete,
        "official_score": official_score,
        "provisional_subtotal": provisional,
        "possible": 100,
        "unresolved": unresolved,
        "problems": problems,
        "breakdown": breakdown,
        "executable": dynamic.get("summary", {}).get("executable"),
        "solved": dynamic.get("summary", {}).get("solved"),
        "package_valid": static.get("checkpoints", {}).get("d1.package_integrity", {}).get("status") == "pass",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "official_score": official_score,
        "provisional_subtotal": provisional,
        "adjudication_complete": adjudication_complete,
        "unresolved_count": len(unresolved),
        "problem_count": len(problems),
    }, ensure_ascii=False))
    return 0 if adjudication_complete or args.allow_incomplete else 2


if __name__ == "__main__":
    raise SystemExit(main())
