import argparse
import json
import math
import re
from pathlib import Path

MAXIMA = {"D1": 10, "D2": 30, "D3": 20, "D4": 20, "D5": 10, "D6": 10}
ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]*$")


def validate(data, output_root=None, require_final=False, check_evidence=False):
    def need(ok, message):
        if not ok:
            raise ValueError(message)

    def keys(obj, required, optional=()):
        need(isinstance(obj, dict), "Expected JSON object")
        need(set(required) <= obj.keys() <= set(required) | set(optional),
             "Missing/unknown fields: " + str(sorted(set(required) ^ obj.keys())))

    def number(value, maximum):
        need(type(value) in (int, float) and math.isfinite(value), "Expected finite number")
        need(0 <= value <= maximum, "Score outside fixed range")
        need(abs(value - round(value, 6)) < 1e-9, "Use at most six decimal places")

    def close(a, b):
        return abs(a - b) < 1e-6

    def ids(items, nonempty=False):
        need(isinstance(items, list), "Expected ID array")
        need(all(isinstance(v, str) and ID.fullmatch(v) for v in items), "Invalid ID")
        need(len(set(items)) == len(items) and (items or not nonempty), "Empty/duplicate IDs")

    def evidence(items, required=False):
        need(isinstance(items, list), "Expected evidence array")
        need(all(isinstance(v, str) and v for v in items), "Invalid evidence string")
        need(len(set(items)) == len(items) and (items or not required), "Empty/duplicate evidence")
        for value in items:
            file = value.split("#", 1)[0]
            need(file and not any(c in file for c in "\\:") and not file.startswith("/"),
                 "Evidence must be result-relative, using forward slashes")
            need(all(p not in ("", ".", "..") for p in file.split("/")),
                 "Evidence path cannot escape output")
            if check_evidence:
                need(output_root is not None, "Missing output root")
                root = Path(output_root).resolve()
                path = (root / file).resolve()
                need(root in path.parents and path.is_file(), "Missing/escaped evidence: " + file)

    keys(data, ["schema_version", "sample_id", "sample_version", "evaluator_version",
                "run_id", "evaluation_valid", "classification", "coverage_status",
                "reason", "dimensions", "checks", "coverage_evidence", "final_score",
                "max_score"], ["extensions"])
    need(data["schema_version"] in ("2.0", "2.1"), "Wrong schema version")
    for k in ["sample_id", "run_id"]:
        need(isinstance(data[k], str) and ID.fullmatch(data[k]), "Invalid " + k)
    for k in ["sample_version", "evaluator_version"]:
        need(isinstance(data[k], str) and bool(data[k].strip()), "Missing " + k)
    need(type(data["evaluation_valid"]) is bool, "evaluation_valid must be boolean")
    need(isinstance(data["reason"], str), "reason must be string")
    need(data["max_score"] == 100 and type(data["max_score"]) in (int, float), "Overall max must be 100")
    need(data["classification"] in ["scored", "candidate_failure", "incomplete",
                                  "infrastructure_failure", "not_run"], "Unknown classification")
    need(data["coverage_status"] in ["not_reviewed", "gaps_found", "qualified"], "Unknown coverage status")
    need("extensions" not in data or isinstance(data["extensions"], dict), "extensions must be object")
    final = data["classification"] in ["scored", "candidate_failure"]
    need(data["evaluation_valid"] == final, "Validity/classification mismatch")
    need(not require_final or final, "Not a final, valid score")
    evidence(data["coverage_evidence"])
    if final:
        if data["schema_version"] == "2.0":
            need(data["coverage_status"] == "qualified" and data["coverage_evidence"], "Legacy v2 qualification missing")
        number(data["final_score"], 100)
    else:
        need(data["final_score"] is None and data["reason"].strip(), "Non-final needs null total and reason")

    keys(data["dimensions"], list(MAXIMA))
    need(isinstance(data["checks"], list), "checks must be array")
    by_id = {}
    for item in data["checks"]:
        keys(item, ["id", "requirement_ids", "dimension", "max_score", "score",
                    "status", "reason", "blocked_by", "evidence"])
        need(isinstance(item["id"], str) and ID.fullmatch(item["id"]), "Invalid checkpoint ID")
        need(item["id"] not in by_id, "Duplicate checkpoint ID")
        by_id[item["id"]] = item
        ids(item["requirement_ids"], nonempty=True)
        ids(item["blocked_by"])
        need(item["dimension"] in MAXIMA, "Unknown dimension")
        number(item["max_score"], MAXIMA[item["dimension"]])
        need(item["max_score"] > 0, "Checkpoint weight must be positive")
        state = item["status"]
        need(state in ["pass", "partial", "fail", "blocked_by_candidate",
                       "inconclusive_evaluator", "not_run"], "Unknown check status")
        need(isinstance(item["reason"], str), "Checkpoint reason must be string")
        resolved = state not in ["inconclusive_evaluator", "not_run"]
        evidence(item["evidence"], required=resolved)
        if resolved:
            number(item["score"], item["max_score"])
            if state == "pass":
                need(close(item["score"], item["max_score"]), "Pass must award full weight")
            elif state == "partial":
                need(0 < item["score"] < item["max_score"] and item["reason"].strip(),
                     "Partial needs intermediate score and reason")
            else:
                need(item["score"] == 0 and item["reason"].strip(), "Failure needs zero and cause")
        else:
            need(item["score"] is None, "Unobserved score must be null, not zero")
            need(not final, "Final result contains unresolved checkpoint")
            if state == "inconclusive_evaluator":
                need(item["reason"].strip(), "Evaluator uncertainty needs a cause")
        need(bool(item["blocked_by"]) == (state == "blocked_by_candidate"), "Invalid blocked_by usage")

    for item in by_id.values():
        for blocker in item["blocked_by"]:
            need(blocker in by_id and blocker != item["id"], "Missing/self blocker")
            need(by_id[blocker]["status"] in ["fail", "blocked_by_candidate"], "Blocker is not candidate defect")
        seen = set()

        def visit(check):
            need(check not in seen, "Cyclic blocker dependencies")
            seen.add(check)
            for parent in by_id[check]["blocked_by"]:
                visit(parent)
            seen.remove(check)

        visit(item["id"])

    for dimension, maximum in MAXIMA.items():
        value = data["dimensions"][dimension]
        keys(value, ["score", "max_score", "status", "evidence"])
        need(type(value["max_score"]) in (int, float) and value["max_score"] == maximum,
             "Changed fixed dimension weight")
        state = value["status"]
        need(state in ["complete", "incomplete", "invalid", "not_run"], "Unknown dimension status")
        evidence(value["evidence"], required=state == "complete")
        items = [c for c in by_id.values() if c["dimension"] == dimension]
        if items:
            need(close(sum(c["max_score"] for c in items), maximum), "Checkpoint maxima do not sum to dimension")
        if state == "complete":
            number(value["score"], maximum)
            need(items and all(c["score"] is not None for c in items), "Complete dimension has missing checks")
            need(close(value["score"], round(sum(c["score"] for c in items), 6)), "Dimension sum mismatch")
        else:
            need(value["score"] is None and not final, "Incomplete/invalid dimension must have null score")
        if final:
            need(state == "complete", "Final result must complete every dimension")
    if final:
        expected = round(sum(v["score"] for v in data["dimensions"].values()), 6)
        need(close(data["final_score"], expected), "Overall is not D1-D6 sum")
    if data["classification"] == "candidate_failure":
        need(data["reason"].strip() and any(c["status"] in ["fail", "blocked_by_candidate"] for c in by_id.values()),
             "candidate_failure needs an evidenced candidate defect")
    if data["classification"] == "not_run":
        need(all(v["status"] == "not_run" for v in data["dimensions"].values())
             and all(c["status"] == "not_run" for c in by_id.values()), "not_run contains executed scores")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--score", required=True, type=Path)
    parser.add_argument("--require-final", action="store_true")
    parser.add_argument("--check-evidence", action="store_true")
    args = parser.parse_args()
    try:
        def reject_duplicates(pairs):
            out = {}
            for k, v in pairs:
                if k in out:
                    raise ValueError("Duplicate JSON key: " + k)
                out[k] = v
            return out

        def reject_nonfinite(value):
            raise ValueError("Non-JSON numeric constant: " + value)

        data = json.loads(args.score.read_text(encoding="utf-8-sig"),
                          object_pairs_hook=reject_duplicates, parse_constant=reject_nonfinite)
        validate(data, args.score.parent, args.require_final, args.check_evidence)
        print(json.dumps({"format_valid": True, "final_score_valid": data["evaluation_valid"]}))
    except (OSError, ValueError, TypeError, KeyError, RecursionError) as exc:
        print(json.dumps({"format_valid": False, "error": str(exc)}, ensure_ascii=False))
        raise SystemExit(2)


if __name__ == "__main__":
    main()
