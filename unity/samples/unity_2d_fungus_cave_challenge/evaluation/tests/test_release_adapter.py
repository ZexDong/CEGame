"""Synthetic adapter tests; do not execute a game or claim calibration."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

E = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("public_unity_entry", E / "evaluate.py")
entry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(entry)


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.meta = json.loads((E.parent / "sample.json").read_text(encoding="utf-8-sig"))
        self.meta["coverage_status"] = "not_reviewed"

    def test_complete_native_observation_does_not_need_private_history(self):
        native = {"evaluation_valid": True,
                  "dimensions": {d: {"score": m} for d, m in entry.MAXIMA.items()}}
        result = entry.normalize(native, self.meta, "synthetic-native.json")
        self.assertTrue(result["evaluation_valid"])
        self.assertEqual(result["final_score"], 100)
        self.assertEqual(result["coverage_status"], "not_reviewed")

    def test_missing_visual_is_not_zero_or_full_credit(self):
        native = {"evaluation_valid": True,
                  "dimensions": {d: {"score": m} for d, m in entry.MAXIMA.items() if d != "D6"}}
        result = entry.normalize(native, self.meta, "synthetic-native.json")
        self.assertIsNone(result["dimensions"]["D6"]["score"])
        self.assertIsNone(result["final_score"])

    def test_invalid_run_cannot_be_promoted_by_numeric_dimensions(self):
        native = {"evaluation_valid": False,
                  "dimensions": {d: {"score": m} for d, m in entry.MAXIMA.items()}}
        result = entry.normalize(native, self.meta, "synthetic-native.json")
        self.assertFalse(result["evaluation_valid"])
        self.assertIsNone(result["final_score"])

    def test_imported_native_numbers_do_not_claim_fresh_game_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            native = root / "native.json"
            native.write_text(json.dumps({
                "evaluation_valid": True,
                "dimensions": {d: {"score": m} for d, m in entry.MAXIMA.items()},
            }), encoding="utf-8")
            out = root / "out"
            process = subprocess.run([
                sys.executable, "-B", str(E / "evaluate.py"),
                "--import-native", str(native), "--output", str(out),
            ], capture_output=True, text=True)
            self.assertEqual(process.returncode, 3, process.stderr)
            result = json.loads((out / "score.json").read_text(encoding="utf-8"))
            self.assertFalse(result["evaluation_valid"])
            self.assertIsNone(result["final_score"])
            self.assertIn("conversion", result["reason"])


if __name__ == "__main__":
    unittest.main()
