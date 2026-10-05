use std::collections::BTreeMap;

use chrono::{Duration, FixedOffset, TimeZone};

use crate::types::{
    AssessmentError, AssessmentRequest, FEATURE_NAMES, HOUR_MS, LOW_ACTIVITY_STEPS, MIN_VALID_BINS,
    REASON_COVERAGE, REASON_MISSING_LOW250_HR, REASON_MISSING_RHR_D1, REASON_MISSING_SLEEP_D1,
    REASON_UNCANONICAL_SLEEP, WINDOW_HOURS,
};

#[derive(Clone, Debug, Default)]
pub struct FeatureVector {
    pub values: [Option<f64>; 12],
    pub missing_reasons: Vec<String>,
    pub coverage_hours: i32,
    pub valid_hr_hours: i32,
    pub valid_step_hours: i32,
    pub latest_sample_at_utc_ms: Option<i64>,
}

impl FeatureVector {
    pub fn all_finite(&self) -> bool {
        self.values
            .iter()
            .all(|value| value.is_some_and(f64::is_finite))
    }

    pub fn as_f32_row(&self) -> Option<[f32; 12]> {
        let mut row = [0.0_f32; 12];
        for (index, value) in self.values.iter().enumerate() {
            let finite = value.filter(|item| item.is_finite())?;
            row[index] = finite as f32;
        }
        Some(row)
    }

    pub fn slots(&self) -> Vec<crate::types::FeatureSlot> {
        FEATURE_NAMES
            .iter()
            .enumerate()
            .map(|(index, name)| crate::types::FeatureSlot {
                name: (*name).to_string(),
                value: self.values[index],
                missing_reason: if self.values[index].is_some_and(f64::is_finite) {
                    None
                } else {
                    Some(format!("missing_{name}"))
                },
            })
            .collect()
    }
}

#[derive(Clone, Debug, Default)]
struct HourBin {
    hr_sum: f64,
    hr_count: usize,
    steps: f64,
    has_steps: bool,
}

pub fn extract(request: &AssessmentRequest) -> FeatureVector {
    let t = request.evaluation_time_utc_ms;
    let window_start = t - i64::from(WINDOW_HOURS) * HOUR_MS;
    let offset = request.timezone_offset_minutes;
    let mut latest = None;
    let mut bins: BTreeMap<i64, HourBin> = BTreeMap::new();

    for sample in &request.heart_rate_samples {
        if sample.timestamp_utc_ms < window_start || sample.timestamp_utc_ms >= t {
            continue;
        }
        let hour_start = local_hour_start_utc(sample.timestamp_utc_ms, offset);
        if hour_start < window_start || hour_start >= t {
            continue;
        }
        let bin = bins.entry(hour_start).or_default();
        bin.hr_sum += sample.bpm;
        bin.hr_count += 1;
        latest = Some(
            latest
                .unwrap_or(sample.timestamp_utc_ms)
                .max(sample.timestamp_utc_ms),
        );
    }

    for interval in &request.step_intervals {
        accumulate_steps(&mut bins, interval, window_start, t, offset, &mut latest);
    }

    let mut hr_values = Vec::new();
    let mut step_values = Vec::new();
    let mut paired = Vec::new();
    for bin in bins.values() {
        let hr = if bin.hr_count > 0 {
            Some(bin.hr_sum / bin.hr_count as f64)
        } else {
            None
        };
        let steps = if bin.has_steps { Some(bin.steps) } else { None };
        if let Some(value) = hr {
            hr_values.push(value);
        }
        if let Some(value) = steps {
            step_values.push(value);
        }
        if let (Some(hr_value), Some(step_value)) = (hr, steps) {
            paired.push((hr_value, step_value));
        }
    }

    let mut vector = FeatureVector {
        coverage_hours: i32::try_from(paired.len()).unwrap_or(i32::MAX),
        valid_hr_hours: i32::try_from(hr_values.len()).unwrap_or(i32::MAX),
        valid_step_hours: i32::try_from(step_values.len()).unwrap_or(i32::MAX),
        latest_sample_at_utc_ms: latest,
        ..FeatureVector::default()
    };

    if hr_values.len() < MIN_VALID_BINS || step_values.len() < MIN_VALID_BINS {
        vector.missing_reasons.push(REASON_COVERAGE.to_string());
    } else {
        let mut sorted_hr = hr_values.clone();
        sorted_hr.sort_by(|a, b| a.total_cmp(b));
        let hr_mean = mean(&hr_values);
        vector.values[0] = Some(hr_mean);
        vector.values[1] = Some(population_std(&hr_values, hr_mean));
        vector.values[2] = Some(quantile_linear(&sorted_hr, 0.5));
        vector.values[3] = Some(quantile_linear(&sorted_hr, 0.25));
        vector.values[4] = Some(quantile_linear(&sorted_hr, 0.75));
        vector.values[11] = Some(step_values.iter().sum());

        let low: Vec<f64> = paired
            .iter()
            .filter(|(_, steps)| *steps <= LOW_ACTIVITY_STEPS)
            .map(|(hr, _)| *hr)
            .collect();
        vector.values[7] = Some(low.len() as f64);
        if low.is_empty() {
            vector
                .missing_reasons
                .push(REASON_MISSING_LOW250_HR.to_string());
        } else {
            let low_mean = mean(&low);
            vector.values[5] = Some(low_mean);
            vector.values[6] = Some(population_std(&low, low_mean));
        }
    }

    match canonical_sleep_minutes(request) {
        Ok(minutes) => vector.values[10] = Some(minutes),
        Err(reason) => vector.missing_reasons.push(reason),
    }
    match canonical_resting_hr(request) {
        Ok(resting_hr) => {
            vector.values[9] = Some(resting_hr);
            if let Some(hr_mean) = vector.values[0] {
                vector.values[8] = Some(hr_mean - resting_hr);
            }
        }
        Err(reason) => vector.missing_reasons.push(reason),
    }
    vector
}

fn accumulate_steps(
    bins: &mut BTreeMap<i64, HourBin>,
    interval: &crate::types::StepInterval,
    window_start: i64,
    t: i64,
    offset: i32,
    latest: &mut Option<i64>,
) {
    let original_duration = interval.end_utc_ms.saturating_sub(interval.start_utc_ms);
    if original_duration <= 0 {
        return;
    }
    let clipped_start = interval.start_utc_ms.max(window_start);
    let clipped_end = interval.end_utc_ms.min(t);
    if clipped_end <= clipped_start {
        return;
    }
    let clipped_duration = clipped_end - clipped_start;
    let clipped_count = interval.count * (clipped_duration as f64 / original_duration as f64);
    let mut cursor = local_hour_start_utc(clipped_start, offset);
    let last_hour = local_hour_start_utc(clipped_end.saturating_sub(1), offset);
    while cursor <= last_hour {
        if cursor >= window_start && cursor < t {
            let hour_end = cursor.saturating_add(HOUR_MS);
            let overlap_start = clipped_start.max(cursor);
            let overlap_end = clipped_end.min(hour_end);
            let overlap = overlap_end.saturating_sub(overlap_start);
            if overlap > 0 {
                let bin = bins.entry(cursor).or_default();
                bin.steps += clipped_count * (overlap as f64 / clipped_duration as f64);
                bin.has_steps = true;
            }
        }
        match cursor.checked_add(HOUR_MS) {
            Some(next) => cursor = next,
            None => break,
        }
    }
    *latest = Some(latest.unwrap_or(clipped_end).max(clipped_end));
}

pub fn local_hour_start_utc(utc_ms: i64, offset_minutes: i32) -> i64 {
    let offset_ms = i64::from(offset_minutes) * 60_000;
    let local_ms = utc_ms.saturating_add(offset_ms);
    let rem = local_ms.rem_euclid(HOUR_MS);
    local_ms.saturating_sub(rem).saturating_sub(offset_ms)
}

pub fn local_date_string(utc_ms: i64, offset_minutes: i32) -> Result<String, AssessmentError> {
    Ok(local_naive_date(utc_ms, offset_minutes)?
        .format("%Y-%m-%d")
        .to_string())
}

pub fn d_minus_1(utc_ms: i64, offset_minutes: i32) -> Result<String, AssessmentError> {
    let date = local_naive_date(utc_ms, offset_minutes)?;
    let previous = date
        .checked_sub_signed(Duration::days(1))
        .ok_or_else(|| AssessmentError::invalid("invalid_evaluation_time", "cannot compute D-1"))?;
    Ok(previous.format("%Y-%m-%d").to_string())
}

fn local_naive_date(
    utc_ms: i64,
    offset_minutes: i32,
) -> Result<chrono::NaiveDate, AssessmentError> {
    let offset = FixedOffset::east_opt(offset_minutes * 60).ok_or_else(|| {
        AssessmentError::invalid(
            "invalid_timezone_offset",
            "timezone offset is not a valid fixed offset",
        )
    })?;
    let utc = chrono::DateTime::from_timestamp_millis(utc_ms).ok_or_else(|| {
        AssessmentError::invalid(
            "invalid_evaluation_time",
            "evaluation time is not a valid timestamp",
        )
    })?;
    Ok(offset.from_utc_datetime(&utc.naive_utc()).date_naive())
}

fn mean(values: &[f64]) -> f64 {
    values.iter().sum::<f64>() / values.len() as f64
}

fn population_std(values: &[f64], mean: f64) -> f64 {
    if values.is_empty() {
        return f64::NAN;
    }
    let variance = values
        .iter()
        .map(|value| {
            let delta = value - mean;
            delta * delta
        })
        .sum::<f64>()
        / values.len() as f64;
    variance.sqrt()
}

fn quantile_linear(sorted: &[f64], q: f64) -> f64 {
    let n = sorted.len();
    if n == 0 {
        return f64::NAN;
    }
    if n == 1 {
        return sorted[0];
    }
    let pos = q * (n - 1) as f64;
    let lo = pos.floor() as usize;
    let hi = pos.ceil() as usize;
    let frac = pos - lo as f64;
    sorted[lo].mul_add(1.0 - frac, sorted[hi] * frac)
}

fn canonical_sleep_minutes(request: &AssessmentRequest) -> Result<f64, String> {
    let d1 = d_minus_1(
        request.evaluation_time_utc_ms,
        request.timezone_offset_minutes,
    )
    .map_err(|_| REASON_MISSING_SLEEP_D1.to_string())?;
    let mut sessions = Vec::new();
    let mut seen_ids = std::collections::HashSet::new();
    for session in &request.sleep_sessions {
        let health_day = match &session.health_day {
            Some(day) => day.clone(),
            None => local_date_string(session.end_utc_ms, request.timezone_offset_minutes)
                .map_err(|_| REASON_MISSING_SLEEP_D1.to_string())?,
        };
        if health_day != d1 {
            continue;
        }
        let identity = session.record_id.clone().unwrap_or_else(|| {
            format!(
                "{}:{}:{}:{}",
                session.source_id.as_deref().unwrap_or(""),
                session.start_utc_ms,
                session.end_utc_ms,
                session.asleep_minutes_aggregate.unwrap_or_default()
            )
        });
        if !seen_ids.insert(identity) {
            continue;
        }
        sessions.push(session);
    }
    if sessions.is_empty() {
        return Err(REASON_MISSING_SLEEP_D1.to_string());
    }
    if sessions.len() > 1 {
        sessions.sort_by(|left, right| {
            sleep_rank(right, request.preferred_source_id.as_deref())
                .cmp(&sleep_rank(left, request.preferred_source_id.as_deref()))
        });
        let best = sleep_rank(sessions[0], request.preferred_source_id.as_deref());
        let second = sleep_rank(sessions[1], request.preferred_source_id.as_deref());
        if best == second {
            return Err(REASON_UNCANONICAL_SLEEP.to_string());
        }
    }
    Ok(sleep_minutes(sessions[0]))
}

fn sleep_rank(
    session: &crate::types::SleepSession,
    preferred_source: Option<&str>,
) -> (u8, u8, u8, i64, i64) {
    let preferred = match (preferred_source, session.source_id.as_deref()) {
        (Some(want), Some(got)) if want == got => 1,
        _ => 0,
    };
    let stage_coverage = u8::from(has_asleep_stage_coverage(session));
    let duration_ms = session.end_utc_ms.saturating_sub(session.start_utc_ms);
    let two_hours = 2 * HOUR_MS;
    let fourteen_hours = 14 * HOUR_MS;
    let in_range = u8::from((two_hours..=fourteen_hours).contains(&duration_ms));
    let modified = session.modified_at_utc_ms.unwrap_or(session.end_utc_ms);
    (preferred, stage_coverage, in_range, duration_ms, modified)
}

fn has_asleep_stage_coverage(session: &crate::types::SleepSession) -> bool {
    session
        .stages
        .iter()
        .any(|stage| is_asleep_stage(&stage.stage_type))
}

fn is_asleep_stage(stage_type: &str) -> bool {
    matches!(
        stage_type.to_ascii_lowercase().as_str(),
        "light" | "deep" | "rem" | "asleep"
    )
}

fn sleep_minutes(session: &crate::types::SleepSession) -> f64 {
    let session_ms = session.end_utc_ms.saturating_sub(session.start_utc_ms);
    if session_ms == 0 {
        return 0.0;
    }
    let max_minutes = session_ms as f64 / 60_000.0;
    let mut unique: Vec<&crate::types::SleepStage> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for stage in &session.stages {
        let start = stage.start_utc_ms.max(session.start_utc_ms);
        let end = stage.end_utc_ms.min(session.end_utc_ms);
        if end <= start {
            continue;
        }
        let key = (
            stage.record_id.clone().unwrap_or_default(),
            stage.source_id.clone().unwrap_or_default(),
            start,
            end,
            stage.stage_type.to_ascii_lowercase(),
        );
        if seen.insert(key) {
            unique.push(stage);
        }
    }
    let awake = union_intervals(
        unique
            .iter()
            .filter(|stage| stage.stage_type.eq_ignore_ascii_case("awake"))
            .filter_map(|stage| clamped(stage, session)),
    );
    let detailed_asleep = union_intervals(
        unique
            .iter()
            .filter(|stage| {
                let kind = stage.stage_type.to_ascii_lowercase();
                kind == "light" || kind == "deep" || kind == "rem"
            })
            .filter_map(|stage| clamped(stage, session)),
    );
    let detailed_coverage = union_intervals(
        unique
            .iter()
            .filter(|stage| {
                let kind = stage.stage_type.to_ascii_lowercase();
                kind == "light" || kind == "deep" || kind == "rem" || kind == "awake"
            })
            .filter_map(|stage| clamped(stage, session)),
    );
    let generic_asleep = union_intervals(
        unique
            .iter()
            .filter(|stage| stage.stage_type.eq_ignore_ascii_case("asleep"))
            .filter_map(|stage| clamped(stage, session)),
    );
    let generic_fill = subtract_intervals(
        subtract_intervals(generic_asleep, &detailed_coverage),
        &awake,
    );
    let mut asleep = detailed_asleep;
    asleep.extend(generic_fill);
    let asleep = subtract_intervals(union_intervals(asleep), &awake);
    let has_reliable = unique
        .iter()
        .any(|stage| is_asleep_stage(&stage.stage_type));
    let minutes = if has_reliable {
        asleep
            .iter()
            .map(|(start, end)| (end - start) as f64 / 60_000.0)
            .sum()
    } else if let Some(aggregate) = session.asleep_minutes_aggregate {
        aggregate
    } else {
        max_minutes
    };
    minutes.clamp(0.0, max_minutes)
}

fn clamped(
    stage: &crate::types::SleepStage,
    session: &crate::types::SleepSession,
) -> Option<(i64, i64)> {
    let start = stage.start_utc_ms.max(session.start_utc_ms);
    let end = stage.end_utc_ms.min(session.end_utc_ms);
    (end > start).then_some((start, end))
}

fn union_intervals(raw: impl IntoIterator<Item = (i64, i64)>) -> Vec<(i64, i64)> {
    let mut items: Vec<(i64, i64)> = raw.into_iter().filter(|(s, e)| e > s).collect();
    if items.is_empty() {
        return Vec::new();
    }
    items.sort_by_key(|item| item.0);
    let mut merged = Vec::new();
    let mut current = items[0];
    for next in items.into_iter().skip(1) {
        if next.0 <= current.1 {
            current.1 = current.1.max(next.1);
        } else {
            merged.push(current);
            current = next;
        }
    }
    merged.push(current);
    merged
}

fn subtract_intervals(base: Vec<(i64, i64)>, cut: &[(i64, i64)]) -> Vec<(i64, i64)> {
    let mut result = base;
    for hole in cut {
        let mut next = Vec::new();
        for item in result {
            if hole.1 <= item.0 || hole.0 >= item.1 {
                next.push(item);
                continue;
            }
            if hole.0 > item.0 {
                next.push((item.0, hole.0));
            }
            if hole.1 < item.1 {
                next.push((hole.1, item.1));
            }
        }
        result = next;
    }
    result
}

fn canonical_resting_hr(request: &AssessmentRequest) -> Result<f64, String> {
    let d1 = d_minus_1(
        request.evaluation_time_utc_ms,
        request.timezone_offset_minutes,
    )
    .map_err(|_| REASON_MISSING_RHR_D1.to_string())?;
    let mut values = Vec::new();
    for record in &request.resting_hr_records {
        let local_date = match &record.local_date {
            Some(day) => day.clone(),
            None => local_date_string(record.recorded_at_utc_ms, request.timezone_offset_minutes)
                .map_err(|_| REASON_MISSING_RHR_D1.to_string())?,
        };
        if local_date != d1 {
            continue;
        }
        if let Some(preferred) = request.preferred_source_id.as_deref() {
            if record.source_id.as_deref() != Some(preferred) {
                continue;
            }
        }
        values.push(record.bpm);
    }
    if values.is_empty() {
        return Err(REASON_MISSING_RHR_D1.to_string());
    }
    values.sort_by(|a, b| a.total_cmp(b));
    Ok(quantile_linear(&values, 0.5))
}

#[cfg(test)]
mod tests {
    use super::{population_std, quantile_linear};

    #[test]
    fn numpy_quantile_and_std_examples() {
        let mut values = vec![70.0_f64, 72.0, 74.0, 76.0, 78.0, 80.0];
        values.sort_by(|a, b| a.total_cmp(b));
        let mean = values.iter().sum::<f64>() / values.len() as f64;
        assert!((quantile_linear(&values, 0.25) - 72.5).abs() < 1e-12);
        assert!((quantile_linear(&values, 0.75) - 77.5).abs() < 1e-12);
        assert!((quantile_linear(&values, 0.5) - 75.0).abs() < 1e-12);
        assert!((population_std(&values, mean) - 3.415650255319866).abs() < 1e-12);
    }
}
