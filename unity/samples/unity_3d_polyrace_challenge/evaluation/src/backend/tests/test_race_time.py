"""A seconds unit and a literal Time label are legal equivalent displays."""
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from coverage_polyrace import race_time_visible


def rendered(value):
    return dict(ui=[dict(text=value, active=True, color=dict(a=1), shaderValid=True)])


class RaceTimeTests(unittest.TestCase):
    def test_truthful_keyword_and_unit_forms(self):
        for display in ["Time 12.35", "12.35s", "12.35 seconds", "<b>12.35</b>s", "12.35 / 30.0s", "12.35/30s"]:
            self.assertTrue(race_time_visible(rendered(display), 12.3456), display)
        self.assertTrue(race_time_visible(rendered("00.00s"), 0))
        self.assertTrue(race_time_visible(rendered("00.00 / 30.0s"), 0))

    def test_precision_and_constant_zero_are_not_excused(self):
        self.assertFalse(race_time_visible(rendered("00.00s"), 12.35))
        self.assertFalse(race_time_visible(rendered("12.34s"), 12.35))
        self.assertTrue(race_time_visible(rendered("12.3s"), 12.34))
        self.assertFalse(race_time_visible(rendered("12.35 / 30.0s"), 30))
        self.assertFalse(race_time_visible(rendered("00.00 / 30.0s"), 12.35))

    def test_unlabelled_speed_shield_or_invisible_time_cannot_pass(self):
        self.assertFalse(race_time_visible(rendered("12.35 SPD   90 SHD"), 12.35))
        self.assertFalse(race_time_visible(rendered("12.35"), 12.35))
        r = rendered("12.35s")
        r["ui"][0]["shaderValid"] = False
        self.assertFalse(race_time_visible(r, 12.35))


if __name__ == "__main__":
    unittest.main()
