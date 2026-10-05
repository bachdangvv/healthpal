use std::fs;
use std::path::PathBuf;

use healthpal_core::{
    assess, init, model_info, AssessmentError, AssessmentRequest, AssessmentStatus,
    ExerciseSession, HeartRateSample, SleepSession, SleepStage, StepInterval, FEATURE_NAMES,
};
use serde::Deserialize;

fn testdata(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("testdata")
        .join(name)
}

fn read_json<T: for<'de> Deserialize<'de>>(name: &str) -> T {
    serde_json::from_str(&fs::read_to_string(testdata(name)).expect("testdata")).expect("json")
}

fn request_from_value(value: serde_json::Value) -> AssessmentRequest {
    serde_json::from_value(value).expect("request")
}

#[test]
fn init_and_model_info_expose_locked_contract() {
    let info = init().expect("init");
    let again = model_info().expect("model_info");
    assert_eq!(info.model_version, "healthpal_fatigue_v4");
    assert_eq!(again.feature_order, FEATURE_NAMES);
    assert_eq!(info.window_hours, 6);
    assert!((info.threshold - 0.18170608515558545).abs() < 1e-12);
    assert!((info.calibration_slope - 0.7806493861342522).abs() < 1e-12);
    assert!((info.calibration_intercept + 1.2659313281484506).abs() < 1e-12);
    assert_eq!(info.onnx_artifact, "healthpal_fatigue_v4_mobile.onnx");
}

#[test]
fn feature_extraction_matches_python_training_fixtures() {
    let fixtures: Vec<serde_json::Value> = read_json("feature_parity.json");
    assert!(fixtures.len() >= 100);
    for fixture in fixtures.iter().take(100) {
        let request = request_from_value(fixture["request"].clone());
        let expected = fixture["expected_features"].as_object().expect("features");
        let result = assess(request).expect("assess");
        for name in FEATURE_NAMES {
            let slot = result
                .features
                .iter()
                .find(|item| item.name == name)
                .expect("slot");
            let Some(expected_value) = expected[name].as_f64() else {
                assert!(
                    slot.value.is_none(),
                    "{} {} should be missing, got {:?}",
                    fixture["id"],
                    name,
                    slot.value
                );
                continue;
            };
            let actual = slot.value.expect(name);
            let delta = (actual - expected_value).abs();
            assert!(
                delta < 1e-5,
                "{} {} delta {delta} actual={actual} expected={expected_value}",
                fixture["id"],
                name
            );
        }
    }
}

#[test]
fn scored_assessment_returns_hash_and_both_probabilities() {
    let payload: serde_json::Value = read_json("boundary.json");
    let request = request_from_value(payload["hour_aligned"]["request"].clone());
    let result = assess(request).expect("assess");
    assert!(
        result.status == AssessmentStatus::SignalDetected
            || result.status == AssessmentStatus::NoClearSignal
    );
    let base = result.base_probability.expect("base");
    let calibrated = result.calibrated_probability.expect("calibrated");
    assert!((0.0..=1.0).contains(&base));
    assert!((0.0..=1.0).contains(&calibrated));
    assert_eq!(result.feature_vector_hash.len(), 64);
    if calibrated >= result.threshold {
        assert_eq!(result.status, AssessmentStatus::SignalDetected);
    } else {
        assert_eq!(result.status, AssessmentStatus::NoClearSignal);
    }
}

#[test]
fn boundary_window_midnight_and_low_activity_250() {
    let payload: serde_json::Value = read_json("boundary.json");
    let request = request_from_value(payload["hour_aligned"]["request"].clone());
    let expected = payload["hour_aligned"]["expected_features"]
        .as_object()
        .expect("expected");
    let result = assess(request.clone()).expect("assess");
    assert_ne!(result.status, AssessmentStatus::InsufficientData);
    for name in FEATURE_NAMES {
        let actual = result
            .features
            .iter()
            .find(|item| item.name == name)
            .and_then(|item| item.value)
            .expect(name);
        let expected_value = expected[name].as_f64().expect("f64");
        assert!(
            (actual - expected_value).abs() < 1e-5,
            "{name} actual={actual} expected={expected_value}"
        );
    }

    let mut with_t = request.clone();
    with_t.heart_rate_samples.push(HeartRateSample {
        timestamp_utc_ms: request.evaluation_time_utc_ms,
        bpm: 180.0,
        record_id: None,
        source_id: None,
    });
    let excluded = assess(with_t).expect("sample at T is allowed but excluded from the window");
    let mean = excluded
        .features
        .iter()
        .find(|item| item.name == "h6_hr_mean")
        .and_then(|item| item.value)
        .unwrap();
    assert!((mean - expected["h6_hr_mean"].as_f64().unwrap()).abs() < 1e-5);

    let mut before_window = request.clone();
    before_window.heart_rate_samples.push(HeartRateSample {
        timestamp_utc_ms: request.evaluation_time_utc_ms - 6 * 3_600_000 - 1,
        bpm: 180.0,
        record_id: None,
        source_id: None,
    });
    let too_old = assess(before_window).expect("sample before T-6h excluded");
    let mean = too_old
        .features
        .iter()
        .find(|item| item.name == "h6_hr_mean")
        .and_then(|item| item.value)
        .unwrap();
    assert!((mean - expected["h6_hr_mean"].as_f64().unwrap()).abs() < 1e-5);

    let mut included = request.clone();
    included.heart_rate_samples.push(HeartRateSample {
        timestamp_utc_ms: request.evaluation_time_utc_ms - 6 * 3_600_000,
        bpm: 180.0,
        record_id: None,
        source_id: None,
    });
    let at_start = assess(included).expect("T-6h included");
    let mean = at_start
        .features
        .iter()
        .find(|item| item.name == "h6_hr_mean")
        .and_then(|item| item.value)
        .unwrap();
    assert!((mean - expected["h6_hr_mean"].as_f64().unwrap()).abs() > 1e-3);

    let midnight_t = payload["midnight"]["evaluation_time_utc_ms"]
        .as_i64()
        .unwrap();
    let mut midnight = request.clone();
    midnight.evaluation_time_utc_ms = midnight_t;
    midnight.data_watermark_utc_ms = Some(midnight_t);
    midnight.sleep_sessions[0].health_day = Some("2021-05-25".into());
    midnight.resting_hr_records[0].local_date = Some("2021-05-25".into());
    let result = assess(midnight).expect("midnight D-1");
    assert!(
        !result
            .missing_reasons
            .iter()
            .any(|item| item == "missing_sleep_d1" || item == "missing_rhr_d1"),
        "midnight assessment should use local date D-1 = 2021-05-25, got {:?}",
        result.missing_reasons
    );
}

#[test]
fn validation_rejects_nan_infinity_negative_and_future() {
    let payload: serde_json::Value = read_json("boundary.json");
    let base = request_from_value(payload["hour_aligned"]["request"].clone());

    let mut nan = base.clone();
    nan.heart_rate_samples[0].bpm = f64::NAN;
    assert!(matches!(
        assess(nan),
        Err(AssessmentError::InvalidRequest { code, .. }) if code == "non_finite_value"
    ));

    let mut inf = base.clone();
    inf.step_intervals[0].count = f64::INFINITY;
    assert!(matches!(
        assess(inf),
        Err(AssessmentError::InvalidRequest { code, .. }) if code == "non_finite_value"
    ));

    let mut negative = base.clone();
    negative.step_intervals[0].count = -1.0;
    assert!(matches!(
        assess(negative),
        Err(AssessmentError::InvalidRequest { code, .. }) if code == "negative_count"
    ));

    let mut duration = base.clone();
    duration.step_intervals[0].end_utc_ms = duration.step_intervals[0].start_utc_ms - 1;
    assert!(matches!(
        assess(duration),
        Err(AssessmentError::InvalidRequest { code, .. }) if code == "invalid_duration"
    ));

    let mut future = base.clone();
    future.heart_rate_samples[0].timestamp_utc_ms = base.evaluation_time_utc_ms + 1;
    assert!(matches!(
        assess(future),
        Err(AssessmentError::InvalidRequest { code, .. }) if code == "timestamp_after_evaluation"
    ));
}

#[test]
fn eligibility_reasons_are_stable() {
    let payload: serde_json::Value = read_json("boundary.json");
    let base = request_from_value(payload["hour_aligned"]["request"].clone());

    let mut missing_perm = base.clone();
    missing_perm.sleep_permission = Some(false);
    let result = assess(missing_perm).expect("typed result");
    assert_eq!(result.status, AssessmentStatus::InsufficientData);
    assert!(result
        .missing_reasons
        .iter()
        .any(|item| item == "missing_sleep_permission"));

    let mut coverage = base.clone();
    coverage.heart_rate_samples.truncate(2);
    let result = assess(coverage).expect("coverage");
    assert!(result
        .missing_reasons
        .iter()
        .any(|item| item == "coverage_below_3_of_6"));

    let mut sleep = base.clone();
    sleep.sleep_sessions.clear();
    let result = assess(sleep).expect("sleep");
    assert!(result
        .missing_reasons
        .iter()
        .any(|item| item == "missing_sleep_d1"));

    let mut rhr = base.clone();
    rhr.resting_hr_records.clear();
    let result = assess(rhr).expect("rhr");
    assert!(result
        .missing_reasons
        .iter()
        .any(|item| item == "missing_rhr_d1"));

    let mut stale = base.clone();
    stale.evaluation_time_utc_ms += 3 * 3_600_000;
    stale.data_watermark_utc_ms = Some(stale.evaluation_time_utc_ms);
    let result = assess(stale).expect("stale");
    assert!(result
        .missing_reasons
        .iter()
        .any(|item| item == "stale_latest_sample"));

    let mut watermark = base.clone();
    watermark.data_watermark_utc_ms = Some(watermark.evaluation_time_utc_ms - 1);
    let result = assess(watermark).expect("watermark");
    assert!(result
        .missing_reasons
        .iter()
        .any(|item| item == "watermark_incomplete"));

    let mut exercise = base.clone();
    exercise.exercise_sessions.push(ExerciseSession {
        start_utc_ms: exercise.evaluation_time_utc_ms - 30 * 60_000,
        end_utc_ms: exercise.evaluation_time_utc_ms + 10 * 60_000,
        exercise_type: Some("running".into()),
        record_id: None,
    });
    let result = assess(exercise).expect("exercise");
    assert_eq!(result.status, AssessmentStatus::SuppressedDuringExercise);
    assert_eq!(
        result.missing_reasons,
        vec!["suppressed_during_exercise".to_string()]
    );

    let mut ended = base.clone();
    ended.exercise_sessions.push(ExerciseSession {
        start_utc_ms: ended.evaluation_time_utc_ms - 90 * 60_000,
        end_utc_ms: ended.evaluation_time_utc_ms - 60 * 60_000,
        exercise_type: Some("cycling".into()),
        record_id: None,
    });
    let result = assess(ended).expect("ended 60m");
    assert_eq!(result.status, AssessmentStatus::SuppressedDuringExercise);

    let mut previous = base.clone();
    previous.previous_assessment_watermark_utc_ms = Some(previous.evaluation_time_utc_ms);
    let result = assess(previous).expect("no new data");
    assert!(result
        .missing_reasons
        .iter()
        .any(|item| item == "no_new_data_since_previous"));

    let mut dup_sleep = base.clone();
    let original = dup_sleep.sleep_sessions[0].clone();
    dup_sleep.sleep_sessions.push(SleepSession {
        record_id: Some("sleep-d1-b".into()),
        start_utc_ms: original.start_utc_ms,
        end_utc_ms: original.end_utc_ms,
        health_day: original.health_day.clone(),
        stages: original.stages.clone(),
        asleep_minutes_aggregate: original.asleep_minutes_aggregate,
        source_id: original.source_id.clone(),
        modified_at_utc_ms: original.modified_at_utc_ms,
    });
    let result = assess(dup_sleep).expect("uncanonical");
    assert!(result
        .missing_reasons
        .iter()
        .any(|item| item == "uncanonical_sleep"));
}

#[test]
fn sleep_stages_sum_asleep_only_and_input_is_sorted() {
    let payload: serde_json::Value = read_json("boundary.json");
    let mut request = request_from_value(payload["hour_aligned"]["request"].clone());
    request.sleep_sessions[0].stages = vec![
        SleepStage {
            start_utc_ms: request.sleep_sessions[0].start_utc_ms,
            end_utc_ms: request.sleep_sessions[0].start_utc_ms + 10 * 60_000,
            stage_type: "awake".into(),
            record_id: None,
            source_id: None,
        },
        SleepStage {
            start_utc_ms: request.sleep_sessions[0].start_utc_ms + 10 * 60_000,
            end_utc_ms: request.sleep_sessions[0].start_utc_ms + 70 * 60_000,
            stage_type: "light".into(),
            record_id: None,
            source_id: None,
        },
        SleepStage {
            start_utc_ms: request.sleep_sessions[0].start_utc_ms + 70 * 60_000,
            end_utc_ms: request.sleep_sessions[0].start_utc_ms + 100 * 60_000,
            stage_type: "deep".into(),
            record_id: None,
            source_id: None,
        },
    ];
    request.heart_rate_samples.reverse();
    request.step_intervals.reverse();
    let result = assess(request).expect("stages");
    let sleep = result
        .features
        .iter()
        .find(|item| item.name == "sleep_minutes")
        .and_then(|item| item.value)
        .unwrap();
    assert!((sleep - 90.0).abs() < 1e-9);
}

#[test]
fn fuzz_malformed_inputs_do_not_panic() {
    let payload: serde_json::Value = read_json("boundary.json");
    let base = request_from_value(payload["hour_aligned"]["request"].clone());
    let t = base.evaluation_time_utc_ms;
    let mut seed: u64 = 0x9e37_79b9_7f4a_7c15;
    for _ in 0..200 {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
        let mut request = base.clone();
        request.timezone_offset_minutes = (seed % 1801) as i32 - 900;
        if seed.is_multiple_of(7) {
            request.heart_rate_samples.push(HeartRateSample {
                timestamp_utc_ms: t - (seed as i64 % (8 * 3_600_000)),
                bpm: ((seed % 200) as f64) + 40.0,
                record_id: None,
                source_id: None,
            });
        }
        if seed.is_multiple_of(11) {
            request.step_intervals.push(StepInterval {
                start_utc_ms: t - 3_600_000,
                end_utc_ms: t - 1_000,
                count: (seed % 500) as f64,
                record_id: None,
                source_id: None,
            });
        }
        if seed.is_multiple_of(13) {
            request.heart_rate_samples.reverse();
            request.step_intervals.reverse();
        }
        let _ = assess(request);
    }
}

#[test]
fn equal_watermark_is_complete_and_earlier_sample_is_allowed() {
    let payload: serde_json::Value = read_json("boundary.json");
    let mut request = request_from_value(payload["hour_aligned"]["request"].clone());
    request.data_watermark_utc_ms = Some(request.evaluation_time_utc_ms);
    let result = assess(request.clone()).expect("equal watermark");
    assert!(
        !result
            .missing_reasons
            .iter()
            .any(|item| item == "watermark_incomplete"),
        "watermark == evaluation must not be incomplete, got {:?}",
        result.missing_reasons
    );

    let mut incomplete = request.clone();
    incomplete.data_watermark_utc_ms = Some(incomplete.evaluation_time_utc_ms - 1);
    let result = assess(incomplete).expect("watermark behind evaluation");
    assert!(result
        .missing_reasons
        .iter()
        .any(|item| item == "watermark_incomplete"));

    let latest = request
        .heart_rate_samples
        .iter()
        .map(|sample| sample.timestamp_utc_ms)
        .max()
        .expect("hr");
    assert!(
        latest < request.evaluation_time_utc_ms,
        "fixture latest sample should be before T so freshness is independent of completeness"
    );
}
