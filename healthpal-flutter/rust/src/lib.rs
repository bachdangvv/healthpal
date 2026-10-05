//! On-device HealthPal V4 fatigue assessment.
//!
//! Dart never receives ONNX Runtime pointers. Public entry points are
//! `init`, `model_info`, and `assess`.

pub mod api;
mod config;
mod eligibility;
mod features;
mod ffi;
mod inference;
mod runtime;
mod types;
mod validate;

pub use runtime::{assess, init, model_info};
pub use types::{
    AssessmentError, AssessmentRequest, AssessmentResult, AssessmentStatus, ExerciseSession,
    FeatureSlot, HeartRateSample, ModelInfo, RestingHrRecord, SleepSession, SleepStage,
    StepInterval, FEATURE_NAMES, MODEL_VERSION,
};
