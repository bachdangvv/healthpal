use sha2::{Digest, Sha256};

use crate::config::ModelConfig;
use crate::types::AssessmentError;

const MOBILE_WEIGHTS_JSON: &str =
    include_str!("../assets/healthpal_fatigue_v4/healthpal_fatigue_v4_mobile_weights.json");

#[cfg(feature = "ort-runtime")]
const MOBILE_ONNX: &[u8] =
    include_bytes!("../assets/healthpal_fatigue_v4/healthpal_fatigue_v4_mobile.onnx");

#[derive(Clone, Debug, serde::Deserialize)]
#[cfg_attr(feature = "ort-runtime", allow(dead_code))]
struct MobileWeights {
    scaler_mean: Vec<f32>,
    scaler_scale: Vec<f32>,
    classifier_coef: Vec<f32>,
    classifier_intercept: f32,
}

#[cfg_attr(feature = "ort-runtime", allow(dead_code))]
impl MobileWeights {
    fn load() -> Result<Self, AssessmentError> {
        let weights: Self =
            serde_json::from_str(MOBILE_WEIGHTS_JSON).map_err(|err| AssessmentError::Model {
                message: format!("failed to parse mobile weights: {err}"),
            })?;
        if weights.scaler_mean.len() != 12
            || weights.scaler_scale.len() != 12
            || weights.classifier_coef.len() != 12
        {
            return Err(AssessmentError::Model {
                message: "mobile weights do not have 12 features".into(),
            });
        }
        Ok(weights)
    }

    fn predict(&self, features: &[f32; 12]) -> f32 {
        let mut logit = self.classifier_intercept;
        for (((&x, &mean), &scale), &coef) in features
            .iter()
            .zip(&self.scaler_mean)
            .zip(&self.scaler_scale)
            .zip(&self.classifier_coef)
        {
            logit += ((x - mean) / scale) * coef;
        }
        1.0 / (1.0 + (-logit).exp())
    }
}

pub struct OnnxScorer {
    #[cfg_attr(feature = "ort-runtime", allow(dead_code))]
    weights: MobileWeights,
    #[cfg(feature = "ort-runtime")]
    session: ort::session::Session,
}

impl OnnxScorer {
    pub fn load() -> Result<Self, AssessmentError> {
        let weights = MobileWeights::load()?;
        #[cfg(feature = "ort-runtime")]
        {
            let session = ort::session::Session::builder()
                .map_err(|err| AssessmentError::Model {
                    message: format!("failed to create ONNX session builder: {err}"),
                })?
                .commit_from_memory(MOBILE_ONNX)
                .map_err(|err| AssessmentError::Model {
                    message: format!("failed to load mobile ONNX graph: {err}"),
                })?;
            Ok(Self { weights, session })
        }
        #[cfg(not(feature = "ort-runtime"))]
        {
            Ok(Self { weights })
        }
    }

    pub fn predict_base_probability(
        &mut self,
        features: &[f32; 12],
    ) -> Result<f64, AssessmentError> {
        #[cfg(feature = "ort-runtime")]
        {
            self.predict_ort(features)
        }
        #[cfg(not(feature = "ort-runtime"))]
        {
            Ok(f64::from(self.weights.predict(features)))
        }
    }

    #[cfg(feature = "ort-runtime")]
    fn predict_ort(&mut self, features: &[f32; 12]) -> Result<f64, AssessmentError> {
        use ort::value::Tensor;

        let tensor = Tensor::from_array(([1usize, 12usize], features.to_vec())).map_err(|err| {
            AssessmentError::Model {
                message: format!("failed to pack feature tensor: {err}"),
            }
        })?;
        let outputs = self
            .session
            .run(ort::inputs!["float_input" => tensor])
            .map_err(|err| AssessmentError::Model {
                message: format!("ONNX inference failed: {err}"),
            })?;
        let value = outputs
            .get("positive_probability")
            .ok_or_else(|| AssessmentError::Model {
                message: "mobile ONNX graph did not return positive_probability".into(),
            })?;
        let (_shape, data) =
            value
                .try_extract_tensor::<f32>()
                .map_err(|err| AssessmentError::Model {
                    message: format!("failed to extract ONNX probability: {err}"),
                })?;
        let probability = *data.first().ok_or_else(|| AssessmentError::Model {
            message: "ONNX probability tensor was empty".into(),
        })?;
        if !probability.is_finite() {
            return Err(AssessmentError::Model {
                message: "ONNX returned a non-finite probability".into(),
            });
        }
        Ok(f64::from(probability))
    }
}

pub fn calibrate(base_probability: f64, config: &ModelConfig) -> f64 {
    let clipped = base_probability.clamp(1e-6, 1.0 - 1e-6);
    let logit = (clipped / (1.0 - clipped)).ln();
    sigmoid(config.calibration_slope * logit + config.calibration_intercept)
}

pub fn sigmoid(value: f64) -> f64 {
    1.0 / (1.0 + (-value).exp())
}

pub fn feature_vector_hash(features: &[f32; 12]) -> String {
    let mut hasher = Sha256::new();
    for value in features {
        hasher.update(value.to_le_bytes());
    }
    hex_encode(&hasher.finalize())
}

fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::{calibrate, feature_vector_hash, sigmoid, MobileWeights, OnnxScorer};
    use crate::config::ModelConfig;
    use serde::Deserialize;

    #[test]
    fn calibration_formula_matches_config_note() {
        let config = ModelConfig::load().expect("config");
        let base = 0.5_f64;
        let logit = (base / (1.0 - base)).ln();
        let expected = sigmoid(config.calibration_slope * logit + config.calibration_intercept);
        assert!((calibrate(base, &config) - expected).abs() < 1e-12);
        assert!(expected < 0.5);
    }

    #[test]
    fn mobile_onnx_matches_python_fixtures() {
        #[derive(Deserialize)]
        struct Row {
            features: Vec<f64>,
            sklearn_base_probability: f64,
            mobile_onnx_base_probability: f64,
            calibrated_probability: f64,
            threshold: f64,
            decision: bool,
        }
        let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("testdata")
            .join("inference_parity.json");
        let rows: Vec<Row> = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        assert!(rows.len() >= 100);
        let mut scorer = OnnxScorer::load().expect("onnx");
        let weights = MobileWeights::load().expect("weights");
        let config = ModelConfig::load().expect("config");
        let mut max_base_delta = 0.0_f64;
        let mut max_cal_delta = 0.0_f64;
        let mut max_weight_delta = 0.0_f64;
        for row in &rows {
            let mut features = [0.0_f32; 12];
            for (index, value) in row.features.iter().enumerate() {
                features[index] = *value as f32;
            }
            let base = scorer.predict_base_probability(&features).expect("predict");
            let from_weights = f64::from(weights.predict(&features));
            let calibrated = calibrate(base, &config);
            max_base_delta = max_base_delta
                .max((base - row.sklearn_base_probability).abs())
                .max((base - row.mobile_onnx_base_probability).abs());
            max_cal_delta = max_cal_delta.max((calibrated - row.calibrated_probability).abs());
            max_weight_delta = max_weight_delta.max((base - from_weights).abs());
            assert_eq!(calibrated >= row.threshold, row.decision);
            assert_eq!(calibrated >= config.threshold, row.decision);
        }
        assert!(max_base_delta < 1e-5, "base delta {max_base_delta}");
        assert!(max_cal_delta < 1e-5, "calibrated delta {max_cal_delta}");
        assert!(max_weight_delta < 1e-5, "weights delta {max_weight_delta}");
    }

    #[test]
    fn feature_hash_is_little_endian_f32_sha256() {
        let features = [1.0_f32; 12];
        let hash = feature_vector_hash(&features);
        assert_eq!(hash.len(), 64);
        assert_ne!(hash, feature_vector_hash(&[0.0_f32; 12]));
    }

    #[test]
    fn threshold_uses_greater_or_equal() {
        let config = ModelConfig::load().expect("config");
        assert!((0.18170608515558545 - config.threshold).abs() < 1e-12);
        let at = config.threshold;
        assert!(at >= config.threshold);
        assert!((at - f64::EPSILON) < config.threshold);
    }
}
