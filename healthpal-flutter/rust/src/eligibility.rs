use crate::features::FeatureVector;
use crate::types::{
    AssessmentRequest, AssessmentStatus, EXERCISE_SUPPRESS_MS, REASON_EXERCISE,
    REASON_MISSING_HR_PERMISSION, REASON_MISSING_RHR_PERMISSION, REASON_MISSING_SLEEP_PERMISSION,
    REASON_MISSING_STEPS_PERMISSION, REASON_NO_NEW_DATA, REASON_STALE, REASON_WATERMARK,
    STALE_SAMPLE_MS,
};

pub fn permission_reasons(request: &AssessmentRequest) -> Vec<String> {
    let mut reasons = Vec::new();
    if request.heart_rate_permission == Some(false) {
        reasons.push(REASON_MISSING_HR_PERMISSION.to_string());
    }
    if request.steps_permission == Some(false) {
        reasons.push(REASON_MISSING_STEPS_PERMISSION.to_string());
    }
    if request.sleep_permission == Some(false) {
        reasons.push(REASON_MISSING_SLEEP_PERMISSION.to_string());
    }
    if request.resting_hr_permission == Some(false) {
        reasons.push(REASON_MISSING_RHR_PERMISSION.to_string());
    }
    reasons
}

pub fn exercise_suppressed(request: &AssessmentRequest) -> bool {
    let t = request.evaluation_time_utc_ms;
    request.exercise_sessions.iter().any(|session| {
        let contains_t = session.start_utc_ms <= t && t < session.end_utc_ms;
        let ended_recently =
            session.end_utc_ms <= t && t.saturating_sub(session.end_utc_ms) <= EXERCISE_SUPPRESS_MS;
        contains_t || ended_recently
    })
}

pub fn watermark_incomplete(request: &AssessmentRequest) -> bool {
    request
        .data_watermark_utc_ms
        .is_some_and(|watermark| watermark < request.evaluation_time_utc_ms)
}

pub fn no_new_data(request: &AssessmentRequest) -> bool {
    let Some(previous) = request.previous_assessment_watermark_utc_ms else {
        return false;
    };
    let newer_hr = request
        .heart_rate_samples
        .iter()
        .any(|sample| sample.timestamp_utc_ms > previous);
    let newer_steps = request
        .step_intervals
        .iter()
        .any(|interval| interval.end_utc_ms > previous || interval.start_utc_ms > previous);
    !(newer_hr || newer_steps)
}

pub fn stale_latest_sample(request: &AssessmentRequest, features: &FeatureVector) -> bool {
    match features.latest_sample_at_utc_ms {
        Some(latest) => request.evaluation_time_utc_ms.saturating_sub(latest) > STALE_SAMPLE_MS,
        None => true,
    }
}

pub fn collect_reasons(
    request: &AssessmentRequest,
    features: &FeatureVector,
) -> (AssessmentStatus, Vec<String>) {
    if exercise_suppressed(request) {
        return (
            AssessmentStatus::SuppressedDuringExercise,
            vec![REASON_EXERCISE.to_string()],
        );
    }

    let mut reasons = permission_reasons(request);
    if no_new_data(request) {
        reasons.push(REASON_NO_NEW_DATA.to_string());
    }
    if watermark_incomplete(request) {
        reasons.push(REASON_WATERMARK.to_string());
    }
    if stale_latest_sample(request, features) {
        reasons.push(REASON_STALE.to_string());
    }
    for reason in &features.missing_reasons {
        if !reasons.contains(reason) {
            reasons.push(reason.clone());
        }
    }
    if reasons.is_empty() {
        (AssessmentStatus::NoClearSignal, reasons)
    } else {
        (AssessmentStatus::InsufficientData, reasons)
    }
}
