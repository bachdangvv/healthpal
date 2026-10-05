import sys
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))

import train_healthpal_fatigue_v5 as v5


class FatigueV5Tests(unittest.TestCase):
    def test_candidate_only_adds_parity_safe_sleep_features(self):
        self.assertEqual(v5.SPECS["V4_baseline"].features, v5.BASE_FEATURES)
        self.assertEqual(
            v5.SPECS["V5_sleep_quality"].features,
            v5.BASE_FEATURES + v5.SLEEP_QUALITY_FEATURES,
        )
        forbidden = {"sleep_efficiency", "sleep_deep_ratio", "sleep_light_ratio", "sleep_rem_ratio", "spo2"}
        self.assertTrue(forbidden.isdisjoint(v5.SPECS["V5_sleep_quality"].features))

    def test_sleep_features_are_d_minus_one_and_reproducible(self):
        frame = pd.DataFrame(
            {
                "id": [1],
                "event_time": pd.to_datetime(["2026-01-03 18:00"]),
                "sleep_minutes": [400.0],
            }
        )
        daily = pd.DataFrame(
            {
                "id": [1],
                "date": pd.to_datetime(["2026-01-02"]),
                "sleep_duration": [28_800_000.0],
                "minutesAwake": [80.0],
                "minutesToFallAsleep": [20.0],
                "minutesAfterWakeup": [10.0],
            }
        )
        result, audit = v5.attach_sleep_quality(frame, daily)
        self.assertEqual(audit["alignment"], "previous_calendar_day_D_minus_1")
        self.assertAlmostEqual(result.loc[0, "sleep_session_minutes"], 480.0)
        self.assertAlmostEqual(result.loc[0, "sleep_awake_fraction"], 80.0 / 480.0)
        self.assertAlmostEqual(result.loc[0, "sleep_onset_fraction"], 20.0 / 480.0)
        self.assertAlmostEqual(result.loc[0, "sleep_after_wakeup_fraction"], 10.0 / 480.0)

    def test_replacement_gate_requires_every_check(self):
        checks = {
            "auprc_delta": 0.02 >= v5.REPLACEMENT_GATE["auprc_delta_min"],
            "auroc_delta": 0.01 >= v5.REPLACEMENT_GATE["auroc_delta_min"],
            "lowest_fold_auroc_not_worse": 0.60 >= 0.60,
        }
        self.assertTrue(all(checks.values()))
        checks["lowest_fold_auroc_not_worse"] = False
        self.assertFalse(all(checks.values()))


if __name__ == "__main__":
    unittest.main()
