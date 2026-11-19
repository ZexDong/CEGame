#!/usr/bin/env python3
"""Run only Tide Lock routing adjudication and capture four D6 visual states."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import local_complete_eval as base


def main() -> int:
    task_root = Path(__file__).resolve().parents[1]
    evaluation = task_root / "evaluation"
    generated = evaluation / "generated"
    runner = generated / "tide_lock_two_item_supplement.client.luau"
    audit = generated / "two_item_supplement_policy_audit.json"

    formal_runs = sorted((task_root / "evidence").glob("formal_*/evidence.json"))
    if not formal_runs:
        raise RuntimeError("No completed formal evidence.json exists to supplement")
    source_formal = formal_runs[-1].parent

    subprocess.run(
        [
            sys.executable,
            str(evaluation / "generate_runtime.py"),
            "--runtime-dir", str(evaluation / "runtime"),
            "--suite-file", "two_item_supplement_suite.lua",
            "--entrypoint", "runTwoItemSupplement",
            "--evaluator-version", "tide-lock-v1.0-two-item-supplement",
            "--watchdog", "240",
            "--output", str(runner),
        ],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            str(evaluation / "static_policy_check.py"),
            str(runner),
            str(evaluation / "runtime" / "qa_observer.client.luau"),
            "--output", str(audit),
        ],
        check=True,
    )
    policy = json.loads(audit.read_text(encoding="utf-8"))
    if not policy.get("passed"):
        raise RuntimeError("Supplemental evaluator policy audit failed")

    qa = base.build_qa(task_root, runner)
    output = base.run_candidate(task_root, qa, runner, audit, 360, "supplemental")
    evidence_path = output / "evidence.json"
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    checkpoint = evidence.get("checkpoints", {}).get("d2.routing_system_usable", {})
    captures = evidence.get("visual_captures", [])

    manifest = {
        "schema_version": "tide-lock-two-item-supplement-v1",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_formal_evidence": str(source_formal),
        "supplemental_evidence": str(evidence_path),
        "candidate_project_zip_sha256": evidence.get("metadata", {}).get("candidate_project_zip_sha256"),
        "routing_adjudication": checkpoint,
        "d6": {
            "status": "captures_ready_for_three_round_visual_review" if len(captures) == 4 else "capture_incomplete",
            "method": "four fixed candidate states; same VLM; three complete rounds; arithmetic mean",
            "fixed_prompt": (
                "Score Tide Lock's visual assembly and presentation fidelity from 0 to 10 using all four fixed "
                "screenshots. Judge scene coherence and composition, material/lighting polish, gameplay readability, "
                "HUD legibility and visual feedback. Penalize obvious default-blockout appearance, clipping, empty "
                "space, inconsistent styling, and unreadable UI. Return one numeric score and a concise rationale."
            ),
            "captures": captures,
            "round_scores": None,
            "final_score": None,
        },
    }
    manifest_path = output / "two_item_adjudication.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print("\nTWO-ITEM SUPPLEMENT COMPLETE", flush=True)
    print(f"Routing: {str(checkpoint.get('status', 'missing')).upper()}", flush=True)
    print(f"D6 captures: {len(captures)}/4", flush=True)
    print(f"Evidence: {output}", flush=True)
    print(f"Adjudication manifest: {manifest_path}", flush=True)
    return 0 if checkpoint.get("status") in {"pass", "fail"} and len(captures) == 4 else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        if base.LAST_OUTPUT is not None:
            (base.LAST_OUTPUT / "bridge_error.txt").write_text(str(error) + "\n", encoding="utf-8")
        print(f"Supplement stopped: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)
