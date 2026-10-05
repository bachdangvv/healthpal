import json
import sys
import unittest
from pathlib import Path

import numpy as np
import onnx
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_mobile_v4 as export


class ExportMobileV4Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = export.export(check_only=False)
        cls.assets = export.FLUTTER_ASSETS
        cls.config = export.load_config(cls.assets / "healthpal_fatigue_v4_config.json")

    def test_copied_artifacts_match_manifest(self):
        manifest = json.loads(
            (self.assets / "artifact_checksums.sha256.json").read_text(encoding="utf-8")
        )
        export.verify_copied_artifacts(self.assets, manifest)

    def test_mobile_graph_uses_only_standard_ops(self):
        model = onnx.load(self.assets / export.MOBILE_ONNX_NAME)
        domains = {opset.domain for opset in model.opset_import}
        self.assertNotIn("ai.onnx.ml", domains)
        self.assertEqual(
            {node.op_type for node in model.graph.node},
            {"Sub", "Div", "MatMul", "Add", "Sigmoid"},
        )
        self.assertEqual([node.name for node in model.graph.output], ["positive_probability"])

    def test_mobile_graph_does_not_impute(self):
        model = onnx.load(self.assets / export.MOBILE_ONNX_NAME)
        self.assertTrue(all(node.op_type != "Imputer" for node in model.graph.node))
        nan_input = np.full((1, 12), np.nan, dtype=np.float32)
        mobile = export.onnx_positive_probability(self.assets / export.MOBILE_ONNX_NAME, nan_input)
        self.assertTrue(np.isnan(mobile).all())

    def test_calibration_stays_in_config(self):
        self.assertEqual(
            self.config["calibration"]["formula"],
            "sigmoid(slope * logit(clamp(base_probability,1e-6,1-1e-6)) + intercept)",
        )
        self.assertAlmostEqual(self.config["calibration"]["slope"], 0.7806493861342522)
        self.assertAlmostEqual(self.config["calibration"]["intercept"], -1.2659313281484506)
        self.assertAlmostEqual(
            self.config["decision_threshold"]["threshold"], 0.18170608515558545
        )
        model = onnx.load(self.assets / export.MOBILE_ONNX_NAME)
        serialized = model.SerializeToString()
        self.assertNotIn(b"0.18170608515558545", serialized)
        self.assertNotIn(b"0.7806493861342522", serialized)

    def test_probability_parity_under_tolerance(self):
        self.assertLess(self.report["training_max_abs_probability_diff"], export.PARITY_TOLERANCE)
        self.assertLess(self.report["random_max_abs_probability_diff"], export.PARITY_TOLERANCE)
        self.assertEqual(self.report["training_fixture_count"], 3398)
        self.assertEqual(self.report["random_vector_count"], 1000)

    def test_feature_fixtures_reconstruct_training_rows(self):
        fixtures = json.loads(
            (export.RUST_TESTDATA / "feature_parity.json").read_text(encoding="utf-8")
        )
        self.assertGreaterEqual(len(fixtures), 100)
        training = pd.read_csv(export.SOURCE_DIR / "training_dataset.csv")
        first = fixtures[0]
        expected = training.iloc[0]
        for name in export.LOCKED_FEATURE_ORDER:
            self.assertLess(abs(first["expected_features"][name] - float(expected[name])), 1e-12)


if __name__ == "__main__":
    unittest.main()
