"""Synthetic emitter fixtures; these are not game or model evaluation records."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))
from format_score import emit


class EvidenceCompletionTests(unittest.TestCase):
    def make_evidence(self, folder, *, mismatch=False, infrastructure=None):
        rules = json.loads((BACKEND / "rules.json").read_text(encoding="utf-8"))
        rows = [{"id": r["id"], "state": "PASS",
                 "observations": [{"state": "PASS", "detail": "Synthetic serialization fixture"}]}
                for r in rules["leaves"]]
        (folder / "automatic-score.json").write_text(json.dumps({
            "leaves": rows, "infrastructure_error": infrastructure,
        }), encoding="utf-8")
        (folder / "checkpoint-evidence.json").write_text('{"synthetic_fixture":true}', encoding="utf-8")
        suite = ET.Element("test-suite")
        for index, row in enumerate(rows):
            ET.SubElement(suite, "test-case", name=row["id"],
                          result="Failed" if mismatch and index == 0 else "Passed")
        ET.ElementTree(suite).write(folder / "nunit.xml", encoding="utf-8")
        (folder / "visual-fixture.json").write_text('{"synthetic_fixture":true}', encoding="utf-8")
        return {"score": 6.5, "evidence": ["visual-fixture.json"]}

    def test_fresh_complete_evidence_does_not_require_a_retained_run_summary(self):
        self.assertFalse((BACKEND / "qualification.json").exists())
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            visual = self.make_evidence(out)
            result = emit(BACKEND, out, visual=visual, run_id="synthetic-completion")
            self.assertTrue(result["evaluation_valid"])
            self.assertEqual(result["schema_version"], "2.1")
            self.assertEqual(result["coverage_status"], "not_reviewed")
            self.assertAlmostEqual(result["final_score"], 96.5, places=6)

    def test_missing_visual_keeps_total_and_d6_null(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            self.make_evidence(out)
            result = emit(BACKEND, out, run_id="synthetic-no-visual")
            self.assertFalse(result["evaluation_valid"])
            self.assertIsNone(result["dimensions"]["D6"]["score"])
            self.assertIsNone(result["final_score"])

    def test_mismatched_nunit_cannot_produce_a_final_score(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            visual = self.make_evidence(out, mismatch=True)
            result = emit(BACKEND, out, visual=visual, run_id="synthetic-mismatch")
            self.assertFalse(result["evaluation_valid"])
            self.assertIsNone(result["final_score"])

    def test_infrastructure_failure_cannot_produce_a_final_score(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            visual = self.make_evidence(out, infrastructure="Synthetic provider failure")
            result = emit(BACKEND, out, visual=visual, run_id="synthetic-infrastructure")
            self.assertFalse(result["evaluation_valid"])
            self.assertEqual(result["classification"], "infrastructure_failure")
            self.assertIsNone(result["final_score"])


if __name__ == "__main__":
    unittest.main()
