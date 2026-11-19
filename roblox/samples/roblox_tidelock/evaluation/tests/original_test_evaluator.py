from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
import shutil
from pathlib import Path


EVALUATION = Path(__file__).resolve().parents[1]
ROOT = EVALUATION.parent
LUAU = Path(shutil.which('luau-compile') or 'luau-compile')


class EvaluatorTests(unittest.TestCase):
    def test_rule_totals_and_equal_checkpoint_formula(self) -> None:
        rules = json.loads((EVALUATION / "rules.json").read_text(encoding="utf-8"))
        self.assertEqual(sum(item["points"] for item in rules["dimensions"]), 100)
        expected = {"D1": (10, 5), "D2": (30, 10), "D3": (20, 10), "D4": (20, 6), "D5": (10, 5), "D6": (10, 1)}
        self.assertEqual(
            {item["id"]: (item["points"], len(item.get("checkpoints", ["visual"]))) for item in rules["dimensions"]},
            expected,
        )

    def test_budget_invariant(self) -> None:
        budget = json.loads((EVALUATION / "runtime" / "budget_plan.json").read_text(encoding="utf-8"))
        for session in budget["sessions"]:
            self.assertGreaterEqual(
                session["hard_watchdog_seconds"],
                session["declared_serial_worst_case_seconds"] + session["evaluator_render_log_evidence_margin_seconds"],
            )

    def test_generated_runner_compiles(self) -> None:
        runner = EVALUATION / "generated" / "tide_lock_formal_runner.client.luau"
        completed = subprocess.run([str(LUAU), "--null", str(runner)], capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr or completed.stdout)

    def test_policy_rejects_forbidden_actuation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bad = root / "bad.lua"
            bad.write_text('part:PivotTo(CFrame.new(100, 0, 0))\nremote:FireServer()\nplayer:SetAttribute("Win", true)\n', encoding="utf-8")
            report = root / "report.json"
            subprocess.run(
                [sys.executable, str(EVALUATION / "static_policy_check.py"), str(bad), "--output", str(report)],
                check=False,
                capture_output=True,
                text=True,
            )
            data = json.loads(report.read_text(encoding="utf-8"))
            self.assertFalse(data["passed"])
            categories = {item["category"] for item in data["findings"]}
            self.assertTrue({"teleport_or_direct_motion", "direct_business_call", "direct_state_mutation"} <= categories)

    def test_score_is_null_when_dynamic_is_unresolved(self) -> None:
        rules = json.loads((EVALUATION / "rules.json").read_text(encoding="utf-8"))
        static = json.loads((ROOT / "audit" / "static_results.json").read_text(encoding="utf-8"))
        dynamic_ids = [checkpoint for dimension in rules["dimensions"] if dimension["id"] in {"D2", "D3", "D4", "D5"} for checkpoint in dimension["checkpoints"]]
        dynamic = {
            "runner_status": "completed",
            "host_fault": None,
            "checkpoints": {checkpoint: {"status": "inconclusive", "detail": "fixture", "trace_ids": []} for checkpoint in dynamic_ids},
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            static_path, dynamic_path, output = root / "static.json", root / "dynamic.json", root / "score.json"
            static_path.write_text(json.dumps(static), encoding="utf-8")
            dynamic_path.write_text(json.dumps(dynamic), encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(EVALUATION / "score_evidence.py"), "--rules", str(EVALUATION / "rules.json"), "--static", str(static_path), "--dynamic", str(dynamic_path), "--output", str(output)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIsNone(json.loads(output.read_text(encoding="utf-8"))["official_score"])


if __name__ == "__main__":
    unittest.main()
