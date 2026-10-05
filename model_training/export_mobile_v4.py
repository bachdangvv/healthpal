"""Export the locked V4 fatigue model to a mobile-friendly ONNX graph.

The training artifact uses `ai.onnx.ml` Imputer/Scaler/LinearClassifier operators.
Android ONNX Runtime handles those poorly, so this script rewrites scaler + logistic
regression with standard tensor ops only. Missing features are never imputed: the
mobile graph has no Imputer, and the app must return `insufficient_data` instead.

Calibration slope/intercept and the decision threshold stay in
`healthpal_fatigue_v4_config.json`. They are not baked into the ONNX graph.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import joblib
import numpy as np
import onnx
import onnxruntime as ort
import pandas as pd
from onnx import TensorProto, helper, numpy_helper
from scipy.special import expit, logit
from sklearn.pipeline import Pipeline

import train_healthpal_stress as v1
import train_healthpal_stress_v2 as v2

ROOT = Path(__file__).resolve().parent
SOURCE_DIR = ROOT / "artifacts" / "healthpal_fatigue_v4"
FLUTTER_ASSETS = (
    ROOT.parent / "healthpal-flutter" / "rust" / "assets" / "healthpal_fatigue_v4"
)
RUST_TESTDATA = ROOT.parent / "healthpal-flutter" / "rust" / "testdata"

LOCKED_FEATURE_ORDER = (
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
)
WINDOW_HOURS = 6
LOW_ACTIVITY_THRESHOLD = 250
MIN_COVERAGE = int(math.ceil(WINDOW_HOURS / 2))
PARITY_TOLERANCE = 1e-6
COPIED_ARTIFACTS = (
    "healthpal_fatigue_v4.onnx",
    "healthpal_fatigue_v4_config.json",
    "artifact_checksums.sha256.json",
)
MOBILE_ONNX_NAME = "healthpal_fatigue_v4_mobile.onnx"
MOBILE_CHECKSUMS_NAME = "mobile_artifact_checksums.sha256.json"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def load_config(path: Path) -> dict:
    config = json.loads(path.read_text(encoding="utf-8"))
    if tuple(config["feature_order"]) != LOCKED_FEATURE_ORDER:
        raise ValueError(f"Unexpected feature order: {config['feature_order']}")
    if int(config["primary_window_hours"]) != WINDOW_HOURS:
        raise ValueError("Locked V4 window is 6 hours.")
    if int(config["low_activity_steps_per_hour_threshold"]) != LOW_ACTIVITY_THRESHOLD:
        raise ValueError("Locked V4 low-activity threshold is 250 steps/hour.")
    if config["calibration"]["method"] != "sigmoid_on_logit_probability":
        raise ValueError("Locked V4 calibration method mismatch.")
    return config


def verify_source_checksums(source_dir: Path) -> dict:
    manifest_path = source_dir / "artifact_checksums.sha256.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for name in ("healthpal_fatigue_v4.onnx", "healthpal_fatigue_v4_config.json"):
        actual = sha256_file(source_dir / name)
        expected = manifest[name]
        if actual != expected:
            raise ValueError(f"SHA-256 mismatch for {name}: {actual} != {expected}")
    return manifest


def extract_scaler_classifier(estimator: Pipeline):
    if list(estimator.named_steps) != ["impute", "scale", "classifier"]:
        raise ValueError(f"Unexpected pipeline steps: {list(estimator.named_steps)}")
    return estimator.named_steps["scale"], estimator.named_steps["classifier"]


def build_mobile_onnx(estimator: Pipeline) -> onnx.ModelProto:
    scaler, classifier = extract_scaler_classifier(estimator)
    mean = scaler.mean_.astype(np.float32).reshape(1, -1)
    scale = scaler.scale_.astype(np.float32).reshape(1, -1)
    coef = classifier.coef_.astype(np.float32).T  # [n_features, 1]
    intercept = classifier.intercept_.astype(np.float32).reshape(1, 1)
    n_features = int(mean.shape[1])

    graph = helper.make_graph(
        nodes=[
            helper.make_node("Sub", ["float_input", "scaler_mean"], ["centered"]),
            helper.make_node("Div", ["centered", "scaler_scale"], ["scaled"]),
            helper.make_node("MatMul", ["scaled", "classifier_coef"], ["dot"]),
            helper.make_node("Add", ["dot", "classifier_intercept"], ["logit"]),
            helper.make_node("Sigmoid", ["logit"], ["positive_probability"]),
        ],
        name="healthpal_fatigue_v4_mobile",
        inputs=[
            helper.make_tensor_value_info(
                "float_input", TensorProto.FLOAT, ["batch", n_features]
            )
        ],
        outputs=[
            helper.make_tensor_value_info(
                "positive_probability", TensorProto.FLOAT, ["batch", 1]
            )
        ],
        initializer=[
            numpy_helper.from_array(mean, name="scaler_mean"),
            numpy_helper.from_array(scale, name="scaler_scale"),
            numpy_helper.from_array(coef, name="classifier_coef"),
            numpy_helper.from_array(intercept, name="classifier_intercept"),
        ],
    )
    model = helper.make_model(
        graph,
        opset_imports=[helper.make_opsetid("", 17)],
        producer_name="healthpal_export_mobile_v4",
        ir_version=8,
    )
    model.doc_string = (
        "StandardScaler + LogisticRegression positive-class probability. "
        "No imputer. Calibration and threshold remain in config JSON."
    )
    onnx.checker.check_model(model)
    domains = {opset.domain for opset in model.opset_import}
    if any(domain == "ai.onnx.ml" for domain in domains):
        raise ValueError("Mobile graph must not use ai.onnx.ml operators.")
    for node in model.graph.node:
        if node.domain and node.domain != "":
            raise ValueError(f"Non-standard operator domain: {node.domain} {node.op_type}")
    return model


def onnx_positive_probability(path: Path, features: np.ndarray) -> np.ndarray:
    session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    outputs = session.run(
        None, {session.get_inputs()[0].name: features.astype(np.float32, copy=False)}
    )
    tensor = outputs[-1]
    if tensor.ndim == 2 and tensor.shape[1] == 2:
        return tensor[:, 1].astype(np.float64, copy=False)
    return np.asarray(tensor, dtype=np.float64).reshape(-1)


def sklearn_positive_probability(estimator: Pipeline, features: np.ndarray) -> np.ndarray:
    return estimator.predict_proba(features)[:, 1].astype(np.float64, copy=False)


def numpy_scaler_logistic_probability(estimator: Pipeline, features: np.ndarray) -> np.ndarray:
    scaler, classifier = extract_scaler_classifier(estimator)
    scaled = (features - scaler.mean_) / scaler.scale_
    logits = scaled @ classifier.coef_.T + classifier.intercept_
    return expit(np.asarray(logits, dtype=np.float64).reshape(-1))


def calibrate(probabilities: np.ndarray, config: dict) -> np.ndarray:
    calibration = config["calibration"]
    clipped = np.clip(probabilities, 1e-6, 1.0 - 1e-6)
    return expit(calibration["slope"] * logit(clipped) + calibration["intercept"])


def max_abs_diff(*arrays: np.ndarray) -> float:
    reference = arrays[0]
    return float(max(np.max(np.abs(reference - other)) for other in arrays[1:]))


def finite_feature_matrix(frame: pd.DataFrame) -> np.ndarray:
    matrix = frame.loc[:, list(LOCKED_FEATURE_ORDER)].to_numpy(dtype=np.float64)
    return matrix[np.isfinite(matrix).all(axis=1)]


def random_valid_vectors(frame: pd.DataFrame, count: int, seed: int) -> np.ndarray:
    finite = finite_feature_matrix(frame)
    lower = finite.min(axis=0)
    upper = finite.max(axis=0)
    span = np.maximum(upper - lower, 1e-6)
    rng = np.random.default_rng(seed)
    return lower + rng.random((count, finite.shape[1])) * span


def assert_probability_parity(
    estimator: Pipeline,
    existing_onnx: Path,
    mobile_onnx: Path,
    features: np.ndarray,
    label: str,
) -> float:
    sklearn_p = sklearn_positive_probability(estimator, features)
    numpy_p = numpy_scaler_logistic_probability(estimator, features)
    existing_p = onnx_positive_probability(existing_onnx, features)
    mobile_p = onnx_positive_probability(mobile_onnx, features)
    error = max_abs_diff(sklearn_p, numpy_p, existing_p, mobile_p)
    if error >= PARITY_TOLERANCE:
        raise AssertionError(
            f"{label} max abs probability diff {error} exceeds {PARITY_TOLERANCE}"
        )
    return error


def copy_frozen_artifacts(source_dir: Path, dest_dir: Path) -> None:
    dest_dir.mkdir(parents=True, exist_ok=True)
    for name in COPIED_ARTIFACTS:
        target = dest_dir / name
        target.write_bytes((source_dir / name).read_bytes())


def verify_copied_artifacts(dest_dir: Path, source_manifest: dict) -> None:
    for name in ("healthpal_fatigue_v4.onnx", "healthpal_fatigue_v4_config.json"):
        actual = sha256_file(dest_dir / name)
        expected = source_manifest[name]
        if actual != expected:
            raise ValueError(f"Copied artifact SHA-256 mismatch for {name}")
    copied_manifest = json.loads(
        (dest_dir / "artifact_checksums.sha256.json").read_text(encoding="utf-8")
    )
    if copied_manifest != source_manifest:
        raise ValueError("Copied checksum manifest does not match the source manifest.")


def timestamp_to_utc_ms(value) -> int:
    stamp = pd.Timestamp(value)
    if stamp.tzinfo is None:
        stamp = stamp.tz_localize("UTC")
    else:
        stamp = stamp.tz_convert("UTC")
    return int(stamp.timestamp() * 1000)


def window_rows(stream: pd.DataFrame, event_time, window_hours: int = WINDOW_HOURS) -> pd.DataFrame:
    event_ns = np.datetime64(pd.Timestamp(event_time), "ns")
    start_ns = event_ns - np.timedelta64(window_hours, "h")
    times = stream["timestamp"].to_numpy(dtype="datetime64[ns]")
    left = int(np.searchsorted(times, start_ns, side="left"))
    right = int(np.searchsorted(times, event_ns, side="left"))
    selected = stream.iloc[left:right].copy()
    window_times = selected["timestamp"].to_numpy(dtype="datetime64[ns]")
    if len(window_times) and not np.all((window_times >= start_ns) & (window_times < event_ns)):
        raise AssertionError("Leakage invariant failed while exporting fixtures.")
    return selected


def features_from_window(
    window: pd.DataFrame, resting_hr: float, sleep_minutes: float
) -> dict[str, float]:
    bpm = pd.to_numeric(window["bpm"], errors="coerce").to_numpy(float)
    steps = pd.to_numeric(window["steps"], errors="coerce").to_numpy(float)
    valid_bpm = v2._finite(bpm)
    valid_steps = v2._finite(steps)
    eligible = len(valid_bpm) >= MIN_COVERAGE and len(valid_steps) >= MIN_COVERAGE
    if not eligible:
        raise ValueError("Window does not meet V4 coverage.")
    summary = v2._summary(valid_bpm)
    low_mask = np.isfinite(bpm) & np.isfinite(steps) & (steps <= LOW_ACTIVITY_THRESHOLD)
    low_summary = v2._summary(bpm[low_mask])
    return {
        "h6_hr_mean": summary["mean"],
        "h6_hr_std": summary["std"],
        "h6_hr_median": summary["median"],
        "h6_hr_p25": summary["p25"],
        "h6_hr_p75": summary["p75"],
        "h6_low250_hr_mean": low_summary["mean"],
        "h6_low250_hr_std": low_summary["std"],
        "h6_low250_hours": float(int(low_mask.sum())),
        "h6_hr_mean_minus_rhr": summary["mean"] - resting_hr,
        "resting_hr": float(resting_hr),
        "sleep_minutes": float(sleep_minutes),
        "h6_steps_sum": float(np.sum(valid_steps)),
    }


def request_from_window(
    window: pd.DataFrame,
    event_time,
    resting_hr: float,
    sleep_minutes: float,
) -> dict:
    event_ms = timestamp_to_utc_ms(event_time)
    previous_day = (pd.Timestamp(event_time).normalize() - pd.Timedelta(days=1)).strftime(
        "%Y-%m-%d"
    )
    heart_rate_samples = []
    step_intervals = []
    for row in window.itertuples(index=False):
        ts_ms = timestamp_to_utc_ms(row.timestamp)
        bpm = float(row.bpm) if pd.notna(row.bpm) else None
        steps = float(row.steps) if pd.notna(row.steps) else None
        if bpm is not None and np.isfinite(bpm):
            heart_rate_samples.append({"timestamp_utc_ms": ts_ms, "bpm": bpm})
        if steps is not None and np.isfinite(steps):
            step_intervals.append(
                {
                    "start_utc_ms": ts_ms,
                    "end_utc_ms": ts_ms + 3_600_000,
                    "count": steps,
                }
            )
    sleep_start = timestamp_to_utc_ms(pd.Timestamp(event_time).normalize() - pd.Timedelta(hours=8))
    sleep_end = sleep_start + int(sleep_minutes * 60_000)
    return {
        "evaluation_time_utc_ms": event_ms,
        "timezone_offset_minutes": 0,
        "heart_rate_samples": heart_rate_samples,
        "step_intervals": step_intervals,
        "resting_hr_records": [
            {
                "recorded_at_utc_ms": timestamp_to_utc_ms(
                    pd.Timestamp(event_time).normalize() - pd.Timedelta(hours=12)
                ),
                "bpm": float(resting_hr),
                "local_date": previous_day,
                "record_id": "rhr-d1",
                "source_id": "fitbit",
            }
        ],
        "sleep_sessions": [
            {
                "record_id": "sleep-d1",
                "start_utc_ms": sleep_start,
                "end_utc_ms": sleep_end,
                "health_day": previous_day,
                "stages": [],
                "asleep_minutes_aggregate": float(sleep_minutes),
                "source_id": "fitbit",
                "modified_at_utc_ms": sleep_end,
            }
        ],
        "exercise_sessions": [],
        "data_watermark_utc_ms": event_ms,
        "heart_rate_permission": True,
        "steps_permission": True,
        "sleep_permission": True,
        "resting_hr_permission": True,
        "preferred_source_id": "fitbit",
    }


def write_feature_parity_fixtures(
    hourly: pd.DataFrame,
    daily: pd.DataFrame,
    training: pd.DataFrame,
    dest: Path,
    count: int = 100,
) -> None:
    daily_lookup = daily.set_index(["id", "date"])[["resting_hr", "minutesAsleep"]]
    fixtures = []
    for row in training.head(count).itertuples(index=False):
        stream = hourly.loc[hourly["id"].eq(row.id)].sort_values("timestamp")
        window = window_rows(stream, row.event_time)
        previous_day = pd.Timestamp(row.event_time).normalize() - pd.Timedelta(days=1)
        day = daily_lookup.loc[(row.id, previous_day)]
        if isinstance(day, pd.DataFrame):
            day = day.iloc[0]
        reconstructed = features_from_window(
            window, float(day["resting_hr"]), float(day["minutesAsleep"])
        )
        expected = {name: float(getattr(row, name)) for name in LOCKED_FEATURE_ORDER}
        for name, value in reconstructed.items():
            if np.isnan(value) and np.isnan(expected[name]):
                continue
            if abs(value - expected[name]) >= 1e-5:
                raise AssertionError(
                    f"Python reconstruction drifted for {row.id} {row.event_time} {name}: "
                    f"{value} vs {expected[name]}"
                )
        fixtures.append(
            {
                "id": row.id,
                "event_time": pd.Timestamp(row.event_time).strftime("%Y-%m-%dT%H:%M:%S"),
                "request": request_from_window(
                    window, row.event_time, float(day["resting_hr"]), float(day["minutesAsleep"])
                ),
                "expected_features": {name: json_number(value) for name, value in expected.items()},
            }
        )
    dest.write_text(json.dumps(fixtures, indent=2), encoding="utf-8")


def json_number(value: float) -> float | None:
    number = float(value)
    if not np.isfinite(number):
        return None
    return number


def write_inference_parity_fixtures(
    estimator: Pipeline,
    existing_onnx: Path,
    mobile_onnx: Path,
    training: pd.DataFrame,
    config: dict,
    dest: Path,
    count: int = 128,
) -> None:
    finite = training.loc[
        np.isfinite(training.loc[:, list(LOCKED_FEATURE_ORDER)].to_numpy(float)).all(axis=1)
    ].head(count)
    features = finite.loc[:, list(LOCKED_FEATURE_ORDER)].to_numpy(dtype=np.float64)
    sklearn_p = sklearn_positive_probability(estimator, features)
    existing_p = onnx_positive_probability(existing_onnx, features)
    mobile_p = onnx_positive_probability(mobile_onnx, features)
    calibrated = calibrate(sklearn_p, config)
    threshold = float(config["decision_threshold"]["threshold"])
    rows = []
    for index, (_, row) in enumerate(finite.iterrows()):
        vector = [float(row[name]) for name in LOCKED_FEATURE_ORDER]
        rows.append(
            {
                "features": vector,
                "sklearn_base_probability": float(sklearn_p[index]),
                "existing_onnx_base_probability": float(existing_p[index]),
                "mobile_onnx_base_probability": float(mobile_p[index]),
                "calibrated_probability": float(calibrated[index]),
                "threshold": threshold,
                "decision": bool(calibrated[index] >= threshold),
            }
        )
    dest.write_text(json.dumps(rows, indent=2), encoding="utf-8")


def write_boundary_fixtures(dest: Path) -> None:
    # T = 2021-05-25 10:00 UTC. Window [04:00, 10:00). Hour 04 included, 10 excluded.
    t = timestamp_to_utc_ms("2021-05-25T10:00:00Z")
    hour = 3_600_000
    bpm = [70.0, 72.0, 74.0, 76.0, 78.0, 80.0]
    steps = [100.0, 200.0, 250.0, 251.0, 0.0, 400.0]
    samples = []
    intervals = []
    for index in range(6):
        start = t - (6 - index) * hour
        samples.append({"timestamp_utc_ms": start, "bpm": bpm[index]})
        intervals.append(
            {"start_utc_ms": start, "end_utc_ms": start + hour, "count": steps[index]}
        )
    hr_mean = float(np.mean(bpm))
    hr_std = float(np.std(bpm, ddof=0))
    hr_median = float(np.median(bpm))
    hr_p25 = float(np.quantile(bpm, 0.25))
    hr_p75 = float(np.quantile(bpm, 0.75))
    low_bpm = np.array(bpm)[np.array(steps) <= 250]
    resting_hr = 60.0
    sleep_minutes = 420.0
    expected = {
        "h6_hr_mean": hr_mean,
        "h6_hr_std": hr_std,
        "h6_hr_median": hr_median,
        "h6_hr_p25": hr_p25,
        "h6_hr_p75": hr_p75,
        "h6_low250_hr_mean": float(np.mean(low_bpm)),
        "h6_low250_hr_std": float(np.std(low_bpm, ddof=0)),
        "h6_low250_hours": 4.0,
        "h6_hr_mean_minus_rhr": hr_mean - resting_hr,
        "resting_hr": resting_hr,
        "sleep_minutes": sleep_minutes,
        "h6_steps_sum": float(np.sum(steps)),
    }
    midnight_t = timestamp_to_utc_ms("2021-05-26T00:00:00Z")
    dest.write_text(
        json.dumps(
            {
                "hour_aligned": {
                    "request": {
                        "evaluation_time_utc_ms": t,
                        "timezone_offset_minutes": 0,
                        "heart_rate_samples": samples,
                        "step_intervals": intervals,
                        "resting_hr_records": [
                            {
                                "recorded_at_utc_ms": t - 12 * hour,
                                "bpm": resting_hr,
                                "local_date": "2021-05-24",
                                "record_id": "rhr-d1",
                                "source_id": "fitbit",
                            }
                        ],
                        "sleep_sessions": [
                            {
                                "record_id": "sleep-d1",
                                "start_utc_ms": t - 12 * hour,
                                "end_utc_ms": t - 12 * hour + int(sleep_minutes * 60_000),
                                "health_day": "2021-05-24",
                                "stages": [],
                                "asleep_minutes_aggregate": sleep_minutes,
                                "source_id": "fitbit",
                                "modified_at_utc_ms": t - 8 * hour,
                            }
                        ],
                        "exercise_sessions": [],
                        "data_watermark_utc_ms": t,
                        "heart_rate_permission": True,
                        "steps_permission": True,
                        "sleep_permission": True,
                        "resting_hr_permission": True,
                    },
                    "expected_features": expected,
                    "notes": "T-6h included, T excluded, low-activity includes steps==250",
                },
                "sample_at_t_excluded": {
                    "evaluation_time_utc_ms": t,
                    "extra_hr_at_t_bpm": 180.0,
                },
                "midnight": {
                    "evaluation_time_utc_ms": midnight_t,
                    "timezone_offset_minutes": 0,
                    "d_minus_1": "2021-05-25",
                },
            },
            indent=2,
        ),
        encoding="utf-8",
    )


def export(check_only: bool = False) -> dict:
    source_manifest = verify_source_checksums(SOURCE_DIR)
    config = load_config(SOURCE_DIR / "healthpal_fatigue_v4_config.json")
    estimator = joblib.load(SOURCE_DIR / "healthpal_fatigue_v4.joblib")
    training = pd.read_csv(SOURCE_DIR / "training_dataset.csv")
    existing_onnx = SOURCE_DIR / "healthpal_fatigue_v4.onnx"
    mobile_model = build_mobile_onnx(estimator)
    mobile_bytes = mobile_model.SerializeToString()

    fixture_features = finite_feature_matrix(training)
    random_features = random_valid_vectors(training, 1000, seed=20260930)
    FLUTTER_ASSETS.mkdir(parents=True, exist_ok=True)
    RUST_TESTDATA.mkdir(parents=True, exist_ok=True)
    mobile_path = FLUTTER_ASSETS / MOBILE_ONNX_NAME
    if check_only:
        if not mobile_path.exists():
            raise FileNotFoundError(mobile_path)
    else:
        copy_frozen_artifacts(SOURCE_DIR, FLUTTER_ASSETS)
        mobile_path.write_bytes(mobile_bytes)
        scaler, classifier = extract_scaler_classifier(estimator)
        weights = {
            "scaler_mean": scaler.mean_.astype(np.float32).tolist(),
            "scaler_scale": scaler.scale_.astype(np.float32).tolist(),
            "classifier_coef": classifier.coef_.astype(np.float32).reshape(-1).tolist(),
            "classifier_intercept": float(np.float32(classifier.intercept_[0])),
        }
        weights_path = FLUTTER_ASSETS / "healthpal_fatigue_v4_mobile_weights.json"
        weights_bytes = (json.dumps(weights, indent=2) + "\n").encode("utf-8")
        weights_path.write_bytes(weights_bytes)
        (FLUTTER_ASSETS / MOBILE_CHECKSUMS_NAME).write_text(
            json.dumps(
                {
                    MOBILE_ONNX_NAME: sha256_bytes(mobile_bytes),
                    "healthpal_fatigue_v4_mobile_weights.json": sha256_bytes(weights_bytes),
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    verify_copied_artifacts(FLUTTER_ASSETS, source_manifest)
    stored_mobile = sha256_file(mobile_path)
    expected_mobile = json.loads(
        (FLUTTER_ASSETS / MOBILE_CHECKSUMS_NAME).read_text(encoding="utf-8")
    )[MOBILE_ONNX_NAME]
    if stored_mobile != expected_mobile:
        raise ValueError("Mobile ONNX SHA-256 does not match its checksum manifest.")
    if stored_mobile != sha256_bytes(mobile_bytes):
        raise ValueError("Stored mobile ONNX does not match a freshly exported graph.")

    training_error = assert_probability_parity(
        estimator, existing_onnx, mobile_path, fixture_features, "training fixtures"
    )
    random_error = assert_probability_parity(
        estimator, existing_onnx, mobile_path, random_features, "1000 random valid vectors"
    )

    if not check_only:
        hourly, daily, _ = v1.read_sources(ROOT)
        write_feature_parity_fixtures(hourly, daily, training, RUST_TESTDATA / "feature_parity.json")
        write_inference_parity_fixtures(
            estimator,
            existing_onnx,
            mobile_path,
            training,
            config,
            RUST_TESTDATA / "inference_parity.json",
        )
        write_boundary_fixtures(RUST_TESTDATA / "boundary.json")

    report = {
        "copied_artifacts": list(COPIED_ARTIFACTS),
        "mobile_onnx": str(mobile_path),
        "training_fixture_count": int(len(fixture_features)),
        "training_max_abs_probability_diff": training_error,
        "random_vector_count": 1000,
        "random_max_abs_probability_diff": random_error,
        "mobile_sha256": stored_mobile,
        "calibration_source": "healthpal_fatigue_v4_config.json",
        "imputer_in_mobile_graph": False,
    }
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify copied artifacts, checksums, and probability parity without rewriting files.",
    )
    args = parser.parse_args(argv)
    report = export(check_only=args.check)
    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
