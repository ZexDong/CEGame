"""Apply an audited predicate replay to the same retained run, without new scoring."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reconcile(root, replay_name):
    replay_path = root / replay_name
    replay = json.loads(replay_path.read_text(encoding="utf-8-sig"))
    assert replay["trace_sha256"] == digest(root / "receipts/atomic-live-traces.json")
    expected = {"D2-08", "D2-10", "D2-13", "D3-03", "D3-04", "D3-05", "D3-07", "D4-02"}
    assert {r["checkpoint_id"] for r in replay["results"]} == expected
    assert all(r["verdict"] in ("pass", "fail", "unreachable") and r["measurements"]["collection_complete"] for r in replay["results"])
    path = root / "verdicts.json"
    run = json.loads(path.read_text(encoding="utf-8-sig"))
    assert run["run_status"] == "completed" and not run["faults"]
    original = root / "verdicts-before-semantic-replay.json"
    assert not original.exists()
    original.write_bytes(path.read_bytes())
    changes = []
    for result in replay["results"]:
        item = next(c for c in run["checkpoints"] if c["checkpoint_id"] == result["checkpoint_id"])
        old = {k: item[k] for k in ("verdict", "reason_code", "detail")}
        passed = result["verdict"] == "pass"
        item.update(verdict=result["verdict"], reason_code=None if passed else result["reason_code"],
                    detail=result["detail"], attribution=None if passed else "candidate",
                    first_failure=None if passed else replay_name,
                    score_impact="full_credit" if passed else "checkpoint_zero")
        item["evidence"] = sorted(set(item["evidence"] + [replay_name]))
        new = {k: item[k] for k in old}
        if new != old:
            changes.append({"checkpoint_id": item["checkpoint_id"], "before": old, "after": new})
    groups = defaultdict(list)
    for item in run["checkpoints"]:
        if item["verdict"] != "pass":
            groups[item["reason_code"]].append(item)
    run["candidate_failures"] = [{"reason_code": code, "attribution": "candidate", "first_failure": checks[0]["first_failure"],
        "affected_checkpoints": [c["checkpoint_id"] for c in checks], "score_impact": "checkpoint_zero",
        "evidence": sorted({p for c in checks for p in c["evidence"]})} for code, checks in groups.items()]
    path.write_text(json.dumps(run, indent=2) + "\n", encoding="utf-8")
    receipt = {"version": "ar-predicate-reconciliation-1.0.0", "candidate_identity_sha256": run["candidate_identity_sha256"],
        "scope": "Nullable event references and equivalent observed round transitions; no event fabrication, new gameplay, checkpoint or weight change.",
        "original_verdicts_sha256": digest(original), "replay_sha256": digest(replay_path), "verdicts_sha256": digest(path), "changes": changes}
    (root / "predicate-reconciliation.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(changes))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", required=True, type=Path)
    parser.add_argument("--replay", default="accepted-predicate-replay.json")
    args = parser.parse_args()
    reconcile(args.run.resolve(), args.replay)
