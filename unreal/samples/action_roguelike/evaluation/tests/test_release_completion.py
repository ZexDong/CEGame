"""Synthetic serialization regressions; no editor or game is executed here."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("score_adapter", ROOT / "src/score_adapter.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class CompletionTests(unittest.TestCase):
    def test_complete_run_is_not_permanently_blocked_by_historical_labels(self):
        rules = json.loads((ROOT / "rules.json").read_text(encoding="utf-8"))["checks"]
        meta = json.loads((ROOT.parent / "sample.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / "native").mkdir()
            (out / "evidence").mkdir()
            (out / "evidence/entry.json").write_text("{}")
            (out / "evidence/finalize.json").write_text(json.dumps({"returncode": 0, "started_ns": 0}))
            checks = {row["id"]: {"verdict": "pass", "reason": "Synthetic converter test"}
                      for row in rules if row["dimension"] != "D6"}
            (out / "native/checks.json").write_text(json.dumps(checks))
            (out / "native/native-summary.json").write_text('{"status":"complete"}')
            records = [{"id": row["id"].removeprefix("D6-"), "round": round_id, "score": 10}
                       for row in rules if row["dimension"] == "D6" for round_id in [1, 2, 3]]
            (out / "native/d6-result.json").write_text(json.dumps({"status": "complete", "records": records}))
            result = adapter.convert_result(ROOT, out, meta, "Synthetic completion test")
            if meta["sample_id"] == "action_roguelike":
                journey = next(c for c in result["checks"] if c["id"] == "D4-01")
                self.assertEqual(journey["status"], "inconclusive_evaluator")
                self.assertIsNone(result["final_score"])
                return
            self.assertTrue(result["evaluation_valid"])
            self.assertAlmostEqual(result["final_score"], 100, places=6)
            spec = importlib.util.spec_from_file_location("validator", ROOT / "validate_score.py")
            validator = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(validator)
            validator.validate(result, out, require_final=True, check_evidence=True)

    def test_checkpoint_pass_cannot_substitute_for_visual_review(self):
        rules = json.loads((ROOT / "rules.json").read_text(encoding="utf-8"))["checks"]
        meta = json.loads((ROOT.parent / "sample.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / "native").mkdir()
            (out / "evidence").mkdir()
            (out / "evidence/entry.json").write_text("{}")
            (out / "evidence/finalize.json").write_text(json.dumps({"returncode": 0, "started_ns": 0}))
            (out / "native/checks.json").write_text(json.dumps({
                "status": "complete",
                "checks": {row["id"]: {"verdict": "pass"} for row in rules},
            }))
            result = adapter.convert_result(ROOT, out, meta, "Synthetic missing-visual test")
            self.assertIsNone(result["dimensions"]["D6"]["score"])
            self.assertIsNone(result["final_score"])


if __name__ == "__main__":
    unittest.main()
