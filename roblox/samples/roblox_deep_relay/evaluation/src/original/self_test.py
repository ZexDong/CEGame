#!/usr/bin/env python3
"""Deterministic scorer discipline tests; never launches Studio."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    rules = json.loads((root / "evaluation" / "rules.json").read_text(encoding="utf-8"))
    static = {"checkpoints": {}, "candidate_zip_sha256": "TEST"}
    dynamic = {"checkpoints": {}, "runner_status": "completed", "host_fault": None, "metadata": {"formal_valid": True}, "summary": {"executable": True, "solved": True}}
    for dimension in rules["dimensions"]:
        if dimension["id"] == "D6":
            continue
        target = static if dimension["id"] == "D1" else dynamic
        for checkpoint_id in dimension["checkpoints"]:
            target["checkpoints"][checkpoint_id] = {"status": "pass", "detail": "synthetic scorer test", "trace_ids": ["test-trace"]}
    with tempfile.TemporaryDirectory(prefix="deeprelay_score_test_") as temp_name:
        temp = Path(temp_name)
        static_path, dynamic_path, output = temp / "static.json", temp / "dynamic.json", temp / "score.json"
        static_path.write_text(json.dumps(static), encoding="utf-8")
        dynamic_path.write_text(json.dumps(dynamic), encoding="utf-8")
        completed = subprocess.run([
            sys.executable, str(root / "evaluation" / "score_evidence.py"),
            "--rules", str(root / "evaluation" / "rules.json"), "--static", str(static_path),
            "--dynamic", str(dynamic_path), "--output", str(output), "--allow-incomplete",
        ], capture_output=True, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stderr)
        score = json.loads(output.read_text(encoding="utf-8"))
        assert score["official_score"] is None, "D6 absence must keep official score null"
        assert score["provisional_subtotal"] == 90.0, "all-pass D1-D5 subtotal must be 90"
        assert "D6 visual evaluation not available" in score["unresolved"]

        # A genuinely broken candidate may fail every dynamic checkpoint. That
        # is a complete adjudication, not an evaluator-inconclusive run.
        for checkpoint in dynamic["checkpoints"].values():
            checkpoint["status"] = "fail"
            checkpoint["detail"] = "synthetic candidate bootstrap failure"
        dynamic_path.write_text(json.dumps(dynamic), encoding="utf-8")
        completed = subprocess.run([
            sys.executable, str(root / "evaluation" / "score_evidence.py"),
            "--rules", str(root / "evaluation" / "rules.json"), "--static", str(static_path),
            "--dynamic", str(dynamic_path), "--output", str(output), "--allow-incomplete",
        ], capture_output=True, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stderr)
        failed_score = json.loads(output.read_text(encoding="utf-8"))
        assert failed_score["provisional_subtotal"] == 10.0, "all dynamic FAIL must preserve only D1's 10 points"
        assert [item for item in failed_score["unresolved"] if item != "D6 visual evaluation not available"] == []

        dynamic["metadata"]["formal_valid"] = False
        dynamic_path.write_text(json.dumps(dynamic), encoding="utf-8")
        subprocess.run([
            sys.executable, str(root / "evaluation" / "score_evidence.py"),
            "--rules", str(root / "evaluation" / "rules.json"), "--static", str(static_path),
            "--dynamic", str(dynamic_path), "--output", str(output), "--allow-incomplete",
        ], check=True, capture_output=True, text=True)
        invalid_score = json.loads(output.read_text(encoding="utf-8"))
        assert invalid_score["runner_valid"] is False, "explicit evaluator-invalid metadata must fail closed"

        dynamic["metadata"]["formal_valid"] = True
        dynamic["evidence_contract_faults"] = ["synthetic missing trace"]
        dynamic_path.write_text(json.dumps(dynamic), encoding="utf-8")
        subprocess.run([
            sys.executable, str(root / "evaluation" / "score_evidence.py"),
            "--rules", str(root / "evaluation" / "rules.json"), "--static", str(static_path),
            "--dynamic", str(dynamic_path), "--output", str(output), "--allow-incomplete",
        ], check=True, capture_output=True, text=True)
        contract_score = json.loads(output.read_text(encoding="utf-8"))
        assert contract_score["runner_valid"] is False, "evidence contract faults must fail closed"

    formal_source = (root / "evaluation" / "runtime" / "formal_suite.lua").read_text(encoding="utf-8")
    generator_source = (root / "evaluation" / "generate_runtime.py").read_text(encoding="utf-8")
    bridge_source = (root / "evaluation" / "local_complete_eval.py").read_text(encoding="utf-8")
    assert "bootstrap_failure_snapshot" in formal_source, "bootstrap degradation path is missing"
    assert "Formal journey could not start because candidate never became ready" not in formal_source
    assert "DEEP_RELAY_TRACE_ANCHOR" in generator_source, "compact trace anchor is missing"
    assert "missing trace records" in bridge_source and "no complete engine-state trace" in bridge_source, "trace-reference closure check is missing"
    print(json.dumps({"passed": True, "checks": ["D6 fail-closed", "D1-D5 subtotal", "official score null", "all-dynamic-fail adjudication", "explicit invalid metadata", "evidence fault fail-closed", "bootstrap degradation path", "trace anchor", "evidence reference closure"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
