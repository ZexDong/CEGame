import json
import tempfile
import unittest
from pathlib import Path

import evaluate


HERE = Path(__file__).resolve().parent


def sample_snapshot():
    naming = evaluate.load_json(HERE / "naming-tables.json")
    return {
        "revision": 2,
        "phase": "playing",
        "slots": {name: 0 for name in naming["slots"]} | {"day": 1, "coins": 8, "water": 4},
        "entities": [{"kind": row["kind"], "state": "empty"} for row in naming["entities"]],
        "targets": [{"kind": row["kind"], "rect": [1, 2, 3, 4], "visible": True, "interactable": True} for row in naming["targets"]]
    }


class EvaluatorTests(unittest.TestCase):
    def test_snapshot_contract(self):
        naming = evaluate.load_json(HERE / "naming-tables.json")
        self.assertEqual(evaluate.validate_snapshot(sample_snapshot(), naming), [])

    def test_safe_assertions(self):
        snap = sample_snapshot()
        self.assertTrue(evaluate.eval_assertion("phase == 'playing' and slots.coins == 8", snap, {}, {}))
        self.assertTrue(evaluate.eval_assertion("entity('plot_1').state == 'empty'", snap, {}, {}))
        with self.assertRaises(ValueError):
            evaluate.eval_assertion("__import__('os').system('echo unsafe')", snap, {}, {})

    def test_checkpoint_json_has_unique_check_ids(self):
        script = evaluate.load_json(HERE / "checkpoint-script.json")
        ids = [s["check"]["id"] for t in script["trajectories"] for s in t["steps"] if "check" in s]
        self.assertEqual(len(ids), len(set(ids)))

    def test_every_condition_uses_supported_expression_syntax(self):
        script = evaluate.load_json(HERE / "checkpoint-script.json")
        snap = sample_snapshot()
        saved = {name: snap for name in (
            "N0", "N1", "S0", "S1", "M0", "G0", "G1", "PREWIN",
            "W0", "MIDRUN", "PRELOSE", "L0",
        )}
        for trajectory in script["trajectories"]:
            for step in trajectory["steps"]:
                expressions = []
                if "cond" in step:
                    expressions.append(step["cond"])
                if "check" in step:
                    expressions.append(step["check"]["assert"])
                for expression in expressions:
                    try:
                        evaluate.eval_assertion(expression, snap, saved, {"N0": True})
                    except (AttributeError, KeyError):
                        pass
                    except Exception as exc:
                        self.fail(f"unsupported expression {expression!r}: {exc}")


if __name__ == "__main__":
    unittest.main()
