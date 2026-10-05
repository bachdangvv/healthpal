use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::OnceLock;

use parking_lot::Mutex;

use crate::config::ModelConfig;
use crate::eligibility::collect_reasons;
use crate::features::extract;
use crate::inference::{calibrate, feature_vector_hash, OnnxScorer};
use crate::types::{
    AssessmentError, AssessmentRequest, AssessmentResult, AssessmentStatus, ModelInfo,
    MODEL_VERSION,
};
use crate::validate::validate_and_sort;

struct Runtime {
    config: ModelConfig,
    scorer: Mutex<OnnxScorer>,
}

static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();

fn runtime() -> Result<&'static Runtime, AssessmentError> {
    match RUNTIME.get_or_init(|| {
        let config = ModelConfig::load().map_err(|err| err.to_string())?;
        let scorer = OnnxScorer::load().map_err(|err| err.to_string())?;
        Ok(Runtime {
            config,
            scorer: Mutex::new(scorer),
        })
    }) {
        Ok(runtime) => Ok(runtime),
        Err(message) => Err(AssessmentError::Model {
            message: message.clone(),
        }),
    }
}

pub fn init() -> Result<ModelInfo, AssessmentError> {
    Ok(model_info_from(runtime()?.config.clone()))
}

pub fn model_info() -> Result<ModelInfo, AssessmentError> {
    Ok(model_info_from(runtime()?.config.clone()))
}

pub fn assess(request: AssessmentRequest) -> Result<AssessmentResult, AssessmentError> {
    match catch_unwind(AssertUnwindSafe(|| assess_inner(request))) {
        Ok(result) => result,
        Err(_) => Err(AssessmentError::Internal {
            message: "native assessment panicked".into(),
        }),
    }
}

fn assess_inner(mut request: AssessmentRequest) -> Result<AssessmentResult, AssessmentError> {
    validate_and_sort(&mut request)?;
    let runtime = runtime()?;
    let features = extract(&request);
    let (mut status, missing_reasons) = collect_reasons(&request, &features);
    let mut base_probability = None;
    let mut calibrated_probability = None;
    let mut hash = String::new();

    if status != AssessmentStatus::SuppressedDuringExercise
        && missing_reasons.is_empty()
        && features.all_finite()
    {
        let row = features
            .as_f32_row()
            .ok_or_else(|| AssessmentError::Model {
                message: "feature vector was not finite after eligibility passed".into(),
            })?;
        hash = feature_vector_hash(&row);
        let mut scorer = runtime.scorer.lock();
        let base = scorer.predict_base_probability(&row)?;
        let calibrated = calibrate(base, &runtime.config);
        base_probability = Some(base);
        calibrated_probability = Some(calibrated);
        status = if calibrated >= runtime.config.threshold {
            AssessmentStatus::SignalDetected
        } else {
            AssessmentStatus::NoClearSignal
        };
    }

    let freshness = features.latest_sample_at_utc_ms.map(|latest| {
        let delta = request.evaluation_time_utc_ms.saturating_sub(latest);
        i32::try_from(delta / 60_000).unwrap_or(i32::MAX)
    });

    Ok(AssessmentResult {
        status,
        features: features.slots(),
        missing_reasons,
        base_probability,
        calibrated_probability,
        threshold: runtime.config.threshold,
        coverage_hours: features.coverage_hours,
        valid_bin_count: features.valid_hr_hours.min(features.valid_step_hours),
        latest_sample_at_utc_ms: features.latest_sample_at_utc_ms,
        data_freshness_minutes: freshness,
        model_version: MODEL_VERSION.to_string(),
        feature_vector_hash: hash,
    })
}

fn model_info_from(config: ModelConfig) -> ModelInfo {
    ModelInfo {
        model_name: config.model_name,
        model_version: MODEL_VERSION.to_string(),
        feature_order: config.feature_order,
        window_hours: config.window_hours,
        threshold: config.threshold,
        calibration_slope: config.calibration_slope,
        calibration_intercept: config.calibration_intercept,
        low_activity_threshold: config.low_activity_threshold,
        onnx_artifact: "healthpal_fatigue_v4_mobile.onnx".into(),
    }
}
