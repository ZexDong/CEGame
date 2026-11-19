"""Small redistributable regression tests; no gameplay solution or private paths."""
import copy
import json
import sys
import unittest
import tempfile
from pathlib import Path
from types import SimpleNamespace

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from coverage_common import bounds_size, number_label
from session_core import Evaluation, ProductError, equivalent, nums, visible
from validate_score import validate, MAXIMA
from merge_score import verified_visual, sha
from format_score import observation_state

def rendered(value):
    return dict(ui=[dict(text=value, active=True, color=dict(a=1), shaderValid=True)])

class ObservationTests(unittest.TestCase):
    def test_expected_specification_is_not_candidate_controlled(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            ev, candidate = root / "evaluation", root / "candidate"
            (ev / "spec").mkdir(parents=True)
            candidate.mkdir()
            (ev / "rules.json").write_text(json.dumps(dict(game="glitch", leaves=[])), encoding="utf-8")
            for name, expected in [("CONTENT.json", dict(waves=[1, 2, 3])),
                                   ("SESSION_MODEL.json", dict(entries=["required"]))]:
                (ev / "spec" / name).write_text(json.dumps(expected), encoding="utf-8")
                (candidate / name).write_text(json.dumps(dict(candidate_lowered_requirements=True)), encoding="utf-8")
            value = Evaluation(ev, candidate, root / "out", "not-needed", bridge=False)
            self.assertEqual(value.content, dict(waves=[1, 2, 3]))
            self.assertEqual(value.model, dict(entries=["required"]))

    def test_float32_equivalence(self):
        self.assertTrue(equivalent(dict(x=2.55), dict(x=2.549999952316284)))
        self.assertFalse(equivalent(dict(x=2.55), dict(x=2.58)))

    def test_semantic_labels_and_icons(self):
        for display in ["Stars: 100", "★ 100", "100 stars", "<b>Stars 0100</b>"]:
            self.assertTrue(number_label(rendered(display), "stars", 100))
        self.assertTrue(number_label(rendered("52.1 SHD"), "shield", 52.13))
        self.assertFalse(number_label(rendered("Score 100, Stars 30"), "stars", 100))

    def test_precision_is_actual_display_precision(self):
        self.assertTrue(number_label(rendered("Time 1.2"), "time", 1.234))
        self.assertFalse(number_label(rendered("Time 1.20"), "time", 1.234))

    def test_invisible_text_cannot_pass(self):
        reply = rendered("Stars 100")
        reply["ui"][0]["shaderValid"] = False
        self.assertFalse(number_label(reply, "stars", 100))
        reply["ui"][0]["shaderValid"] = True
        reply["ui"][0]["color"]["a"] = 0
        self.assertFalse(number_label(reply, "stars", 100))

    def test_real_rendering_not_only_report(self):
        reply = dict(actors=[dict(id="x", active=True, onScreen=True, renderers=0, graphics=[])])
        self.assertFalse(visible(reply, "x"))
        reply["actors"][0]["renderers"] = 1
        self.assertTrue(visible(reply, "x"))
        reply["actors"][0]["active"] = False
        self.assertFalse(visible(reply, "x"))

    def test_unity_bounds_serialization(self):
        self.assertEqual(bounds_size(dict(bounds=dict(m_Extent=dict(x=2, y=3, z=4)))),
                         dict(x=4, y=6, z=8))

    def test_invalid_numeric_payloads(self):
        for rows in [[dict(name="x", value=1), dict(name="x", value=2)],
                     [dict(name="x", value=float("nan"))]]:
            with self.assertRaises(ProductError):
                nums(rows)

    def test_obligations_are_conjunctive(self):
        target = Evaluation.__new__(Evaluation)
        target.leaves = dict(x=dict(state="INCONCLUSIVE_EVALUATOR", observations=[]))
        target.context = "unit-test"
        target.p = SimpleNamespace(last={}, serial=1)
        for state in ["PASS", "FAIL_OBSERVED", "PASS", "BLOCKED_BY_PRODUCT"]:
            target.record("x", state, "Fixture")
        self.assertEqual(target.leaves["x"]["state"], "FAIL_OBSERVED")
        self.assertEqual(len(target.leaves["x"]["observations"]), 4)
        target.record("x", "INCONCLUSIVE_EVALUATOR", "Provider uncertainty")
        self.assertEqual(target.leaves["x"]["state"], "INCONCLUSIVE_EVALUATOR")

class OutputTests(unittest.TestCase):
    def test_diagnostic_subset_is_not_an_evaluator_failure_or_zero(self):
        self.assertEqual(observation_state(dict(state="INCONCLUSIVE_EVALUATOR", observations=[])), "not_run")
        self.assertEqual(observation_state(dict(state="INCONCLUSIVE_EVALUATOR",
            observations=[dict(state="INCONCLUSIVE_EVALUATOR", detail="Provider failed")])),
            "inconclusive_evaluator")
        self.assertEqual(observation_state(dict(state="FAIL_OBSERVED",
            observations=[dict(state="FAIL_OBSERVED", detail="Actual defect")])), "fail")

    def test_no_frame_requires_actual_candidate_build_failure(self):
        with tempfile.TemporaryDirectory() as path:
            folder = Path(path)
            (folder / "reference.png").write_bytes(b"only-a-hash-fixture-not-an-image")
            (folder / "build.log").write_text("Candidate.cs: error CS1002", encoding="utf-8")
            value = dict(status="no_candidate_frame_product_blocked", score=0, model_call=False,
                         reference_sha256=sha(folder / "reference.png"))
            (folder / "d6.json").write_text(json.dumps(value), encoding="utf-8")
            auto = dict(infrastructure_error=None, leaves=[dict(id="d1.import", state="FAIL_OBSERVED")])
            (folder / "automatic-score.json").write_text(json.dumps(auto), encoding="utf-8")
            self.assertEqual(verified_visual(folder, folder)["score"], 0)
            auto["infrastructure_error"] = "Provider crash"
            (folder / "automatic-score.json").write_text(json.dumps(auto), encoding="utf-8")
            with self.assertRaises(ValueError):
                verified_visual(folder, folder)
            auto["infrastructure_error"] = None
            auto["leaves"][0]["state"] = "PASS"
            (folder / "automatic-score.json").write_text(json.dumps(auto), encoding="utf-8")
            with self.assertRaises(ValueError):
                verified_visual(folder, folder)

    def fixture(self):
        data = dict(schema_version="2.0", sample_id="fixture", sample_version="1.0.0",
            evaluator_version="1.2.0", run_id="fixture", evaluation_valid=True, classification="scored",
            coverage_status="qualified", reason="", dimensions={}, checks=[],
            coverage_evidence=["evidence.json"], final_score=100, max_score=100)
        for dimension, maximum in MAXIMA.items():
            data["dimensions"][dimension] = dict(score=maximum, max_score=maximum, status="complete", evidence=["evidence.json"])
            data["checks"].append(dict(id=dimension+".fixture", requirement_ids=["PUBLIC-01"],
                dimension=dimension, score=maximum, max_score=maximum, status="pass",
                reason="", blocked_by=[], evidence=["evidence.json"]))
        return data

    def test_all_six_dimensions_required(self):
        value = self.fixture()
        self.assertTrue(validate(value, require_final=True))
        del value["dimensions"]["D6"]
        with self.assertRaises(ValueError):
            validate(value)

    def test_total_and_coverage_cannot_be_fabricated(self):
        for key, value in [("final_score", 99), ("coverage_status", "gaps_found"), ("max_score", 90)]:
            data = self.fixture()
            data[key] = value
            with self.assertRaises(ValueError):
                validate(data)

    def test_unobserved_not_zero(self):
        data = self.fixture()
        data["checks"][0].update(status="inconclusive_evaluator", score=0, reason="No observation")
        with self.assertRaises(ValueError):
            validate(data)

    def test_blocker_must_exist(self):
        data = self.fixture()
        data["checks"][0].update(status="blocked_by_candidate", score=0, blocked_by=["missing"], reason="Blocked")
        with self.assertRaises(ValueError):
            validate(data)

if __name__ == "__main__":
    unittest.main()
