import sys
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import train_healthpal_target_benchmark_v3 as v3


class TargetBenchmarkTests(unittest.TestCase):
    def test_attach_target_preserves_exact_common_keys(self):
        common = pd.DataFrame(
            {
                "id": ["p1", "p2"],
                "event_time": pd.to_datetime(["2024-01-01 10:00", "2024-01-01 11:00"]),
                "target": [0, 1],
                "feature": [1.0, 2.0],
            }
        )
        hourly = pd.DataFrame(
            {
                "id": ["p1", "p2"],
                "timestamp": pd.to_datetime(["2024-01-01 10:00", "2024-01-01 11:00"]),
                "TIRED": [1.0, 0.0],
            }
        )
        result = v3.attach_target(common, hourly, "TIRED")
        self.assertEqual(result["target"].tolist(), [1, 0])
        self.assertEqual(result["feature"].tolist(), [1.0, 2.0])
        self.assertTrue(result[["id", "event_time"]].equals(common[["id", "event_time"]]))

    def test_comparison_uses_prevalence_lift(self):
        def result(target, prevalence, auprc):
            return {
                "target": target,
                "events": 100,
                "positives": int(prevalence * 100),
                "prevalence": prevalence,
                "participants": 10,
                "participants_with_positive": 8,
                "nested_selection_oof": {
                    "auprc": auprc,
                    "auroc": 0.7,
                    "brier": 0.1,
                    "precision": 0.4,
                    "recall": 0.7,
                    "f1": 0.5,
                },
                "auprc_lift_over_prevalence": auprc / prevalence,
                "lift_hypothesis": v3.LIFT_HYPOTHESES[target],
                "lift_hypothesis_met": auprc / prevalence >= v3.LIFT_HYPOTHESES[target],
                "cluster_bootstrap_95_ci": {
                    "auprc": {"lower_95": auprc - 0.01, "upper_95": auprc + 0.01},
                    "auroc": {"lower_95": 0.65, "upper_95": 0.75},
                    "brier": {"lower_95": 0.09, "upper_95": 0.11},
                },
                "lowest_fold_auroc": 0.6,
            }

        results = {
            "TENSE/ANXIOUS": result("TENSE/ANXIOUS", 0.1, 0.12),
            "TIRED": result("TIRED", 0.2, 0.4),
            "RESTED/RELAXED": result("RESTED/RELAXED", 0.25, 0.5),
        }
        comparison = v3.comparison_frame(results)
        self.assertEqual(comparison["auprc_lift"].round(6).tolist(), [1.2, 2.0, 2.0])


if __name__ == "__main__":
    unittest.main()
