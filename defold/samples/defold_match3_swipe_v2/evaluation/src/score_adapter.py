"""Convert native Defold checkpoint evidence to the shared six-dimension format."""
from __future__ import annotations

import json
import math
import re
from pathlib import Path

MAXIMA = {"D1": 10, "D2": 30, "D3": 20, "D4": 20, "D5": 10, "D6": 10}
STATIC = ("D1_PROJECT_ENTRY", "D1_BOB_BUILD", "D1_BUNDLE_ENTRY", "D1_RUNTIME_DASHBOARD_SMOKE")


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def requirement_id(value):
    return re.sub(r"[^A-Za-z0-9_.:-]+", "-", value).strip("-")


def catalog(rules):
    if "trajectories" not in rules:
        return [{"id": c["id"], "dimension": c["dimension"], "weight": c["weight"],
                 "requirements": c["requirements"]} for c in rules["checks"]]
    rows = [{"id": name, "dimension": "D1", "weight": 1,
             "requirements": ["common-baseline:CB-01" if i < 3 else "common-baseline:CB-02"]}
            for i, name in enumerate(STATIC)]
    known = {}
    for trajectory in rules["trajectories"]:
        for step in trajectory["steps"]:
            c = step.get("check")
            if not c:
                continue
            item = {"id": c["id"], "dimension": c["dim"], "weight": 1,
                    "requirements": [requirement_id(c["source"])]}
            if c["id"] in known and known[c["id"]] != item:
                raise ValueError("Repeated checkpoint changed its meaning: " + c["id"])
            known[c["id"]] = item
    return rows + list(known.values())


def normalized_weights(rows):
    weights = {}
    for dim, maximum in MAXIMA.items():
        group = [c for c in rows if c["dimension"] == dim]
        if not group:
            continue
        denominator = sum(c["weight"] for c in group)
        used = 0
        for i, c in enumerate(group):
            value = round(maximum - used, 6) if i == len(group) - 1 else round(maximum * c["weight"] / denominator, 6)
            weights[c["id"]] = value
            used += value
    return weights


def convert(evaluation, output, meta, reason="", infrastructure=False):
    rules = read(evaluation / "rules.json")
    rows = catalog(rules)
    weights = normalized_weights(rows)
    native_path = output / "native/score.json"
    native = read(native_path) if native_path.is_file() else {}
    status = native.get("evaluation_status")
    infrastructure = infrastructure or status in {"infrastructure_invalid", "evaluator_invalid"} or not native
    observations = {}
    if "trajectories" in rules:
        for rel in ("native/d1/d1-report.json", "native/checkpoint/checkpoint-report.json"):
            path = output / rel
            if path.is_file():
                report = read(path)
                if report.get("evaluation_status") == "valid":
                    for item in report.get("checks", []):
                        observations.setdefault(item["id"], []).append((item, rel))
    else:
        for item in native.get("checks", []):
            observations.setdefault(item["id"], []).append((item, "native/score.json"))
    checks = []
    for c in rows:
        found = observations.get(c["id"], [])
        verdicts = [v.get("status", v.get("verdict")) for v, _ in found]
        evidence = sorted(set(rel + "#check-" + c["id"] for _, rel in found))
        if infrastructure:
            state, points, why = "inconclusive_evaluator", None, reason or native.get("reason") or "Native evaluator did not complete."
        elif not found or any(v in {"invalid", "excluded", "pending"} for v in verdicts):
            state, points, why = "not_run", None, "No resolved native observation."
        elif all(v == "pass" for v in verdicts):
            state, points, why = "pass", weights[c["id"]], "All native observations passed."
        else:
            state, points = "fail", 0
            why = "; ".join(str(v.get("detail", v.get("reason", "Native candidate check failed.")))
                            for v, _ in found if v.get("status", v.get("verdict")) != "pass")
        checks.append({"id": c["id"], "requirement_ids": c["requirements"],
                       "dimension": c["dimension"], "max_score": weights[c["id"]],
                       "score": points, "status": state, "reason": why,
                       "blocked_by": [], "evidence": evidence})

    outcome_observations = {}
    if not infrastructure:
        if isinstance(native.get("outcome_observations"), dict):
            outcome_observations.update(native["outcome_observations"])
        if "journey" not in outcome_observations:
            j_checks = [c for c in checks if c["id"] in ('D4.CHAPTERS', 'D4.SUCCESS')]
            if j_checks:
                if any(c["status"] == "fail" for c in j_checks):
                    ev = sorted({ref for c in j_checks if c["status"] == "fail" for ref in c["evidence"]})
                    if ev:
                        outcome_observations["journey"] = {"value": 0, "evidence": ev}
                elif all(c["status"] == "pass" for c in j_checks):
                    ev = sorted({ref for c in j_checks for ref in c["evidence"]})
                    if ev:
                        outcome_observations["journey"] = {"value": 1, "evidence": ev}
        # These checks cover restart/reopen but do not enumerate every persistence obligation.
        failed = [c for c in checks if c["id"] in {"D4.RETRY", "D4.REOPEN", "D4.RESET"}
                  and c["status"] == "fail"]
        if failed:
            outcome_observations["lifecycle"] = {
                "value": 0, "evidence": sorted({ref for c in failed for ref in c["evidence"]}),
            }

    # Native completion caps are explicit fixed task rules. Preserve their total
    # by allocating any reduction over the positively credited checkpoints.
    raw = sum(c["score"] for c in checks if c["score"] is not None)
    capped = native.get("nonvisual_score")
    caps = native.get("triggered_score_caps", [])
    if (not infrastructure and status == "valid" and caps
            and type(capped) in (int, float) and math.isfinite(capped) and 0 <= capped < raw):
        positive = [c for c in checks if c["score"] is not None and c["score"] > 0]
        allocated = 0
        for i, c in enumerate(positive):
            points = round(capped - allocated, 6) if i == len(positive) - 1 else round(c["score"] * capped / raw, 6)
            c.update(score=points, status="partial" if points > 0 else "fail",
                     reason="Fixed functional completion cap: " + ", ".join(v["id"] for v in caps))
            allocated += points

    dimensions = {}
    for dim, maximum in MAXIMA.items():
        group = [c for c in checks if c["dimension"] == dim]
        complete = bool(group) and all(c["score"] is not None for c in group)
        dimensions[dim] = {
            "score": round(sum(c["score"] for c in group), 6) if complete else None,
            "max_score": maximum,
            "status": "complete" if complete else "invalid" if infrastructure and dim != "D6" else "not_run",
            "evidence": sorted(set(e for c in group for e in c["evidence"])),
        }
    return {
        "schema_version": "2.1", "sample_id": meta["sample_id"],
        "sample_version": meta["sample_version"], "evaluator_version": meta["evaluation"]["version"],
        "run_id": read(output / "evidence/binding.json")["run_id"],
        "evaluation_valid": False,
        "classification": "infrastructure_failure" if infrastructure else "incomplete",
        "coverage_status": "not_reviewed",
        "reason": reason or native.get("reason") or "Functional collection finished; D6 review is required.",
        "dimensions": dimensions, "checks": checks, "coverage_evidence": [],
        "final_score": None, "max_score": 100,
        "extensions": {"outcome_observations": outcome_observations, "native_status": status, "native_nonvisual_score": capped,
                       "raw_functional_score": round(raw, 6), "triggered_score_caps": caps},
    }
