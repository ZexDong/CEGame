"""Dependency-closed canonical score/v2 emission; never invents observations."""
import argparse
import hashlib
import json
import math
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

MAXIMA = {"D1": 10, "D2": 30, "D3": 20, "D4": 20, "D5": 10, "D6": 10}
STATES = {"PASS": "pass", "FAIL_OBSERVED": "fail",
          "BLOCKED_BY_PRODUCT": "blocked_by_candidate",
          "INCONCLUSIVE_EVALUATOR": "inconclusive_evaluator"}

def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def observation_state(row):
    # A deliberately unselected diagnostic case has no observation.  It is
    # not an evaluator failure and must never become an invented zero.
    if row["state"] == "INCONCLUSIVE_EVALUATOR" and not row["observations"]:
        return "not_run"
    return STATES[row["state"]]

def emit(ev, out, visual=None, run_id=None):
    from session_core import evaluator_digest
    auto = load(out / "automatic-score.json")
    rules = load(ev / "rules.json")
    definitions = {r["id"]: r for r in rules["leaves"]}
    observations = {r["id"]: r for r in auto["leaves"]}
    if set(definitions) != set(observations) or len(observations) != len(auto["leaves"]):
        raise ValueError("Missing/duplicate automatic leaves")
    checks = []
    for key, rule in definitions.items():
        row = observations[key]
        state = observation_state(row)
        failed = [o for o in row["observations"] if o["state"] != "PASS"]
        blockers = []
        if state == "blocked_by_candidate":
            blockers = sorted({parent for o in failed for parent in o.get("blocked_by", [])})
            if not blockers:
                blockers = [i for i in ["d1.import", "d1.scene"] if observations[i]["state"] == "FAIL_OBSERVED"]
            if not blockers:
                raise ValueError("A product-blocked leaf has no directly evidenced blocker: " + key)
        checks.append(dict(
            id=key, requirement_ids=rule["requirement_ids"], dimension=rule["dimension"],
            max_score=rule["max_score"],
            score=rule["max_score"] if state == "pass" else None if state in ["inconclusive_evaluator", "not_run"] else 0,
            status=state, blocked_by=blockers,
            reason=("\n".join(dict.fromkeys(o["detail"] for o in failed)) if failed else
                    "Diagnostic subset: this checkpoint was not executed." if state == "not_run" else ""),
            evidence=["checkpoint-evidence.json#" + key] if row["observations"] else []))
    visual_check = dict(id="d6.presentation", requirement_ids=[rules["visual_requirement_id"]],
        dimension="D6", max_score=10, score=None, status="not_run", reason="Visual review not yet merged.",
        blocked_by=[], evidence=[])
    if visual:
        visual_check.update(score=visual["score"],
            status="pass" if visual["score"] == 10 else "fail" if visual["score"] == 0 else "partial",
            reason="Frozen single-state/single-round visual rubric; not a whole-game visual or usability test.",
            evidence=visual["evidence"])
    checks.append(visual_check)
    dimensions = {}
    for dimension, maximum in MAXIMA.items():
        rows = [c for c in checks if c["dimension"] == dimension]
        complete = all(c["score"] is not None for c in rows)
        dimensions[dimension] = dict(
            score=round(sum(c["score"] for c in rows), 6) if complete else None,
            max_score=maximum, status="complete" if complete else "incomplete",
            evidence=sorted({e for c in rows for e in c["evidence"]}))
    complete = all(d["status"] == "complete" for d in dimensions.values())
    nunit = out / "nunit.xml"
    bridge_complete = False
    if nunit.exists():
        cases = list(ET.parse(nunit).getroot().iter("test-case"))
        ids = [c.get("name") for c in cases]
        bridge_complete = len(ids) == len(definitions) and set(ids) == set(definitions)
        for row in cases:
            state = observations[row.get("name")]["state"]
            expected = "Passed" if state == "PASS" else "Inconclusive" if state == "INCONCLUSIVE_EVALUATOR" else "Failed"
            if row.get("result") != expected:
                bridge_complete = False
    final = bool(complete and bridge_complete and not auto["infrastructure_error"])
    coverage_evidence = []
    if final:
        shutil.copyfile(ev / "coverage.json", out / "coverage-used.json")
        shutil.copyfile(ev / "rules.json", out / "rules-used.json")
        coverage_evidence = ["coverage-used.json", "rules-used.json", "evaluator-used.json"]
        (out / "evaluator-used.json").write_text(json.dumps(evaluator_digest(ev), indent=2), encoding="utf-8")
    candidate_failure = any(c["status"] in ["fail", "blocked_by_candidate"]
                            for c in checks if c["dimension"] != "D6")
    result = dict(
        schema_version="2.1", sample_id=rules["sample_id"], sample_version="1.0.0",
        evaluator_version=rules["evaluator_version"], run_id=run_id or (
            out.parent.name if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]*", out.parent.name)
            else "run-" + hashlib.sha256(str(out).encode()).hexdigest()[:16]),
        evaluation_valid=final,
        classification=("candidate_failure" if candidate_failure else "scored") if final else
            "infrastructure_failure" if auto["infrastructure_error"] else "incomplete",
        coverage_status="not_reviewed",
        reason=("Observed candidate defects; fixed-denominator score, with interface-blocked and observed failures separated."
                if candidate_failure else "") if final else
            auto["infrastructure_error"] or "Complete automatic evidence, matching NUnit results, and D6 are required.",
        dimensions=dimensions, checks=checks, coverage_evidence=coverage_evidence,
        final_score=round(sum(d["score"] for d in dimensions.values()), 6) if final else None,
        max_score=100,
        extensions=dict(
            automatic_evidence="automatic-score.json",
            automatic_score_sha256=sha(out / "automatic-score.json"),
            blocked_by_candidate_weight=round(sum(c["max_score"] for c in checks if c["status"] == "blocked_by_candidate"), 6),
            observed_failure_weight=round(sum(c["max_score"] for c in checks if c["status"] == "fail" and c["dimension"] != "D6"), 6),
            visual_review_reused=bool(visual and visual.get("reused")),
            limits=["Each result binds the actual candidate and evaluator files from this execution.",
                    "D6 uses the predeclared single main-play image and one review, not full visual coverage.",
                    "The complete six-dimensional result requires every frozen checkpoint to have evidence."]))
    from validate_score import validate
    validate(result, out, require_final=final, check_evidence=True)
    (out / "score.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evaluation", required=True, type=Path)
    args = parser.parse_args()
    out = args.evaluation.resolve()
    visual = None
    if (out / "d6.json").exists():
        review = load(out / "d6.json")
        visual = dict(score=review["score"], evidence=["d6.json", "main-play.png", "d6-response.json"], reused=False)
    result = emit(Path(__file__).resolve().parent, out, visual)
    print(json.dumps(result["dimensions"]))
    raise SystemExit(0 if result["evaluation_valid"] else 2 if result["classification"] == "infrastructure_failure" else 3)

if __name__ == "__main__":
    main()
