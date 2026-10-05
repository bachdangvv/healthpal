"""Train and export HealthPal's on-device stress-risk model.

The target is a binary SEMA response: TENSE/ANXIOUS. Every rolling feature is
computed on [T-window, T), and daily sleep/resting-HR comes from D-1. Splits are
grouped by participant so the same person never appears in train and validation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import onnx
import onnxruntime as ort
import pandas as pd
import sklearn
from scipy.special import expit, logit
from sklearn.base import clone
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score,
    brier_score_loss,
    confusion_matrix,
    f1_score,
    precision_recall_curve,
    precision_score,
    recall_score,
    roc_auc_score,
    roc_curve,
)
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.utils.class_weight import compute_sample_weight
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

SEED = 20260927
TARGET = "TENSE/ANXIOUS"
MIN_RECALL = 0.70
WINDOWS = (6, 12, 24)
FEATURE_SETS = {
    "compact5": ["hr_mean", "hr_std", "resting_hr", "sleep_minutes", "steps_sum"],
    "core7": [
        "hr_mean",
        "hr_std",
        "hr_min",
        "hr_max",
        "resting_hr",
        "sleep_minutes",
        "steps_sum",
    ],
    "core8_delta": [
        "hr_mean",
        "hr_std",
        "hr_min",
        "hr_max",
        "resting_hr",
        "sleep_minutes",
        "steps_sum",
        "hr_delta_rhr",
    ],
}


@dataclass(frozen=True)
class Calibration:
    slope: float
    intercept: float

    def apply(self, probabilities: np.ndarray) -> np.ndarray:
        clipped = np.clip(probabilities, 1e-6, 1 - 1e-6)
        return expit(self.slope * logit(clipped) + self.intercept)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_sources(data_dir: Path) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    hourly_path = data_dir / "hourly_fitbit_sema_df_unprocessed.csv"
    daily_path = data_dir / "daily_fitbit_sema_df_unprocessed.csv"
    hourly = pd.read_csv(hourly_path, low_memory=False)
    daily = pd.read_csv(daily_path, low_memory=False)
    raw_hourly_rows = int(len(hourly))
    raw_daily_rows = int(len(daily))

    required_hourly = {"id", "date", "hour", "bpm", "steps", "distance", TARGET}
    required_daily = {"id", "date", "resting_hr", "minutesAsleep"}
    if missing := required_hourly.difference(hourly.columns):
        raise ValueError(f"Hourly CSV is missing columns: {sorted(missing)}")
    if missing := required_daily.difference(daily.columns):
        raise ValueError(f"Daily CSV is missing columns: {sorted(missing)}")

    raw_event_count = int(hourly[TARGET].notna().sum())
    raw_positive_count = int(hourly[TARGET].fillna(0).eq(1).sum())
    if raw_event_count != 5029 or raw_positive_count != 620:
        raise ValueError(
            "Unexpected source snapshot: expected 5,029 labelled events / 620 positives, "
            f"found {raw_event_count:,} / {raw_positive_count:,}."
        )

    hourly = hourly.drop(columns=["Unnamed: 0"], errors="ignore").copy()
    daily = daily.drop(columns=["Unnamed: 0"], errors="ignore").copy()
    hourly["date"] = pd.to_datetime(hourly["date"], errors="raise")
    daily["date"] = pd.to_datetime(daily["date"], errors="raise")
    hourly["hour"] = pd.to_numeric(hourly["hour"], errors="raise").astype(int)
    hourly["timestamp"] = hourly["date"] + pd.to_timedelta(hourly["hour"], unit="h")

    key = ["id", "date", "hour"]
    duplicate_rows = int(hourly.duplicated(key, keep=False).sum())
    duplicate_groups = int(hourly.loc[hourly.duplicated(key, keep=False), key].drop_duplicates().shape[0])
    labelled_duplicates = int(hourly.loc[hourly[TARGET].notna()].duplicated(key, keep=False).sum())
    if labelled_duplicates:
        raise ValueError("Labelled hourly keys are duplicated; refusing ambiguous target aggregation.")
    hourly = hourly.sort_values(["id", "timestamp"], kind="stable").drop_duplicates(key, keep="first")
    daily = daily.sort_values(["id", "date"], kind="stable").drop_duplicates(["id", "date"], keep="first")

    manifest = {
        "hourly": {
            "path": str(hourly_path.resolve()),
            "sha256": sha256(hourly_path),
            "raw_rows": raw_hourly_rows,
            "deduplicated_rows": int(len(hourly)),
            "duplicate_groups": duplicate_groups,
            "duplicate_rows": duplicate_rows,
        },
        "daily": {
            "path": str(daily_path.resolve()),
            "sha256": sha256(daily_path),
            "raw_rows": raw_daily_rows,
            "deduplicated_rows": int(len(daily)),
        },
        "labelled_events_raw": raw_event_count,
        "positives_raw": raw_positive_count,
    }
    return hourly, daily, manifest


def build_event_dataset(hourly: pd.DataFrame, daily: pd.DataFrame, window_hours: int) -> pd.DataFrame:
    """Create event-level features using only records strictly before event time."""
    min_coverage = math.ceil(window_hours / 2)
    daily_lookup = daily.set_index(["id", "date"])[["resting_hr", "minutesAsleep"]]
    events = hourly.loc[hourly[TARGET].notna(), ["id", "timestamp", TARGET]].copy()
    events = events.rename(columns={TARGET: "target"})
    events["target"] = events["target"].astype(int)

    rows: list[dict] = []
    for participant, participant_events in events.groupby("id", sort=False):
        stream = hourly.loc[hourly["id"].eq(participant)].sort_values("timestamp")
        times = stream["timestamp"].to_numpy(dtype="datetime64[ns]")
        bpm = pd.to_numeric(stream["bpm"], errors="coerce").to_numpy(float)
        steps = pd.to_numeric(stream["steps"], errors="coerce").to_numpy(float)
        distance = pd.to_numeric(stream["distance"], errors="coerce").to_numpy(float)

        for event in participant_events.itertuples(index=False):
            event_time = np.datetime64(event.timestamp, "ns")
            start_time = event_time - np.timedelta64(window_hours, "h")
            left = int(np.searchsorted(times, start_time, side="left"))
            right = int(np.searchsorted(times, event_time, side="left"))
            window_times = times[left:right]
            if len(window_times) and not np.all((window_times >= start_time) & (window_times < event_time)):
                raise AssertionError("Leakage invariant failed: feature window is not [T-window, T).")
            window_bpm = bpm[left:right]
            window_steps = steps[left:right]
            window_distance = distance[left:right]
            bpm_valid = window_bpm[np.isfinite(window_bpm)]
            steps_valid = window_steps[np.isfinite(window_steps)]
            distance_valid = window_distance[np.isfinite(window_distance)]
            if len(bpm_valid) < min_coverage or len(steps_valid) < min_coverage:
                continue

            previous_day = pd.Timestamp(event.timestamp).normalize() - pd.Timedelta(days=1)
            try:
                day = daily_lookup.loc[(participant, previous_day)]
            except KeyError:
                continue
            if isinstance(day, pd.DataFrame):
                day = day.iloc[0]
            resting_hr = float(day["resting_hr"])
            sleep_minutes = float(day["minutesAsleep"])
            if not np.isfinite(resting_hr) or not np.isfinite(sleep_minutes) or sleep_minutes <= 0:
                continue

            rows.append(
                {
                    "id": participant,
                    "event_time": pd.Timestamp(event.timestamp),
                    "target": int(event.target),
                    "window_hours": window_hours,
                    "hr_hours_observed": len(bpm_valid),
                    "activity_hours_observed": len(steps_valid),
                    "hr_mean": float(np.mean(bpm_valid)),
                    "hr_std": float(np.std(bpm_valid, ddof=0)),
                    "hr_min": float(np.min(bpm_valid)),
                    "hr_max": float(np.max(bpm_valid)),
                    "resting_hr": resting_hr,
                    "sleep_minutes": sleep_minutes,
                    "steps_sum": float(np.sum(steps_valid)),
                    "distance_sum": float(np.sum(distance_valid)) if len(distance_valid) else np.nan,
                    "hr_delta_rhr": float(np.mean(bpm_valid) - resting_hr),
                }
            )
    result = pd.DataFrame(rows)
    if result.empty:
        raise ValueError(f"No eligible events for {window_hours}h window.")
    return result.sort_values(["id", "event_time"]).reset_index(drop=True)


def build_estimator(kind: str, parameter: float | int):
    if kind == "logistic":
        return Pipeline(
            [
                ("scale", StandardScaler()),
                (
                    "classifier",
                    LogisticRegression(
                        C=float(parameter),
                        class_weight="balanced",
                        max_iter=3000,
                        random_state=SEED,
                    ),
                ),
            ]
        )
    if kind == "histgb":
        return HistGradientBoostingClassifier(
            learning_rate=0.05,
            max_iter=250,
            max_leaf_nodes=int(parameter),
            l2_regularization=1.0,
            random_state=SEED,
        )
    raise ValueError(f"Unknown model kind: {kind}")


def fit_estimator(estimator, kind: str, x: np.ndarray, y: np.ndarray):
    if kind == "histgb":
        estimator.fit(x, y, sample_weight=compute_sample_weight("balanced", y))
    else:
        estimator.fit(x, y)
    return estimator


def safe_auroc(y: np.ndarray, p: np.ndarray) -> float:
    return float(roc_auc_score(y, p)) if np.unique(y).size == 2 else float("nan")


def score_probabilities(y: np.ndarray, p: np.ndarray) -> dict:
    return {
        "auprc": float(average_precision_score(y, p)),
        "auroc": safe_auroc(y, p),
        "brier": float(brier_score_loss(y, p)),
    }


def grouped_splits(y: np.ndarray, groups: np.ndarray, folds: int, seed: int):
    splitter = StratifiedGroupKFold(n_splits=folds, shuffle=True, random_state=seed)
    return list(splitter.split(np.zeros(len(y)), y, groups))


def benchmark(datasets: dict[int, pd.DataFrame]) -> pd.DataFrame:
    records: list[dict] = []
    fixed_parameters = {"logistic": 1.0, "histgb": 15}
    for window, frame in datasets.items():
        y = frame["target"].to_numpy(int)
        groups = frame["id"].to_numpy()
        for feature_set, features in FEATURE_SETS.items():
            x = frame[features].to_numpy(float)
            for kind, parameter in fixed_parameters.items():
                fold_scores = []
                oof = np.full(len(frame), np.nan)
                for fold, (train, test) in enumerate(grouped_splits(y, groups, 5, SEED), start=1):
                    estimator = fit_estimator(build_estimator(kind, parameter), kind, x[train], y[train])
                    p = estimator.predict_proba(x[test])[:, 1]
                    oof[test] = p
                    fold_scores.append(average_precision_score(y[test], p))
                metrics = score_probabilities(y, oof)
                records.append(
                    {
                        "window_hours": window,
                        "feature_set": feature_set,
                        "model": kind,
                        "features": "|".join(features),
                        "feature_count": len(features),
                        "events": len(frame),
                        "participants": frame["id"].nunique(),
                        "positives": int(y.sum()),
                        "prevalence": float(y.mean()),
                        "mean_fold_auprc": float(np.mean(fold_scores)),
                        "se_fold_auprc": float(np.std(fold_scores, ddof=1) / np.sqrt(len(fold_scores))),
                        "oof_auprc": metrics["auprc"],
                        "oof_auroc": metrics["auroc"],
                        "oof_brier": metrics["brier"],
                    }
                )
    return pd.DataFrame(records).sort_values("mean_fold_auprc", ascending=False).reset_index(drop=True)


def select_one_se(benchmarks: pd.DataFrame) -> pd.Series:
    best = benchmarks.iloc[0]
    floor = float(best["mean_fold_auprc"] - best["se_fold_auprc"])
    eligible = benchmarks.loc[benchmarks["mean_fold_auprc"].ge(floor)].copy()
    eligible["model_rank"] = eligible["model"].map({"logistic": 0, "histgb": 1})
    eligible["window_rank"] = (eligible["window_hours"] - 12).abs()
    return eligible.sort_values(
        ["model_rank", "feature_count", "window_rank", "mean_fold_auprc"],
        ascending=[True, True, True, False],
    ).iloc[0]


def tune_parameter(x: np.ndarray, y: np.ndarray, groups: np.ndarray, kind: str, seed: int):
    grid = [0.03, 0.1, 0.3, 1.0, 3.0, 10.0] if kind == "logistic" else [7, 15, 31]
    splits = grouped_splits(y, groups, 4, seed)
    rows = []
    for parameter in grid:
        scores = []
        for train, test in splits:
            estimator = fit_estimator(build_estimator(kind, parameter), kind, x[train], y[train])
            scores.append(average_precision_score(y[test], estimator.predict_proba(x[test])[:, 1]))
        rows.append((parameter, float(np.mean(scores)), float(np.std(scores, ddof=1))))
    rows.sort(key=lambda item: (-item[1], float(item[0])))
    return rows[0][0], rows


def grouped_oof_base(
    x: np.ndarray,
    y: np.ndarray,
    groups: np.ndarray,
    kind: str,
    parameter: float | int,
    folds: int,
    seed: int,
) -> np.ndarray:
    oof = np.full(len(y), np.nan)
    for train, test in grouped_splits(y, groups, folds, seed):
        estimator = fit_estimator(build_estimator(kind, parameter), kind, x[train], y[train])
        oof[test] = estimator.predict_proba(x[test])[:, 1]
    if np.isnan(oof).any():
        raise AssertionError("OOF generation left unpredicted rows.")
    return oof


def fit_calibrator(y: np.ndarray, base_probabilities: np.ndarray) -> Calibration:
    z = logit(np.clip(base_probabilities, 1e-6, 1 - 1e-6)).reshape(-1, 1)
    calibrator = LogisticRegression(C=1e6, max_iter=2000, random_state=SEED).fit(z, y)
    return Calibration(float(calibrator.coef_[0, 0]), float(calibrator.intercept_[0]))


def choose_threshold(y: np.ndarray, probabilities: np.ndarray, min_recall: float = MIN_RECALL) -> dict:
    precision, recall, thresholds = precision_recall_curve(y, probabilities)
    candidates = []
    for p, r, threshold in zip(precision[:-1], recall[:-1], thresholds):
        if r >= min_recall:
            f1 = 2 * p * r / (p + r) if p + r else 0.0
            candidates.append((f1, p, r, threshold))
    if not candidates:
        index = int(np.argmax(2 * precision[:-1] * recall[:-1] / np.maximum(precision[:-1] + recall[:-1], 1e-12)))
        chosen = (
            float(2 * precision[index] * recall[index] / max(precision[index] + recall[index], 1e-12)),
            float(precision[index]),
            float(recall[index]),
            float(thresholds[index]),
        )
        constraint_met = False
    else:
        chosen = max(candidates, key=lambda item: (item[0], item[1], item[3]))
        constraint_met = True
    return {
        "threshold": float(chosen[3]),
        "training_f1": float(chosen[0]),
        "training_precision": float(chosen[1]),
        "training_recall": float(chosen[2]),
        "minimum_recall_constraint": min_recall,
        "constraint_met": constraint_met,
    }


def nested_evaluation(frame: pd.DataFrame, features: list[str], kind: str):
    x = frame[features].to_numpy(float)
    y = frame["target"].to_numpy(int)
    groups = frame["id"].to_numpy()
    oof = np.full(len(y), np.nan)
    predictions = np.full(len(y), -1, dtype=int)
    thresholds = np.full(len(y), np.nan)
    fold_ids = np.full(len(y), -1, dtype=int)
    fold_rows = []
    chosen_parameters = []

    for fold, (train, test) in enumerate(grouped_splits(y, groups, 5, SEED), start=1):
        parameter, tuning = tune_parameter(x[train], y[train], groups[train], kind, SEED + fold)
        chosen_parameters.append(parameter)
        inner_base = grouped_oof_base(
            x[train], y[train], groups[train], kind, parameter, 4, SEED + 100 + fold
        )
        calibration = fit_calibrator(y[train], inner_base)
        inner_calibrated = calibration.apply(inner_base)
        threshold_info = choose_threshold(y[train], inner_calibrated)

        estimator = fit_estimator(build_estimator(kind, parameter), kind, x[train], y[train])
        test_base = estimator.predict_proba(x[test])[:, 1]
        test_probability = calibration.apply(test_base)
        test_prediction = (test_probability >= threshold_info["threshold"]).astype(int)
        oof[test] = test_probability
        predictions[test] = test_prediction
        thresholds[test] = threshold_info["threshold"]
        fold_ids[test] = fold
        fold_metric = score_probabilities(y[test], test_probability)
        fold_rows.append(
            {
                "fold": fold,
                "train_participants": int(np.unique(groups[train]).size),
                "test_participants": int(np.unique(groups[test]).size),
                "train_events": int(len(train)),
                "test_events": int(len(test)),
                "test_positives": int(y[test].sum()),
                "parameter": float(parameter),
                "calibration_slope": calibration.slope,
                "calibration_intercept": calibration.intercept,
                "threshold": threshold_info["threshold"],
                "auprc": fold_metric["auprc"],
                "auroc": fold_metric["auroc"],
                "brier": fold_metric["brier"],
                "precision": float(precision_score(y[test], test_prediction, zero_division=0)),
                "recall": float(recall_score(y[test], test_prediction, zero_division=0)),
                "f1": float(f1_score(y[test], test_prediction, zero_division=0)),
                "inner_tuning": tuning,
            }
        )
    if np.isnan(oof).any() or (fold_ids < 0).any():
        raise AssertionError("Nested evaluation left unpredicted rows.")
    return oof, predictions, thresholds, fold_ids, pd.DataFrame(fold_rows), chosen_parameters


def classification_metrics(y: np.ndarray, p: np.ndarray, pred: np.ndarray) -> dict:
    tn, fp, fn, tp = confusion_matrix(y, pred, labels=[0, 1]).ravel()
    result = score_probabilities(y, p)
    result.update(
        {
            "precision": float(precision_score(y, pred, zero_division=0)),
            "recall": float(recall_score(y, pred, zero_division=0)),
            "f1": float(f1_score(y, pred, zero_division=0)),
            "specificity": float(tn / (tn + fp)) if tn + fp else float("nan"),
            "confusion_matrix": {"tn": int(tn), "fp": int(fp), "fn": int(fn), "tp": int(tp)},
        }
    )
    return result


def participant_macro_metrics(frame: pd.DataFrame, probabilities: np.ndarray) -> dict:
    rows = []
    for participant, index in frame.groupby("id").groups.items():
        indices = np.asarray(list(index), dtype=int)
        y = frame.loc[indices, "target"].to_numpy(int)
        if np.unique(y).size < 2:
            continue
        rows.append(
            {
                "id": participant,
                "auprc": average_precision_score(y, probabilities[indices]),
                "auroc": roc_auc_score(y, probabilities[indices]),
            }
        )
    metrics = pd.DataFrame(rows)
    return {
        "eligible_participants": int(len(metrics)),
        "mean_auprc": float(metrics["auprc"].mean()),
        "median_auprc": float(metrics["auprc"].median()),
        "mean_auroc": float(metrics["auroc"].mean()),
        "median_auroc": float(metrics["auroc"].median()),
    }


def participant_bootstrap(
    frame: pd.DataFrame, probabilities: np.ndarray, replicates: int = 1000
) -> dict:
    rng = np.random.default_rng(SEED)
    participant_indices = {
        participant: np.asarray(list(index), dtype=int)
        for participant, index in frame.groupby("id").groups.items()
    }
    participants = np.asarray(list(participant_indices))
    results = {"auprc": [], "auroc": [], "brier": []}
    for _ in range(replicates):
        sampled = rng.choice(participants, size=len(participants), replace=True)
        indices = np.concatenate([participant_indices[participant] for participant in sampled])
        y = frame.loc[indices, "target"].to_numpy(int)
        p = probabilities[indices]
        if np.unique(y).size < 2:
            continue
        results["auprc"].append(average_precision_score(y, p))
        results["auroc"].append(roc_auc_score(y, p))
        results["brier"].append(brier_score_loss(y, p))
    return {
        name: {
            "lower_95": float(np.quantile(values, 0.025)),
            "upper_95": float(np.quantile(values, 0.975)),
        }
        for name, values in results.items()
    }


def create_report_plot(
    frame: pd.DataFrame,
    probabilities: np.ndarray,
    predictions: np.ndarray,
    folds: pd.DataFrame,
    output_path: Path,
) -> None:
    y = frame["target"].to_numpy(int)
    fig, axes = plt.subplots(2, 2, figsize=(11, 8.5))
    precision, recall, _ = precision_recall_curve(y, probabilities)
    axes[0, 0].plot(recall, precision, color="#00695c", lw=2)
    axes[0, 0].axhline(y.mean(), color="#777", ls="--", label=f"Prevalence {y.mean():.3f}")
    axes[0, 0].set(title="Nested OOF precision-recall", xlabel="Recall", ylabel="Precision")
    axes[0, 0].legend()

    fpr, tpr, _ = roc_curve(y, probabilities)
    axes[0, 1].plot(fpr, tpr, color="#1565c0", lw=2)
    axes[0, 1].plot([0, 1], [0, 1], color="#777", ls="--")
    axes[0, 1].set(title="Nested OOF ROC", xlabel="False-positive rate", ylabel="True-positive rate")

    bins = pd.qcut(probabilities, q=8, duplicates="drop")
    calibration = pd.DataFrame({"p": probabilities, "y": y, "bin": bins}).groupby("bin", observed=True).agg(
        predicted=("p", "mean"), observed=("y", "mean"), count=("y", "size")
    )
    axes[1, 0].plot(calibration["predicted"], calibration["observed"], marker="o", color="#7b1fa2")
    axes[1, 0].plot([0, 1], [0, 1], color="#777", ls="--")
    axes[1, 0].set(title="Calibration by probability octile", xlabel="Mean predicted", ylabel="Observed rate")

    axes[1, 1].bar(folds["fold"].astype(str), folds["auprc"], color="#ef6c00")
    axes[1, 1].axhline(y.mean(), color="#777", ls="--")
    axes[1, 1].set(title="AUPRC by held-out participant fold", xlabel="Fold", ylabel="AUPRC")
    fig.suptitle("HealthPal stress-risk model validation", fontsize=15)
    fig.tight_layout()
    fig.savefig(output_path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def export_onnx(estimator, kind: str, feature_count: int, path: Path, sample: np.ndarray) -> float:
    if kind != "logistic":
        raise ValueError("This pipeline exports only the selected logistic model to ONNX.")
    classifier = estimator.named_steps["classifier"]
    model = convert_sklearn(
        estimator,
        initial_types=[("float_input", FloatTensorType([None, feature_count]))],
        options={id(classifier): {"zipmap": False}},
        target_opset=17,
    )
    path.write_bytes(model.SerializeToString())
    onnx.checker.check_model(onnx.load(path))
    session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    outputs = session.run(None, {session.get_inputs()[0].name: sample.astype(np.float32)})
    onnx_probabilities = next(output for output in outputs if isinstance(output, np.ndarray) and output.ndim == 2)[:, 1]
    sklearn_probabilities = estimator.predict_proba(sample)[:, 1]
    return float(np.max(np.abs(onnx_probabilities - sklearn_probabilities)))


def json_ready(value):
    if isinstance(value, dict):
        return {str(key): json_ready(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_ready(item) for item in value]
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
        return None
    return value


def write_model_card(path: Path, metrics: dict, config: dict) -> None:
    ci = metrics["cluster_bootstrap_95_ci"]
    pooled = metrics["nested_oof_pooled"]
    text = f"""# HealthPal stress-risk model v1

## Intended use

This model estimates the probability that a LifeSnaps SEMA event is labelled `TENSE/ANXIOUS`. It is a wellness signal for HealthPal's separate, conservative training-readiness rule engine. It is not a medical diagnosis, a clinical stress-severity scale, or a substitute for professional care.

## Training snapshot

- Eligible events: {metrics['dataset']['events']:,} ({metrics['dataset']['positives']:,} positive; prevalence {metrics['dataset']['prevalence']:.3f})
- Participants: {metrics['dataset']['participants']}
- Window: {config['window_hours']} hours, strictly `[T-{config['window_hours']}h, T)`
- Daily alignment: previous calendar day (`D-1`) for sleep and resting heart rate
- Features: {', '.join(config['features'])}
- Model: class-balanced logistic regression, sigmoid calibration outside ONNX

## Validation

Participant-grouped nested 5-fold cross-validation kept every participant entirely in one outer fold. Hyperparameters, calibration, and operating threshold were fitted without outer-fold labels.

- AUPRC: {pooled['auprc']:.3f} (participant-cluster bootstrap 95% CI {ci['auprc']['lower_95']:.3f}–{ci['auprc']['upper_95']:.3f}); random ranking baseline = {metrics['dataset']['prevalence']:.3f}
- AUROC: {pooled['auroc']:.3f} (95% CI {ci['auroc']['lower_95']:.3f}–{ci['auroc']['upper_95']:.3f})
- Brier score: {pooled['brier']:.3f} (95% CI {ci['brier']['lower_95']:.3f}–{ci['brier']['upper_95']:.3f})
- Thresholded recall: {pooled['recall']:.3f}; precision: {pooled['precision']:.3f}; F1: {pooled['f1']:.3f}

The 70% recall target is a product operating preference, not a clinical guarantee. Confidence intervals quantify participant sampling uncertainty in this dataset, not external validity.

## Input contract

Inputs must follow `feature_order` in the config JSON. Heart rate is first averaged to hourly values; window statistics are calculated across those hourly means. Steps are summed by hour and then across the window. At least half of the expected hours must be present for both heart rate and steps. The event hour is excluded. Sleep and resting heart rate must be available for D-1; otherwise the app should return `insufficient_data` rather than impute a risk.

The ONNX output is the uncalibrated base probability. Apply `sigmoid(slope * logit(p) + intercept)` from the config, then compare with the deployment threshold.

## Known limitations

- Only 63 people supplied any labels, and the final eligible cohort is smaller after strict sensor coverage.
- Labels are imbalanced and self-reported; they indicate a momentary response, not clinical stress.
- Nearly all source events occur between 10:00 and 23:00, so early-morning use is unsupported.
- LifeSnaps/Fitbit users may not represent HealthPal's deployment population or other wearable devices.
- D-1 daily alignment is conservative because the provided daily CSV has no per-record availability timestamp.
- Do not use protected demographics, Fitbit's proprietary `stress_score`, or the event-hour sensor row as inputs.

## Release gate

This artifact is a research baseline. Before user-facing deployment, run a prospective pilot on Health Connect data, verify Python/Rust/ONNX parity, assess subgroup calibration where sample size permits, version the feature contract, and monitor drift/insufficient-data rates.
"""
    path.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent / "artifacts" / "healthpal_stress_v1")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)

    hourly, daily, manifest = read_sources(args.data_dir.resolve())
    datasets = {window: build_event_dataset(hourly, daily, window) for window in WINDOWS}
    benchmark_results = benchmark(datasets)
    selected = select_one_se(benchmark_results)
    if selected["model"] != "logistic":
        raise RuntimeError("One-standard-error selection did not yield the ONNX-portable logistic model.")
    window = int(selected["window_hours"])
    feature_set = str(selected["feature_set"])
    features = FEATURE_SETS[feature_set]
    frame = datasets[window].reset_index(drop=True)
    x = frame[features].to_numpy(float)
    y = frame["target"].to_numpy(int)
    groups = frame["id"].to_numpy()

    oof, predictions, thresholds, fold_ids, fold_metrics, chosen_parameters = nested_evaluation(
        frame, features, "logistic"
    )
    pooled = classification_metrics(y, oof, predictions)
    bootstrap = participant_bootstrap(frame, oof)
    macro = participant_macro_metrics(frame, oof)

    final_parameter, final_tuning = tune_parameter(x, y, groups, "logistic", SEED + 500)
    full_oof_base = grouped_oof_base(x, y, groups, "logistic", final_parameter, 5, SEED + 600)
    final_calibration = fit_calibrator(y, full_oof_base)
    calibrated_full_oof = final_calibration.apply(full_oof_base)
    threshold_info = choose_threshold(y, calibrated_full_oof)
    final_estimator = fit_estimator(build_estimator("logistic", final_parameter), "logistic", x, y)

    model_path = output / "healthpal_stress_v1.onnx"
    parity_error = export_onnx(final_estimator, "logistic", len(features), model_path, x[:128])
    if parity_error > 1e-5:
        raise AssertionError(f"ONNX parity failed: maximum absolute error {parity_error}")
    joblib.dump(final_estimator, output / "healthpal_stress_v1.joblib")

    benchmark_results.to_csv(output / "benchmark_results.csv", index=False)
    fold_metrics.drop(columns=["inner_tuning"]).to_csv(output / "nested_fold_metrics.csv", index=False)
    training_dataset = frame[["id", "event_time", "target", "window_hours", *features]].copy()
    training_dataset.to_csv(output / "training_dataset.csv", index=False)
    oof_frame = frame[["id", "event_time", "target"]].copy()
    oof_frame["fold"] = fold_ids
    oof_frame["calibrated_probability"] = oof
    oof_frame["fold_threshold"] = thresholds
    oof_frame["prediction"] = predictions
    oof_frame.to_csv(output / "nested_oof_predictions.csv", index=False)

    config = {
        "model_name": "healthpal_stress_v1",
        "target": TARGET,
        "positive_class": 1,
        "model_family": "logistic_regression",
        "window_hours": window,
        "window_interval": "[T-window,T)",
        "daily_alignment": "previous_calendar_day_D_minus_1",
        "feature_order": features,
        "features": features,
        "minimum_hourly_coverage": math.ceil(window / 2),
        "hourly_aggregation": {
            "heart_rate": "mean raw samples by hour, then mean/std/min/max across hourly means",
            "steps": "sum by hour, then sum across window",
        },
        "missing_data_policy": "return_insufficient_data",
        "base_model_parameter_C": float(final_parameter),
        "calibration": {
            "method": "sigmoid_on_logit_probability",
            "slope": final_calibration.slope,
            "intercept": final_calibration.intercept,
            "formula": "sigmoid(slope * logit(clamp(base_probability,1e-6,1-1e-6)) + intercept)",
        },
        "decision_threshold": threshold_info,
        "onnx_output": "uncalibrated_positive_class_probability",
        "unsupported_time_warning": "Source labels are overwhelmingly 10:00-23:00; do not claim early-morning validity.",
    }
    (output / "healthpal_stress_v1_config.json").write_text(
        json.dumps(json_ready(config), indent=2), encoding="utf-8"
    )

    manifest.update(
        {
            "created_at_utc": datetime.now(timezone.utc).isoformat(),
            "python": sys.version,
            "platform": platform.platform(),
            "packages": {
                "numpy": np.__version__,
                "pandas": pd.__version__,
                "scikit_learn": sklearn.__version__,
                "onnx": onnx.__version__,
                "onnxruntime": ort.__version__,
            },
            "seed": SEED,
        }
    )
    (output / "dataset_manifest.json").write_text(
        json.dumps(json_ready(manifest), indent=2), encoding="utf-8"
    )

    metrics = {
        "selection_rule": "Highest mean grouped-CV AUPRC, then simplest logistic configuration within one SE of best.",
        "selected_benchmark": selected.to_dict(),
        "dataset": {
            "events": int(len(frame)),
            "positives": int(y.sum()),
            "prevalence": float(y.mean()),
            "participants": int(frame["id"].nunique()),
            "participants_with_positive": int(frame.loc[frame["target"].eq(1), "id"].nunique()),
        },
        "nested_oof_pooled": pooled,
        "participant_macro": macro,
        "cluster_bootstrap_95_ci": bootstrap,
        "outer_fold_metrics": fold_metrics.to_dict("records"),
        "outer_chosen_parameters": [float(value) for value in chosen_parameters],
        "final_parameter_tuning": final_tuning,
        "deployment_threshold": threshold_info,
        "onnx_max_absolute_probability_error": parity_error,
    }
    (output / "healthpal_stress_v1_metrics.json").write_text(
        json.dumps(json_ready(metrics), indent=2), encoding="utf-8"
    )
    create_report_plot(frame, oof, predictions, fold_metrics, output / "validation_report.png")
    write_model_card(output / "MODEL_CARD.md", metrics, config)

    artifact_hashes = {}
    for path in sorted(output.iterdir()):
        if path.is_file() and path.name != "artifact_checksums.sha256.json":
            artifact_hashes[path.name] = sha256(path)
    (output / "artifact_checksums.sha256.json").write_text(
        json.dumps(artifact_hashes, indent=2), encoding="utf-8"
    )
    print(json.dumps(json_ready({"output_dir": str(output), "metrics": metrics, "config": config}), indent=2))


if __name__ == "__main__":
    main()
