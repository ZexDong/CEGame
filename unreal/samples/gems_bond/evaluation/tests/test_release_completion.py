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
    def test_native_visual_evidence_preserves_the_journey_gate(self):
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
            records = [{"id": row["id"].removeprefix("D6-"), "round": round_id, "score": 10}
                       for row in rules if row["dimension"] == "D6" for round_id in [1, 2, 3]]
            # An unrelated file left from a preceding review must never enter this run.
            (out / "native/d6-result.json").write_text(json.dumps({"records": records}))
            summary = out / "native/score.json"
            summary.write_text(json.dumps({"status": "complete"}))
            unbound = adapter.convert_result(ROOT, out, meta, "Unbound visual result")
            self.assertIsNone(unbound["dimensions"]["D6"]["score"])
            summary.write_text(json.dumps({"status": "complete", "d6_results": records}))
            result = adapter.convert_result(ROOT, out, meta, "Synthetic completion test")
            spec = importlib.util.spec_from_file_location("validator", ROOT / "validate_score.py")
            validator = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(validator)
            validator.apply_scorecard(result)
            validator.validate(result, out, check_evidence=True)
            self.assertEqual(result["dimensions"]["D6"]["score"], 10)
            self.assertIsNone(result["final_score"])
            self.assertIsNone(result["extensions"]["scorecard"]["J"])
            if meta["sample_id"] == "action_roguelike":
                journey = next(c for c in result["checks"] if c["id"] == "D4-01")
                self.assertEqual(journey["status"], "inconclusive_evaluator")
            for row in rules:
                native = row.get("native_definition", {})
                if native.get("visible_review_required") or native.get("runtime_picture_review_required"):
                    self.assertIsNone(next(c["score"] for c in result["checks"] if c["id"] == row["id"]))

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
