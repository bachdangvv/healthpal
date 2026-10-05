use crate::runtime;

pub use crate::types::{
    AssessmentError, AssessmentRequest, AssessmentResult, AssessmentStatus, ExerciseSession,
    FeatureSlot, HeartRateSample, ModelInfo, RestingHrRecord, SleepSession, SleepStage,
    StepInterval,
};

/// One-time native initialization. Safe to call from the UI isolate and a
/// background isolate; ONNX session pointers never leave Rust.
pub fn init_healthpal_rust() -> Result<ModelInfo, AssessmentError> {
    runtime::init()
}

pub fn model_info() -> Result<ModelInfo, AssessmentError> {
    runtime::model_info()
}

pub fn assess(request: AssessmentRequest) -> Result<AssessmentResult, AssessmentError> {
    runtime::assess(request)
}
