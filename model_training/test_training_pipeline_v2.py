import sys
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import train_healthpal_stress_v2 as v2


class V2FeatureTests(unittest.TestCase):
    def _daily(self):
        return pd.DataFrame(
            {
                "id": ["p1"],
                "date": pd.to_datetime(["2024-01-01"]),
                "resting_hr": [50.0],
                "minutesAsleep": [420.0],
            }
        )

    def test_recency_relative_low_activity_and_event_exclusion(self):
        hours = pd.date_range("2024-01-02 00:00", periods=13, freq="h")
        hourly = pd.DataFrame(
            {
                "id": ["p1"] * 13,
                "timestamp": hours,
                "bpm": np.arange(60.0, 73.0),
                "steps": [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 1000, 0],
                "activityType": [np.nan] * 11 + ["['Run']", np.nan],
                v2.TARGET: [np.nan] * 12 + [1.0],
            }
        )
        frame, _ = v2.build_wide_event_dataset(hourly, self._daily())
        self.assertEqual(len(frame), 1)
        self.assertAlmostEqual(frame.loc[0, "h2_hr_mean"], 70.5)
        self.assertAlmostEqual(frame.loc[0, "h6_hr_mean"], 68.5)
        self.assertAlmostEqual(frame.loc[0, "recency_hr_mean_delta_2h_6h"], 2.0)
        self.assertAlmostEqual(frame.loc[0, "h2_hr_mean_minus_rhr"], 20.5)
        self.assertEqual(frame.loc[0, "h2_low100_hours"], 1)
        self.assertAlmostEqual(frame.loc[0, "h2_low100_hr_mean"], 70.0)
        self.assertEqual(frame.loc[0, "h2_exercise_hours"], 1)
        self.assertAlmostEqual(frame.loc[0, "h2_masked_hr_mean"], 70.0)
        self.assertNotEqual(frame.loc[0, "h2_hr_mean"], 71.5)

    def test_candidate_matrix_covers_requested_experiments(self):
        specs = v2.feature_specs()
        names = {spec.name for spec in specs}
        for name in (
            "w2_full_minmax",
            "w4_full_minmax",
            "w6_full_minmax",
            "w12_full_minmax",
            "w4_robust_quantiles",
            "w6_relative_rhr",
            "w4_low_activity_100",
            "w6_low_activity_250",
            "w6_exercise_masked",
            "multiscale_2h_6h",
        ):
            self.assertIn(name, names)
        self.assertEqual(set(v2.MODEL_KINDS), {"logistic", "histgb", "xgboost"})


if __name__ == "__main__":
    unittest.main()
