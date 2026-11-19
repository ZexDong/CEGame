"""Public entry and evidence-integrity tests; no editor or API is required."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

EVALUATION = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVALUATION / "src"))
sys.path.insert(0, str(EVALUATION))


class PublicEntryTests(unittest.TestCase):
    def test_missing_environment_is_not_a_candidate_score(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / "candidate"
            candidate.mkdir()
            (candidate / "project.godot").write_text("config_version=5\n", encoding="utf-8")
            out = root / "out"
            process = subprocess.run([
                sys.executable, "-B", str(EVALUATION / "evaluate.py"),
                "--project", str(candidate), "--output", str(out),
                "--godot", str(root / "missing-godot.exe"),
            ], capture_output=True, text=True)
            self.assertEqual(process.returncode, 2, process.stderr)
            result = json.loads((out / "score.json").read_text(encoding="utf-8"))
            self.assertEqual(result["classification"], "infrastructure_failure")
            self.assertIsNone(result["final_score"])
            self.assertTrue(all(row["score"] is None for row in result["dimensions"].values()))
            from validate_score import validate
            validate(result, out, check_evidence=True)

    def test_rule_weights_and_requirement_coverage(self):
        rules = json.loads((EVALUATION / "rules.json").read_text(encoding="utf-8"))
        for dim, maximum in rules["dimensions"].items():
            self.assertAlmostEqual(sum(c["max_score"] for c in rules["checks"]
                                       if c["dimension"] == dim), maximum, places=6)
        ids = [c["id"] for c in rules["checks"]]
        self.assertEqual(len(ids), len(set(ids)))
        coverage = json.loads((EVALUATION / "coverage.json").read_text(encoding="utf-8"))["rows"]
        self.assertEqual({r["source"] for r in coverage},
                         {k for r in rules["checks"] for k in r["requirement_ids"]})

    def test_review_must_be_bound_to_current_collection(self):
        from runtime import inside
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                inside(Path(directory), "../outside.json")


if __name__ == "__main__":
    unittest.main()
