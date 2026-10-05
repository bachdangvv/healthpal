use serde::Deserialize;

use crate::types::{AssessmentError, FEATURE_NAMES, MODEL_VERSION, WINDOW_HOURS};

const CONFIG_JSON: &str =
    include_str!("../assets/healthpal_fatigue_v4/healthpal_fatigue_v4_config.json");

#[derive(Clone, Debug)]
pub struct ModelConfig {
    pub model_name: String,
    pub feature_order: Vec<String>,
    pub window_hours: i32,
    pub low_activity_threshold: i32,
    pub calibration_slope: f64,
    pub calibration_intercept: f64,
    pub threshold: f64,
}

#[derive(Deserialize)]
struct RawConfig {
    model_name: String,
    feature_order: Vec<String>,
    primary_window_hours: i32,
    low_activity_steps_per_hour_threshold: i32,
    calibration: RawCalibration,
    decision_threshold: RawThreshold,
}

#[derive(Deserialize)]
struct RawCalibration {
    slope: f64,
    intercept: f64,
    formula: String,
}

#[derive(Deserialize)]
struct RawThreshold {
    threshold: f64,
}

impl ModelConfig {
    pub fn load() -> Result<Self, AssessmentError> {
        let raw: RawConfig =
            serde_json::from_str(CONFIG_JSON).map_err(|err| AssessmentError::Model {
                message: format!("failed to parse model config: {err}"),
            })?;
        if raw.feature_order != FEATURE_NAMES {
            return Err(AssessmentError::Model {
                message: "config feature_order does not match the locked V4 contract".into(),
            });
        }
        if raw.primary_window_hours != WINDOW_HOURS {
            return Err(AssessmentError::Model {
                message: "config window does not match the locked V4 contract".into(),
            });
        }
        if raw.model_name != MODEL_VERSION {
            return Err(AssessmentError::Model {
                message: format!("unexpected model_name {}", raw.model_name),
            });
        }
        if !raw.formula_is_supported() {
            return Err(AssessmentError::Model {
                message: format!(
                    "unsupported calibration formula: {}",
                    raw.calibration.formula
                ),
            });
        }
        Ok(Self {
            model_name: raw.model_name,
            feature_order: raw.feature_order,
            window_hours: raw.primary_window_hours,
            low_activity_threshold: raw.low_activity_steps_per_hour_threshold,
            calibration_slope: raw.calibration.slope,
            calibration_intercept: raw.calibration.intercept,
            threshold: raw.decision_threshold.threshold,
        })
    }
}

impl RawConfig {
    fn formula_is_supported(&self) -> bool {
        self.calibration.formula
            == "sigmoid(slope * logit(clamp(base_probability,1e-6,1-1e-6)) + intercept)"
    }
}
