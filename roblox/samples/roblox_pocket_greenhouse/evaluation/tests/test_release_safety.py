"""Synthetic packaging regression tests; these are not gameplay/model results."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

EVALUATION = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(EVALUATION / "src"))
from visual_binding import candidate_digest, sha, validate_visual


class ReleaseSafetyTests(unittest.TestCase):
    def runtime(self):
        path = EVALUATION / "src/collection_runtime.py"
        if not path.exists():
            self.skipTest("Tide Lock retains its independent native exporter")
        spec = importlib.util.spec_from_file_location("collection_runtime", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_candidate_supplied_score_is_not_native_report(self):
        runtime = self.runtime()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = {"dimensions": {"D1": {"score": 10}}}
            for name in ["candidate", "submission", "unpacked", "source", "transport"]:
                (root / name).mkdir()
                (root / name / "score.json").write_text(json.dumps(payload), encoding="utf-8")
            self.assertEqual(runtime.find_report(root), (None, {}))
            (root / "evidence").mkdir()
            report = root / "evidence/score.json"
            report.write_text(json.dumps(payload), encoding="utf-8")
            self.assertEqual(runtime.find_report(root)[0], report)

    def test_numbers_without_fresh_runtime_cannot_be_final(self):
        runtime = self.runtime()
        cfg = json.loads((EVALUATION / "src/native-config.json").read_text(encoding="utf-8"))
        raw = {"runner_valid": True, "dimensions": {d: {"score": m} for d, m in runtime.MAXIMA.items()}}
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            result = runtime.export(EVALUATION, out, raw, cfg, None, 10, runtime_completed=False)
            self.assertIsNone(result["final_score"])
            self.assertFalse(result["evaluation_valid"])

    def test_incomplete_native_run_cannot_be_promoted(self):
        runtime = self.runtime()
        cfg = json.loads((EVALUATION / "src/native-config.json").read_text(encoding="utf-8"))
        for fault in [{"runner_valid": False}, {"unresolved": ["d3.missing"]}, {"errors": ["runtime aborted"]}]:
            with tempfile.TemporaryDirectory() as directory:
                raw = {"runner_valid": True, "dimensions": {d: {"score": m} for d, m in runtime.MAXIMA.items()}, **fault}
                result = runtime.export(EVALUATION, Path(directory), raw, cfg, None, 10, runtime_completed=True)
                self.assertIsNone(result["final_score"])

    def test_complete_observations_do_not_require_private_qualification(self):
        runtime = self.runtime()
        cfg = json.loads((EVALUATION / "src/native-config.json").read_text(encoding="utf-8"))
        raw = {"runner_valid": True, "dimensions": {d: {"score": m} for d, m in runtime.MAXIMA.items()}}
        with tempfile.TemporaryDirectory() as directory:
            result = runtime.export(EVALUATION, Path(directory), raw, cfg, None, 8, runtime_completed=True)
            self.assertEqual(result["schema_version"], "2.1")
            self.assertEqual(result["coverage_status"], "not_reviewed")
            self.assertEqual(result["final_score"], 98)

    def test_visual_numbers_without_binding_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            visual = root / "visual.json"
            visual.write_text('{"round_scores":[10,10,10],"final_score":10}', encoding="utf-8")
            candidate = root / "candidate.zip"
            candidate.write_bytes(b"synthetic-candidate")
            with self.assertRaises(ValueError):
                validate_visual(visual, EVALUATION, candidate, root / "out")

    def test_visual_hash_candidate_and_response_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / "candidate.zip"
            candidate.write_bytes(b"synthetic-candidate")
            protocol = json.loads((EVALUATION / "d6/protocol.json").read_text(encoding="utf-8"))
            binding = {
                "candidate_sha256": candidate_digest(candidate),
                "prompt_sha256": sha(EVALUATION / "d6" / protocol["prompt"]),
                "reference_sha256": sha(EVALUATION / "d6" / protocol["reference_image"]["path"]),
                "reviewer_model": protocol["reviewer_model"],
            }
            images = []
            for index in range(4):
                path = root / ("synthetic-state-" + str(index) + ".png")
                path.write_bytes(b"\x89PNG\r\n\x1a\n" + bytes([index]))
                images.append({"path": path.name, "sha256": sha(path)})
            responses = []
            for index in range(3):
                path = root / ("synthetic-answer-" + str(index) + ".json")
                path.write_text(json.dumps({
                    "response_id": "synthetic-unit-test-" + str(index), "model": protocol["reviewer_model"],
                    "criteria": [1, 1, 1, 1, 1], "binding": binding,
                    "image_sha256": [item["sha256"] for item in images],
                }), encoding="utf-8")
                responses.append({"path": path.name, "sha256": sha(path)})
            value = {"binding": binding, "round_scores": [5, 5, 5], "final_score": 5,
                     "screenshots": images, "responses": responses}
            visual = root / "visual.json"
            visual.write_text(json.dumps(value), encoding="utf-8")
            self.assertEqual(validate_visual(visual, EVALUATION, candidate, root / "out")["final_score"], 5)
            candidate.write_bytes(b"different-candidate")
            with self.assertRaises(ValueError):
                validate_visual(visual, EVALUATION, candidate, root / "out2")
            candidate.write_bytes(b"synthetic-candidate")
            (root / responses[0]["path"]).write_text("{}", encoding="utf-8")
            with self.assertRaises(ValueError):
                validate_visual(visual, EVALUATION, candidate, root / "out3")


if __name__ == "__main__":
    unittest.main()
