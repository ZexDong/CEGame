"""Small synthetic orchestration fixtures, not gameplay or Gold implementations."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
EVALUATION = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVALUATION / "src"))
sys.path.insert(0, str(EVALUATION))
import runner
from runner import read, write
from framework.defold_player_runtime.score_reports import combine_reports, expected_checks


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="defold-package-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / "result"
        self.project = self.root / "candidate"
        self.project.mkdir()
        (self.project / "game.project").write_text("fixture\n")

    def test_detached_sample_has_no_parent_runtime_dependency(self):
        isolated = self.root / "sample"
        shutil.copytree(EVALUATION.parent, isolated, ignore=shutil.ignore_patterns("__pycache__", ".DS_Store"))
        result = subprocess.run([sys.executable, "-B", str(isolated / "evaluation/evaluate.py"), "--validate-only"],
                                cwd=self.root, env={**os.environ, "PYTHONPATH": ""}, capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertTrue(json.loads(result.stdout)["package_valid"])

    def test_missing_dependency_is_rejected_offline(self):
        isolated = self.root / "sample"
        shutil.copytree(EVALUATION.parent, isolated, ignore=shutil.ignore_patterns("__pycache__", ".DS_Store"))
        (isolated / "evaluation/src/framework/defold_player_runtime/player.py").unlink()
        result = subprocess.run([sys.executable, "-B", str(isolated / "evaluation/evaluate.py"), "--validate-only"],
                                cwd=self.root, env={**os.environ, "PYTHONPATH": ""}, capture_output=True, text=True)
        self.assertEqual(2, result.returncode)
        self.assertIn("player.py", result.stdout)

    def test_host_failure_produces_valid_null_report(self):
        with redirect_stdout(StringIO()), patch.object(runner, "host_check", side_effect=RuntimeError("fixture missing OCR")):
            code = runner.main(EVALUATION, ["--project", str(self.project), "--output", str(self.output)])
        report = read(self.output / "score.json")
        self.assertEqual(2, code)
        self.assertEqual("infrastructure_invalid", report["evaluation_status"])
        self.assertTrue(all(d is None for d in report["dimensions"].values()))

    def test_output_inside_candidate_is_rejected_without_writes(self):
        target = self.project / "result"
        with redirect_stderr(StringIO()), self.assertRaises(SystemExit):
            runner.main(EVALUATION, ["--project", str(self.project), "--output", str(target)])
        self.assertFalse(target.exists())

    def simulate_pipeline(self, build=True, invalid_score=False):
        real_call = runner.call

        def fixture_call(command, env, output=None, label=None):
            if label == "d1":
                checks_by_id = expected_checks(read(EVALUATION / "rules.json"))
                checks = [{"id": cid, "status": "pass" if build or cid == "D1_PROJECT_ENTRY" else "fail",
                           "detail": "synthetic build fixture"} for cid in ["D1_PROJECT_ENTRY", "D1_BOB_BUILD", "D1_BUNDLE_ENTRY", "D1_RUNTIME_DASHBOARD_SMOKE"]]
                write(self.output / "d1/d1-report.json", {"evaluation_status": "valid", "checks": checks,
                                                         "d1_score": 10 if build else 2.5})
                if build:
                    executable = self.output / "d1/candidate/build/default/Fixture.app/Contents/MacOS/fixture"
                    executable.parent.mkdir(parents=True)
                    executable.write_text("fixture, never executed")
                    executable.chmod(0o755)
            elif label == "checkpoint":
                checks_by_id = expected_checks(read(EVALUATION / "rules.json"))
                checks = [{"id": cid, "dim": dim, "status": "pass", "detail": "synthetic evidence"}
                          for cid, dim in checks_by_id.items()]
                write(self.output / "checkpoint/checkpoint-report.json", {"evaluation_status": "valid", "checks": checks})
            elif label == "score" and invalid_score:
                write(self.output / "score.json", {"evaluation_status": "evaluator_invalid"})
            else:
                return real_call(command, env, output, label)
            return subprocess.CompletedProcess(command, 0, "", "")

        with redirect_stdout(StringIO()), patch.object(runner, "host_check"), patch.object(runner, "call", side_effect=fixture_call):
            return runner.main(EVALUATION, ["--project", str(self.project), "--output", str(self.output)])

    def test_candidate_build_failure_retains_d1_without_dynamic_credit(self):
        self.assertEqual(3, self.simulate_pipeline(build=False))
        report = read(self.output / "score.json")
        self.assertEqual("incomplete", report["evaluation_status"])
        self.assertEqual(2.5, report["dimensions"]["D1"]["score"])
        self.assertIsNone(report["dimensions"]["D2"])
        self.assertFalse((self.output / "checkpoint").exists())

    def test_success_matches_original_combiner_without_conversion(self):
        self.assertEqual(0, self.simulate_pipeline())
        report = read(self.output / "score.json")
        expected = combine_reports(read(self.output / "d1/d1-report.json"),
                                   read(self.output / "checkpoint/checkpoint-report.json"),
                                   read(EVALUATION / "rules.json"))
        self.assertEqual(expected, report)
        self.assertEqual(90, report["nonvisual_score"])
        self.assertEqual(1, report["schema_version"])
        self.assertIsNone(report["D6"])
        self.assertIsNone(report["total_score"])
        self.assertFalse((self.output / "functional-score.json").exists())

    def test_zero_exit_from_invalid_scorer_is_not_success(self):
        self.assertEqual(2, self.simulate_pipeline(invalid_score=True))
        self.assertEqual("infrastructure_invalid", read(self.output / "score.json")["evaluation_status"])


if __name__ == "__main__":
    unittest.main()
