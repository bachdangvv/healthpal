import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import train_healthpal_fatigue_v4 as v4


class FatigueV4Tests(unittest.TestCase):
    def _row(self, candidate_id, auprc, auroc, fold_auprc, fold_auroc):
        return {
            "candidate_id": candidate_id,
            "mean_auprc": auprc,
            "mean_auroc": auroc,
            "fold_auprc": fold_auprc,
            "fold_auroc": fold_auroc,
        }

    def test_candidate_contract(self):
        contract = {(candidate.candidate_id, candidate.feature_spec, candidate.model) for candidate in v4.CANDIDATES}
        self.assertEqual(
            contract,
            {
                ("A", "w6_low_activity_250", "logistic"),
                ("B", "w6_robust_quantiles", "xgboost"),
                ("C", "multiscale_2h_6h_robust", "xgboost"),
            },
        )

    def test_logistic_wins_when_xgboost_gain_is_small(self):
        rows = [
            self._row("A", 0.30, 0.61, [0.3, 0.3, 0.3, 0.3], [0.59, 0.60, 0.61, 0.62]),
            self._row("B", 0.31, 0.62, [0.31, 0.31, 0.31, 0.31], [0.60, 0.61, 0.62, 0.63]),
            self._row("C", 0.29, 0.60, [0.29] * 4, [0.58] * 4),
        ]
        selected, _ = v4.select_candidate(rows)
        self.assertEqual(selected, "A")

    def test_xgboost_wins_only_with_clear_stable_gain(self):
        rows = [
            self._row("A", 0.30, 0.60, [0.30, 0.29, 0.31, 0.30], [0.55, 0.58, 0.60, 0.62]),
            self._row("B", 0.33, 0.62, [0.34, 0.32, 0.34, 0.32], [0.56, 0.60, 0.63, 0.69]),
            self._row("C", 0.31, 0.61, [0.31] * 4, [0.55, 0.60, 0.63, 0.66]),
        ]
        selected, decision = v4.select_candidate(rows)
        self.assertEqual(selected, "B")
        self.assertTrue(all(decision["checks"].values()))

    def test_gate_boundaries(self):
        gates = v4.evaluate_gates(auprc=0.28, prevalence=0.22, auroc=0.60, lowest_fold_auroc=0.521)
        self.assertTrue(gates["research"]["passed"])
        self.assertFalse(gates["user_facing_mvp"]["passed"])


if __name__ == "__main__":
    unittest.main()
