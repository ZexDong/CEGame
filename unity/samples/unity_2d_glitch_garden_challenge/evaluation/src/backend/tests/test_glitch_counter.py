"""Legal HUD equivalence must not be mistaken for a candidate defect."""
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from coverage_glitch import garden_progress_visible


def rendered(value):
    return dict(ui=[dict(text=value, active=True, color=dict(a=1), shaderValid=True)])


class GardenCounterTests(unittest.TestCase):
    def test_equivalent_truthful_progress_displays(self):
        for display in ["Wave 4/12", "Waves: 8", "Enemies 1", "INVADERS 9"]:
            self.assertTrue(garden_progress_visible(rendered(display), 4, 12, 1), display)
        self.assertTrue(garden_progress_visible(rendered("INVADERS 12"), 1, 12, 1))

    def test_static_wrong_or_invisible_total_cannot_pass(self):
        self.assertFalse(garden_progress_visible(rendered("INVADERS 12"), 4, 12, 1))
        self.assertFalse(garden_progress_visible(rendered("INVADERS 10"), 4, 12, 1))
        r = rendered("INVADERS 9")
        r["ui"][0]["color"]["a"] = 0
        self.assertFalse(garden_progress_visible(r, 4, 12, 1))


if __name__ == "__main__":
    unittest.main()
