"""Offline evidence, format and failure-attribution regressions."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
EVALUATION = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVALUATION / "src"))
sys.path.insert(0, str(EVALUATION))
from score_adapter import catalog, convert, normalized_weights
from validate_score import validate
from visual_review import CRITERIA, apply_review, capture_inventory, reference_binding


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


class ReleaseAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="defold-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        self.meta = json.loads((EVALUATION.parent / "sample.json").read_text(encoding="utf-8"))
        self.rules = json.loads((EVALUATION / "rules.json").read_text(encoding="utf-8"))
        self.rows = catalog(self.rules)
        write(self.output / "evidence/binding.json", {
            "run_id": "synthetic-unit-test", "candidate_sha256": "unit-test",
            "references": reference_binding(EVALUATION.parent),
        })

    def native_fixture(self, caps=None):
        if "trajectories" in self.rules:
            static = [{"id": c["id"], "status": "pass"} for c in self.rows if c["dimension"] == "D1"]
            dynamic = [{"id": c["id"], "dim": c["dimension"], "status": "pass"}
                       for c in self.rows if c["dimension"] != "D1"]
            write(self.output / "native/d1/d1-report.json", {"evaluation_status": "valid", "checks": static})
            write(self.output / "native/checkpoint/checkpoint-report.json",
                  {"evaluation_status": "valid", "checks": dynamic})
            report = {"evaluation_status": "valid", "nonvisual_score": 50 if caps else 90,
                      "triggered_score_caps": caps or []}
        else:
            report = {"evaluation_status": "valid", "nonvisual_score": 90,
                      "checks": [{"id": c["id"], "verdict": "pass", "reason": "unit fixture"}
                                 for c in self.rows]}
        write(self.output / "native/score.json", report)
        return convert(EVALUATION, self.output, self.meta)

    def test_fixed_weight_normalization(self):
        weights = normalized_weights(self.rows)
        for dim, maximum in {"D1": 10, "D2": 30, "D3": 20, "D4": 20, "D5": 10}.items():
            self.assertAlmostEqual(maximum, sum(weights[c["id"]] for c in self.rows if c["dimension"] == dim), places=6)

    def test_missing_visual_evidence_never_creates_total(self):
        result = self.native_fixture()
        validate(result, self.output, check_evidence=True)
        self.assertIsNone(result["final_score"])
        self.assertFalse(result["evaluation_valid"])
        self.assertIsNone(result["dimensions"]["D6"]["score"])

    def test_infrastructure_failure_is_null_not_candidate_zero(self):
        result = convert(EVALUATION, self.output, self.meta, "unit-test host failure", True)
        validate(result, self.output, check_evidence=True)
        self.assertEqual("infrastructure_failure", result["classification"])
        self.assertTrue(all(v["score"] is None for v in result["dimensions"].values()))

    def test_declared_native_cap_preserves_aggregate(self):
        if "trajectories" not in self.rules:
            self.skipTest("This native scorer has no completion-cap format.")
        result = self.native_fixture([{"id": "unit-cap", "max_nonvisual_score": 50}])
        validate(result, self.output, check_evidence=True)
        self.assertAlmostEqual(50, sum(v["score"] for v in result["dimensions"].values() if v["score"] is not None), places=6)

    def test_duplicate_native_fail_does_not_earn_repeated_credit(self):
        if "trajectories" not in self.rules:
            self.skipTest("Conjunctive checkpoint runtime only.")
        self.native_fixture()
        path = self.output / "native/checkpoint/checkpoint-report.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        report["checks"].append({**report["checks"][0], "status": "fail", "detail": "unit-test defect"})
        write(path, report)
        result = convert(EVALUATION, self.output, self.meta)
        row = next(c for c in result["checks"] if c["id"] == report["checks"][0]["id"])
        self.assertEqual(0, row["score"])
        self.assertEqual("fail", row["status"])

    def review_fixture(self):
        result = self.native_fixture()
        binding = json.loads((self.output / "evidence/binding.json").read_text(encoding="utf-8"))
        protocol = json.loads((EVALUATION / "d6/protocol.json").read_text(encoding="utf-8"))
        review = {"candidate_sha256": binding["candidate_sha256"],
                  "reference_hashes": binding["references"], "model": protocol["judge_model"],
                  "settings": protocol["judge_settings"], "states": {}, "rounds": []}
        for i, state in enumerate(protocol["states"]):
            # Synthetic evidence used only to test binding/aggregation, never published as a run.
            image = self.output / f"native/playtest/captures/unit-{i}.png"
            image.parent.mkdir(parents=True, exist_ok=True)
            image.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\0" * 8 + (4).to_bytes(4, "big") * 2 + bytes([i]))
            review["states"][state] = {"image": image.relative_to(self.output).as_posix(),
                                       "sha256": hashlib.sha256(image.read_bytes()).hexdigest()}
        write(self.output / "evidence/visual-captures.json", capture_inventory(self.output))
        for number, points in enumerate((0, 1, 2)):
            round_ = {}
            for state, image in review["states"].items():
                request = f"unit-{number}-{state}"
                raw = self.output / f"unit-responses/{request}.json"
                write(raw, {"request_id": request, "model": review["model"], "state": state,
                            "candidate_sha256": binding["candidate_sha256"],
                            "image_sha256": image["sha256"], "reference_hashes": binding["references"],
                            "scores": {key: points for key in CRITERIA}, "rationale": "synthetic unit fixture",
                            "raw_provider_response": {"synthetic_test_fixture": True}})
                round_[state] = {"request_id": request, "raw_response": raw.relative_to(self.output).as_posix(),
                                 "raw_response_sha256": hashlib.sha256(raw.read_bytes()).hexdigest()}
            review["rounds"].append(round_)
        path = self.output / "unit-review.json"
        write(path, review)
        return result, review, path

    def test_visual_review_uses_median_and_sum_of_six_dimensions(self):
        result, _, path = self.review_fixture()
        apply_review(result, path, EVALUATION.parent, self.output)
        validate(result, self.output, require_final=True, check_evidence=True)
        self.assertAlmostEqual(5, result["dimensions"]["D6"]["score"], places=5)
        self.assertAlmostEqual(95, result["final_score"], places=5)

    def test_visual_review_rejects_changed_image(self):
        result, review, path = self.review_fixture()
        image = self.output / next(iter(review["states"].values()))["image"]
        image.write_bytes(image.read_bytes() + b"modified")
        with self.assertRaisesRegex(ValueError, "changed"):
            apply_review(result, path, EVALUATION.parent, self.output)

    def test_visual_review_rejects_reused_provider_response(self):
        result, review, path = self.review_fixture()
        first_state = next(iter(review["states"]))
        review["rounds"][1][first_state] = copy.deepcopy(review["rounds"][0][first_state])
        write(path, review)
        with self.assertRaisesRegex(ValueError, "unique request"):
            apply_review(result, path, EVALUATION.parent, self.output)

    def test_output_template_has_no_observations(self):
        data = json.loads((EVALUATION / "output-template/score.json").read_text(encoding="utf-8"))
        validate(data, require_final=False)
        self.assertEqual("not_run", data["classification"])
        self.assertTrue(all(v["score"] is None for v in data["dimensions"].values()))

if __name__ == "__main__":
    unittest.main()
