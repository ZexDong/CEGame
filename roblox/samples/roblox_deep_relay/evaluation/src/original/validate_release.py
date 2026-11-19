#!/usr/bin/env python3
"""Fail-closed release checks for scoring, budgets, inputs and evaluator source."""

from __future__ import annotations

import hashlib
import json
import py_compile
import subprocess
import sys
from pathlib import Path


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    rules = json.loads((root / "evaluation" / "rules.json").read_text(encoding="utf-8"))
    budget = json.loads((root / "evaluation" / "runtime" / "budget_plan.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "candidate" / "candidate_manifest.json").read_text(encoding="utf-8"))
    problems: list[str] = []

    if sum(item["points"] for item in rules["dimensions"]) != 100:
        problems.append("dimension points do not sum to 100")
    expected = {"D1": 10, "D2": 30, "D3": 20, "D4": 20, "D5": 10, "D6": 10}
    if {item["id"]: item["points"] for item in rules["dimensions"]} != expected:
        problems.append("D1-D6 weights differ from the frozen guide")
    ids = [checkpoint for item in rules["dimensions"] for checkpoint in item["checkpoints"]]
    if len(ids) != len(set(ids)):
        problems.append("duplicate scoring checkpoint IDs")
    if "d4.reopen_clean_session" not in ids:
        problems.append("clean Reopen checkpoint missing")

    for session in budget["sessions"]:
        required = session["declared_serial_worst_case_seconds"] + session["evaluator_render_evidence_margin_seconds"]
        if session["hard_watchdog_seconds"] < required:
            problems.append(f"watchdog invariant failed for {session['id']}")
        if session["watchdog_headroom_seconds"] != session["hard_watchdog_seconds"] - session["declared_serial_worst_case_seconds"]:
            problems.append(f"watchdog headroom mismatch for {session['id']}")

    for key in ("delivered_place", "source_package"):
        record = manifest[key]
        path = root / record["path"]
        if not path.is_file() or sha(path) != record["sha256"]:
            problems.append(f"candidate manifest mismatch: {key}")

    for script in (root / "evaluation").glob("*.py"):
        try:
            py_compile.compile(str(script), doraise=True)
        except py_compile.PyCompileError as error:
            problems.append(str(error))

    formal_source = (root / "evaluation" / "runtime" / "formal_suite.lua").read_text(encoding="utf-8")
    reopen_source = (root / "evaluation" / "runtime" / "reopen_suite.lua").read_text(encoding="utf-8")
    for label, source in (("formal", formal_source), ("reopen", reopen_source)):
        if "d:trace(\"bootstrap_failure_snapshot\",\"observed\",degraded)" in source or "d:trace(\"reopen_bootstrap_failure\",\"observed\",snapshot)" in source:
            problems.append(f"{label} suite emits an unbounded bootstrap snapshot")

    generated = root / "evaluation" / "generated"
    generated.mkdir(parents=True, exist_ok=True)
    generator = root / "evaluation" / "generate_runtime.py"
    for mode in ("formal", "reopen"):
        runner = generated / f"deep_relay_{mode}_runner.client.luau"
        result = subprocess.run([sys.executable, str(generator), "--runtime-dir", str(root / "evaluation" / "runtime"), "--output", str(runner), "--mode", mode], capture_output=True, text=True)
        if result.returncode:
            problems.append(f"runtime generation failed: {mode}: {result.stderr[-500:]}")
        else:
            compiled = subprocess.run([str(root / "tools" / "luau-compile.exe"), str(runner)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            if compiled.returncode:
                problems.append(f"generated Luau compile failed: {mode}: {compiled.stderr[-500:]}")

    report = {"schema_version": "deep-relay-release-validation-v1", "passed": not problems, "problems": problems}
    output = root / "audit" / "release_validation.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0 if not problems else 2


if __name__ == "__main__":
    raise SystemExit(main())
