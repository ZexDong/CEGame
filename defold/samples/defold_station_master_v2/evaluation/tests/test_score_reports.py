import sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import unittest

from framework.defold_player_runtime.score_reports import combine_reports


def script() -> dict:
    return {
        "trajectories": [
            {
                "steps": [
                    {
                        "check": {
                            "id": dimension,
                            "dim": dimension,
                            "source": "gdd:R-1",
                            "assert": "true",
                        }
                    }
                    for dimension in ("D2", "D3", "D4", "D5")
                ]
            }
        ]
    }


def checkpoints(statuses=None) -> dict:
    statuses = statuses or {}
    return {
        "evaluation_status": "valid",
        "checks": [
            {"id": dimension, "dim": dimension, "status": statuses.get(dimension, "pass")}
            for dimension in ("D2", "D3", "D4", "D5")
        ],
    }


def with_cap(value: dict, cap_id="completion", required=None, maximum=50) -> dict:
    value["score_caps"] = [
        {
            "id": cap_id,
            "requires_all": required or ["D4"],
            "max_nonvisual_score": maximum,
        }
    ]
    return value


class ScoreReportsTest(unittest.TestCase):
    def test_all_pass_is_nonvisual_ninety(self):
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            checkpoints(),
            script(),
        )
        self.assertEqual("valid", report["evaluation_status"])
        self.assertEqual(90.0, report["nonvisual_score"])
        self.assertEqual(90.0, report["raw_nonvisual_score"])
        self.assertIsNone(report["applied_score_cap"])
        self.assertEqual([], report["triggered_score_caps"])
        self.assertIsNone(report["D6"])

    def test_unable_counts_as_not_passed(self):
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            checkpoints({"D3": "unable"}),
            script(),
        )
        self.assertEqual(70.0, report["nonvisual_score"])

    def test_infrastructure_invalid_never_becomes_zero(self):
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            {"evaluation_status": "infrastructure_invalid", "checks": []},
            script(),
        )
        self.assertEqual("infrastructure_invalid", report["evaluation_status"])
        self.assertIsNone(report["nonvisual_score"])

    def test_missing_check_is_evaluator_invalid(self):
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            {"evaluation_status": "valid", "checks": checkpoints()["checks"][:-1]},
            script(),
        )
        self.assertEqual("evaluator_invalid", report["evaluation_status"])
        self.assertIsNone(report["nonvisual_score"])

    def test_repeated_evidence_for_one_id_is_conjunctive_not_extra_weight(self):
        value = script()
        value["trajectories"][0]["steps"].append(
            {
                "check": {
                    "id": "D4",
                    "dim": "D4",
                    "source": "gdd:R-1",
                    "assert": "true",
                }
            }
        )
        report_rows = checkpoints()["checks"]
        report_rows.append({"id": "D4", "dim": "D4", "status": "fail"})
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            {"evaluation_status": "valid", "checks": report_rows},
            value,
        )
        self.assertEqual(70.0, report["nonvisual_score"])
        self.assertEqual(1, report["dimensions"]["D4"]["total_checks"])

    def test_failed_required_check_caps_score_but_preserves_raw_score(self):
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            checkpoints({"D4": "fail"}),
            with_cap(script()),
        )
        self.assertEqual(70.0, report["raw_nonvisual_score"])
        self.assertEqual(50.0, report["nonvisual_score"])
        self.assertEqual(50.0, report["applied_score_cap"])
        self.assertEqual(
            [
                {
                    "id": "completion",
                    "max_nonvisual_score": 50.0,
                    "failed_required_checks": ["D4"],
                }
            ],
            report["triggered_score_caps"],
        )

    def test_all_required_checks_pass_without_triggering_cap(self):
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            checkpoints(),
            with_cap(script()),
        )
        self.assertEqual(90.0, report["raw_nonvisual_score"])
        self.assertEqual(90.0, report["nonvisual_score"])
        self.assertIsNone(report["applied_score_cap"])
        self.assertEqual([], report["triggered_score_caps"])

    def test_unable_required_check_also_triggers_cap(self):
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            checkpoints({"D4": "unable"}),
            with_cap(script()),
        )
        self.assertEqual(50.0, report["nonvisual_score"])

    def test_triggered_cap_never_raises_a_lower_raw_score(self):
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 0},
            checkpoints({"D2": "fail", "D3": "fail", "D4": "fail"}),
            with_cap(script(), maximum=50),
        )
        self.assertEqual(10.0, report["raw_nonvisual_score"])
        self.assertEqual(10.0, report["nonvisual_score"])
        self.assertEqual(50.0, report["applied_score_cap"])

    def test_multiple_triggered_caps_use_the_lowest_maximum(self):
        value = with_cap(script(), cap_id="late", required=["D4"], maximum=50)
        value["score_caps"].append(
            {
                "id": "early",
                "requires_all": ["D3"],
                "max_nonvisual_score": 45,
            }
        )
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            checkpoints({"D3": "fail", "D4": "fail"}),
            value,
        )
        self.assertEqual(45.0, report["applied_score_cap"])
        self.assertEqual(45.0, report["nonvisual_score"])

    def test_repeated_required_evidence_must_all_pass(self):
        value = with_cap(script())
        value["trajectories"][0]["steps"].append(
            {
                "check": {
                    "id": "D4",
                    "dim": "D4",
                    "source": "gdd:R-1",
                    "assert": "true",
                }
            }
        )
        rows = checkpoints()["checks"]
        rows.append({"id": "D4", "dim": "D4", "status": "fail"})
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            {"evaluation_status": "valid", "checks": rows},
            value,
        )
        self.assertEqual(50.0, report["nonvisual_score"])
        self.assertEqual(["D4"], report["triggered_score_caps"][0]["failed_required_checks"])

    def test_invalid_score_cap_configuration_invalidates_evaluator(self):
        invalid_caps = [
            {"id": "bad", "requires_all": [], "max_nonvisual_score": 50},
            {"id": "bad", "requires_all": ["UNKNOWN"], "max_nonvisual_score": 50},
            {"id": "bad", "requires_all": ["D4"], "max_nonvisual_score": True},
            {"id": "bad", "requires_all": ["D4"], "max_nonvisual_score": 91},
        ]
        for cap in invalid_caps:
            with self.subTest(cap=cap):
                value = script()
                value["score_caps"] = [cap]
                report = combine_reports(
                    {"evaluation_status": "valid", "d1_score": 10},
                    checkpoints(),
                    value,
                )
                self.assertEqual("evaluator_invalid", report["evaluation_status"])
                self.assertIsNone(report["nonvisual_score"])

    def test_duplicate_score_cap_ids_are_rejected(self):
        value = with_cap(script())
        value["score_caps"].append(dict(value["score_caps"][0]))
        report = combine_reports(
            {"evaluation_status": "valid", "d1_score": 10},
            checkpoints(),
            value,
        )
        self.assertEqual("evaluator_invalid", report["evaluation_status"])


if __name__ == "__main__":
    unittest.main()
