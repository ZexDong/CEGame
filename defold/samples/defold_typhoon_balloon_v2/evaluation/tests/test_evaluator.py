"""Package-level tests; no Gold or gameplay fixture is included."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class EvaluatorPackageTests(unittest.TestCase):
    def test_detached_validate_only(self):
        sample = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix="public-sample-test-") as temporary:
            detached = Path(temporary) / "sample"
            shutil.copytree(sample, detached, ignore=shutil.ignore_patterns("__pycache__", ".DS_Store"))
            result = subprocess.run(
                [sys.executable, "-B", str(detached / "evaluation/evaluate.py"), "--validate-only"],
                cwd=temporary,
                env={**os.environ, "PYTHONPATH": ""},
                capture_output=True,
                text=True,
            )
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertTrue(json.loads(result.stdout)["package_valid"])


if __name__ == "__main__":
    unittest.main()
