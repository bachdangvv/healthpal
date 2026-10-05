use serde::{Deserialize, Serialize};

pub const FEATURE_NAMES: [&str; 12] = [
    "h6_hr_mean",
    "h6_hr_std",
    "h6_hr_median",
    "h6_hr_p25",
    "h6_hr_p75",
    "h6_low250_hr_mean",
    "h6_low250_hr_std",
    "h6_low250_hours",
    "h6_hr_mean_minus_rhr",
    "resting_hr",
    "sleep_minutes",
    "h6_steps_sum",
];

pub const WINDOW_HOURS: i32 = 6;
pub const MIN_VALID_BINS: usize = 3;
pub const LOW_ACTIVITY_STEPS: f64 = 250.0;
pub const STALE_SAMPLE_MS: i64 = 2 * 60 * 60 * 1000;
pub const EXERCISE_SUPPRESS_MS: i64 = 60 * 60 * 1000;
pub const HOUR_MS: i64 = 60 * 60 * 1000;
pub const MODEL_VERSION: &str = "healthpal_fatigue_v4";

pub const REASON_MISSING_SLEEP_D1: &str = "missing_sleep_d1";
pub const REASON_MISSING_RHR_D1: &str = "missing_rhr_d1";
pub const REASON_COVERAGE: &str = "coverage_below_3_of_6";
pub const REASON_STALE: &str = "stale_latest_sample";
pub const REASON_WATERMARK: &str = "watermark_incomplete";
pub const REASON_EXERCISE: &str = "suppressed_during_exercise";
pub const REASON_UNCANONICAL_SLEEP: &str = "uncanonical_sleep";
pub const REASON_MISSING_HR_PERMISSION: &str = "missing_hr_permission";
pub const REASON_MISSING_STEPS_PERMISSION: &str = "missing_steps_permission";
pub const REASON_MISSING_SLEEP_PERMISSION: &str = "missing_sleep_permission";
pub const REASON_MISSING_RHR_PERMISSION: &str = "missing_rhr_permission";
pub const REASON_NO_NEW_DATA: &str = "no_new_data_since_previous";
pub const REASON_MISSING_LOW250_HR: &str = "missing_low250_hr";

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HeartRateSample {
    pub timestamp_utc_ms: i64,
    pub bpm: f64,
    #[serde(default)]
    pub record_id: Option<String>,
    #[serde(default)]
    pub source_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StepInterval {
    pub start_utc_ms: i64,
    pub end_utc_ms: i64,
    pub count: f64,
    #[serde(default)]
    pub record_id: Option<String>,
    #[serde(default)]
    pub source_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RestingHrRecord {
    pub recorded_at_utc_ms: i64,
    pub bpm: f64,
    #[serde(default)]
    pub local_date: Option<String>,
    #[serde(default)]
    pub record_id: Option<String>,
    #[serde(default)]
    pub source_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SleepStage {
    pub start_utc_ms: i64,
    pub end_utc_ms: i64,
    pub stage_type: String,
    #[serde(default)]
    pub record_id: Option<String>,
    #[serde(default)]
    pub source_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SleepSession {
    #[serde(default)]
    pub record_id: Option<String>,
    pub start_utc_ms: i64,
    pub end_utc_ms: i64,
    #[serde(default)]
    pub health_day: Option<String>,
    #[serde(default)]
    pub stages: Vec<SleepStage>,
    #[serde(default)]
    pub asleep_minutes_aggregate: Option<f64>,
    #[serde(default)]
    pub source_id: Option<String>,
    #[serde(default)]
    pub modified_at_utc_ms: Option<i64>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ExerciseSession {
    pub start_utc_ms: i64,
    pub end_utc_ms: i64,
    #[serde(default)]
    pub exercise_type: Option<String>,
    #[serde(default)]
    pub record_id: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AssessmentRequest {
    pub evaluation_time_utc_ms: i64,
    pub timezone_offset_minutes: i32,
    #[serde(default)]
    pub heart_rate_samples: Vec<HeartRateSample>,
    #[serde(default)]
    pub step_intervals: Vec<StepInterval>,
    #[serde(default)]
    pub resting_hr_records: Vec<RestingHrRecord>,
    #[serde(default)]
    pub sleep_sessions: Vec<SleepSession>,
    #[serde(default)]
    pub exercise_sessions: Vec<ExerciseSession>,
    #[serde(default)]
    pub data_watermark_utc_ms: Option<i64>,
    #[serde(default)]
    pub previous_assessment_watermark_utc_ms: Option<i64>,
    #[serde(default)]
    pub preferred_source_id: Option<String>,
    #[serde(default)]
    pub heart_rate_permission: Option<bool>,
    #[serde(default)]
    pub steps_permission: Option<bool>,
    #[serde(default)]
    pub sleep_permission: Option<bool>,
    #[serde(default)]
    pub resting_hr_permission: Option<bool>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AssessmentStatus {
    SignalDetected,
    NoClearSignal,
    InsufficientData,
    SuppressedDuringExercise,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FeatureSlot {
    pub name: String,
    pub value: Option<f64>,
    pub missing_reason: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AssessmentResult {
    pub status: AssessmentStatus,
    pub features: Vec<FeatureSlot>,
    pub missing_reasons: Vec<String>,
    pub base_probability: Option<f64>,
    pub calibrated_probability: Option<f64>,
    pub threshold: f64,
    pub coverage_hours: i32,
    pub valid_bin_count: i32,
    pub latest_sample_at_utc_ms: Option<i64>,
    pub data_freshness_minutes: Option<i32>,
    pub model_version: String,
    pub feature_vector_hash: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ModelInfo {
    pub model_name: String,
    pub model_version: String,
    pub feature_order: Vec<String>,
    pub window_hours: i32,
    pub threshold: f64,
    pub calibration_slope: f64,
    pub calibration_intercept: f64,
    pub low_activity_threshold: i32,
    pub onnx_artifact: String,
}

#[derive(Clone, Debug, thiserror::Error, Serialize, Deserialize)]
pub enum AssessmentError {
    #[error("{code}: {message}")]
    InvalidRequest { code: String, message: String },
    #[error("model error: {message}")]
    Model { message: String },
    #[error("internal error: {message}")]
    Internal { message: String },
}

impl AssessmentError {
    pub fn invalid(code: &str, message: impl Into<String>) -> Self {
        Self::InvalidRequest {
            code: code.to_string(),
            message: message.into(),
        }
    }
}
