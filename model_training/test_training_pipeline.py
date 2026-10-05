import importlib.util
import sys
import unittest
from pathlib import Path

import numpy as np
import pandas as pd


MODULE_PATH = Path(__file__).with_name("train_healthpal_stress.py")
SPEC = importlib.util.spec_from_file_location("train_healthpal_stress", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class FeatureWindowTests(unittest.TestCase):
    def test_event_hour_is_excluded_and_previous_day_is_used(self):
        hours = pd.date_range("2024-01-02 00:00", periods=13, freq="h")
        hourly = pd.DataFrame(
            {
                "id": ["p1"] * len(hours),
                "timestamp": hours,
                "bpm": np.arange(10, 23, dtype=float),
                "steps": np.ones(len(hours)),
                "distance": np.ones(len(hours)) * 2,
                MODULE.TARGET: [np.nan] * 12 + [1.0],
            }
        )
        daily = pd.DataFrame(
            {
                "id": ["p1", "p1"],
                "date": pd.to_datetime(["2024-01-01", "2024-01-02"]),
                "resting_hr": [50.0, 99.0],
                "minutesAsleep": [420.0, 1.0],
            }
        )
        result = MODULE.build_event_dataset(hourly, daily, 12)
        self.assertEqual(len(result), 1)
        self.assertAlmostEqual(result.loc[0, "hr_mean"], np.mean(np.arange(10, 22)))
        self.assertNotEqual(result.loc[0, "hr_mean"], np.mean(np.arange(11, 23)))
        self.assertEqual(result.loc[0, "resting_hr"], 50.0)
        self.assertEqual(result.loc[0, "sleep_minutes"], 420.0)
        self.assertEqual(result.loc[0, "steps_sum"], 12.0)

    def test_half_window_coverage_is_required(self):
        hours = pd.date_range("2024-01-02 00:00", periods=13, freq="h")
        bpm = np.array([70.0] * 5 + [np.nan] * 7 + [90.0])
        hourly = pd.DataFrame(
            {
                "id": ["p1"] * len(hours),
                "timestamp": hours,
                "bpm": bpm,
                "steps": np.ones(len(hours)),
                "distance": np.ones(len(hours)),
                MODULE.TARGET: [np.nan] * 12 + [0.0],
            }
        )
        daily = pd.DataFrame(
            {
                "id": ["p1"],
                "date": pd.to_datetime(["2024-01-01"]),
                "resting_hr": [55.0],
                "minutesAsleep": [400.0],
            }
        )
        with self.assertRaises(ValueError):
            MODULE.build_event_dataset(hourly, daily, 12)


if __name__ == "__main__":
    unittest.main()
