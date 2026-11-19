"""The public adapter must preserve the six fixed dimension maxima."""
import importlib.util
from pathlib import Path
import unittest

class FixedWeights(unittest.TestCase):
    def test_adapter(self):
        path = Path(__file__).resolve().parents[3] / "evaluate.py"
        spec = importlib.util.spec_from_file_location("public_adapter", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.MAXIMA, dict(D1=10, D2=30, D3=20, D4=20, D5=10, D6=10))

if __name__ == "__main__":
    unittest.main()
