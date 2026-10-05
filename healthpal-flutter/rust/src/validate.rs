use crate::types::{AssessmentError, AssessmentRequest};

pub fn validate_and_sort(request: &mut AssessmentRequest) -> Result<(), AssessmentError> {
    if !request.evaluation_time_utc_ms_is_reasonable() {
        return Err(AssessmentError::invalid(
            "invalid_evaluation_time",
            "evaluation_time_utc_ms is out of range",
        ));
    }
    if request.timezone_offset_minutes.abs() > 14 * 60 {
        return Err(AssessmentError::invalid(
            "invalid_timezone_offset",
            "timezone_offset_minutes must be within ±14 hours",
        ));
    }
    let t = request.evaluation_time_utc_ms;
    for sample in &request.heart_rate_samples {
        reject_non_finite("heart_rate.bpm", sample.bpm)?;
        reject_after_t("heart_rate.timestamp_utc_ms", sample.timestamp_utc_ms, t)?;
        if sample.bpm < 0.0 {
            return Err(AssessmentError::invalid(
                "negative_count",
                "heart rate bpm must not be negative",
            ));
        }
    }
    for interval in &request.step_intervals {
        reject_non_finite("step_interval.count", interval.count)?;
        reject_after_t("step_interval.start_utc_ms", interval.start_utc_ms, t)?;
        reject_after_t("step_interval.end_utc_ms", interval.end_utc_ms, t)?;
        if interval.end_utc_ms < interval.start_utc_ms {
            return Err(AssessmentError::invalid(
                "invalid_duration",
                "step interval end is before start",
            ));
        }
        if interval.count < 0.0 {
            return Err(AssessmentError::invalid(
                "negative_count",
                "step count must not be negative",
            ));
        }
    }
    for record in &request.resting_hr_records {
        reject_non_finite("resting_hr.bpm", record.bpm)?;
        reject_after_t(
            "resting_hr.recorded_at_utc_ms",
            record.recorded_at_utc_ms,
            t,
        )?;
        if record.bpm < 0.0 {
            return Err(AssessmentError::invalid(
                "negative_count",
                "resting heart rate must not be negative",
            ));
        }
    }
    for session in &request.sleep_sessions {
        reject_after_t("sleep.start_utc_ms", session.start_utc_ms, t)?;
        reject_after_t("sleep.end_utc_ms", session.end_utc_ms, t)?;
        if session.end_utc_ms < session.start_utc_ms {
            return Err(AssessmentError::invalid(
                "invalid_duration",
                "sleep session end is before start",
            ));
        }
        if let Some(minutes) = session.asleep_minutes_aggregate {
            reject_non_finite("sleep.asleep_minutes_aggregate", minutes)?;
            if minutes < 0.0 {
                return Err(AssessmentError::invalid(
                    "negative_count",
                    "sleep minutes must not be negative",
                ));
            }
        }
        for stage in &session.stages {
            reject_after_t("sleep_stage.start_utc_ms", stage.start_utc_ms, t)?;
            reject_after_t("sleep_stage.end_utc_ms", stage.end_utc_ms, t)?;
            if stage.end_utc_ms < stage.start_utc_ms {
                return Err(AssessmentError::invalid(
                    "invalid_duration",
                    "sleep stage end is before start",
                ));
            }
        }
    }
    for session in &request.exercise_sessions {
        reject_after_t("exercise.start_utc_ms", session.start_utc_ms, t)?;
        // An exercise session may contain T (start <= T < end), so end can be after T.
        if session.end_utc_ms < session.start_utc_ms {
            return Err(AssessmentError::invalid(
                "invalid_duration",
                "exercise session end is before start",
            ));
        }
    }
    if let Some(watermark) = request.data_watermark_utc_ms {
        if watermark > t {
            return Err(AssessmentError::invalid(
                "timestamp_after_evaluation",
                "data_watermark_utc_ms is after T",
            ));
        }
    }
    if let Some(watermark) = request.previous_assessment_watermark_utc_ms {
        if watermark > t {
            return Err(AssessmentError::invalid(
                "timestamp_after_evaluation",
                "previous_assessment_watermark_utc_ms is after T",
            ));
        }
    }

    request
        .heart_rate_samples
        .sort_by_key(|sample| sample.timestamp_utc_ms);
    request
        .step_intervals
        .sort_by_key(|interval| (interval.start_utc_ms, interval.end_utc_ms));
    request
        .resting_hr_records
        .sort_by_key(|record| record.recorded_at_utc_ms);
    request
        .sleep_sessions
        .sort_by_key(|session| (session.start_utc_ms, session.end_utc_ms));
    request
        .exercise_sessions
        .sort_by_key(|session| (session.start_utc_ms, session.end_utc_ms));
    Ok(())
}

fn reject_non_finite(field: &str, value: f64) -> Result<(), AssessmentError> {
    if value.is_finite() {
        Ok(())
    } else {
        Err(AssessmentError::invalid(
            "non_finite_value",
            format!("{field} is NaN or Infinity"),
        ))
    }
}

fn reject_after_t(field: &str, timestamp: i64, t: i64) -> Result<(), AssessmentError> {
    if timestamp > t {
        Err(AssessmentError::invalid(
            "timestamp_after_evaluation",
            format!("{field} is after T"),
        ))
    } else {
        Ok(())
    }
}

impl AssessmentRequest {
    fn evaluation_time_utc_ms_is_reasonable(&self) -> bool {
        chrono::DateTime::from_timestamp_millis(self.evaluation_time_utc_ms).is_some()
    }
}
