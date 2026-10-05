"""Train HealthPal stress-risk V2 with recency and activity-aware features.

Model/feature selection, hyperparameter tuning, calibration, and threshold choice
all happen inside outer participant-grouped folds. The reported V2 metric is the
outer out-of-fold result of that complete selection procedure.
"""

from __future__ import annotations

import argparse
import json
import math
import platform
import sys
from collections import Counter
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
import xgboost
from scipy.special import expit, logit
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
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
from xgboost import XGBClassifier

from train_healthpal_stress import TARGET, json_ready, read_sources, sha256

SEED = 20260928
WINDOWS = (2, 4, 6, 12)
MIN_RECALL = 0.70
LOW_ACTIVITY_THRESHOLDS = (100, 250)
MODEL_KINDS = ("logistic", "histgb", "xgboost")
ONNX_DEPLOYABLE_KINDS = ("logistic", "xgboost")
MVP_GATE = {
    "auprc_min": 0.20,
    "auroc_min": 0.65,
    "lowest_fold_auroc_min": 0.55,
    "auroc_ci_lower_min_exclusive": 0.50,
}


@dataclass(frozen=True)
class FeatureSpec:
    name: str
    experiment: str
    features: tuple[str, ...]
    window_hours: int
    requires_exercise_mask: bool = False
    low_activity_threshold: int | None = None


@dataclass(frozen=True)
class Calibration:
    slope: float
    intercept: float

    def apply(self, probabilities: np.ndarray) -> np.ndarray:
        clipped = np.clip(probabilities, 1e-6, 1 - 1e-6)
        return expit(self.slope * logit(clipped) + self.intercept)


def _prefix(window: int) -> str:
    return f"h{window}_"


def _base_features(window: int) -> list[str]:
    p = _prefix(window)
    return ["resting_hr", "sleep_minutes", f"{p}steps_sum"]


def feature_specs() -> list[FeatureSpec]:
    specs: list[FeatureSpec] = []
    for window in WINDOWS:
        p = _prefix(window)
        specs.append(
            FeatureSpec(
                f"w{window}_full_minmax",
                "short_window",
                tuple([f"{p}hr_mean", f"{p}hr_std", f"{p}hr_min", f"{p}hr_max", *_base_features(window)]),
                window,
            )
        )
    for window in (4, 6, 12):
        p = _prefix(window)
        specs.append(
            FeatureSpec(
                f"w{window}_robust_quantiles",
                "robust_hr",
                tuple(
                    [
                        f"{p}hr_mean",
                        f"{p}hr_std",
                        f"{p}hr_median",
                        f"{p}hr_p25",
                        f"{p}hr_p75",
                        *_base_features(window),
                    ]
                ),
                window,
            )
        )
    for window in (2, 4, 6, 12):
        p = _prefix(window)
        specs.append(
            FeatureSpec(
                f"w{window}_relative_rhr",
                "relative_rhr",
                tuple(
                    [
                        f"{p}hr_mean",
                        f"{p}hr_std",
                        f"{p}hr_min",
                        f"{p}hr_max",
                        f"{p}hr_mean_minus_rhr",
                        f"{p}hr_min_minus_rhr",
                        f"{p}hr_max_minus_rhr",
                        *_base_features(window),
                    ]
                ),
                window,
            )
        )
    for window in (4, 6):
        p = _prefix(window)
        for threshold in LOW_ACTIVITY_THRESHOLDS:
            specs.append(
                FeatureSpec(
                    f"w{window}_low_activity_{threshold}",
                    "low_activity_hr",
                    tuple(
                        [
                            f"{p}hr_mean",
                            f"{p}hr_std",
                            f"{p}hr_median",
                            f"{p}hr_p25",
                            f"{p}hr_p75",
                            f"{p}low{threshold}_hr_mean",
                            f"{p}low{threshold}_hr_std",
                            f"{p}low{threshold}_hours",
                            f"{p}hr_mean_minus_rhr",
                            *_base_features(window),
                        ]
                    ),
                    window,
                    low_activity_threshold=threshold,
                )
            )
        specs.append(
            FeatureSpec(
                f"w{window}_exercise_masked",
                "exercise_mask",
                tuple(
                    [
                        f"{p}masked_hr_mean",
                        f"{p}masked_hr_std",
                        f"{p}masked_hr_median",
                        f"{p}masked_hr_p25",
                        f"{p}masked_hr_p75",
                        f"{p}masked_hr_hours",
                        f"{p}exercise_hours",
                        "resting_hr",
                        "sleep_minutes",
                        f"{p}steps_sum",
                    ]
                ),
                window,
                requires_exercise_mask=True,
            )
        )

    multiscale_base = [
        "h2_hr_mean",
        "h2_hr_std",
        "h2_steps_sum",
        "h6_hr_mean",
        "h6_hr_std",
        "h6_steps_sum",
        "recency_hr_mean_delta_2h_6h",
        "recency_hr_std_delta_2h_6h",
        "h2_hr_mean_minus_rhr",
        "h6_hr_mean_minus_rhr",
        "resting_hr",
        "sleep_minutes",
    ]
    specs.append(FeatureSpec("multiscale_2h_6h", "recency", tuple(multiscale_base), 6))
    specs.append(
        FeatureSpec(
            "multiscale_2h_6h_robust",
            "recency_robust",
            tuple(multiscale_base + ["h2_hr_median", "h2_hr_p25", "h2_hr_p75", "h6_hr_median", "h6_hr_p25", "h6_hr_p75"]),
            6,
        )
    )
    specs.append(
        FeatureSpec(
            "multiscale_2h_6h_low100",
            "recency_low_activity",
            tuple(
                multiscale_base
                + [
                    "h2_low100_hr_mean",
                    "h2_low100_hr_std",
                    "h2_low100_hours",
                    "h6_low100_hr_mean",
                    "h6_low100_hr_std",
                    "h6_low100_hours",
                ]
            ),
            6,
            low_activity_threshold=100,
        )
    )
    return specs


def _finite(values: np.ndarray) -> np.ndarray:
    return values[np.isfinite(values)]


def _summary(values: np.ndarray) -> dict[str, float]:
    values = _finite(values)
    if len(values) == 0:
        return {name: np.nan for name in ("mean", "std", "min", "max", "median", "p25", "p75")}
    return {
        "mean": float(np.mean(values)),
        "std": float(np.std(values, ddof=0)),
        "min": float(np.min(values)),
        "max": float(np.max(values)),
        "median": float(np.median(values)),
        "p25": float(np.quantile(values, 0.25)),
        "p75": float(np.quantile(values, 0.75)),
    }


def build_wide_event_dataset(hourly: pd.DataFrame, daily: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
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
        exercise = stream["activityType"].notna().to_numpy(bool)

        for event in participant_events.itertuples(index=False):
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

            row = {
                "id": participant,
                "event_time": pd.Timestamp(event.timestamp),
                "target": int(event.target),
                "resting_hr": resting_hr,
                "sleep_minutes": sleep_minutes,
            }
            all_windows_eligible = True
            event_time = np.datetime64(event.timestamp, "ns")
            for window in WINDOWS:
                p = _prefix(window)
                start_time = event_time - np.timedelta64(window, "h")
                left = int(np.searchsorted(times, start_time, side="left"))
                right = int(np.searchsorted(times, event_time, side="left"))
                window_times = times[left:right]
                if len(window_times) and not np.all((window_times >= start_time) & (window_times < event_time)):
                    raise AssertionError("Leakage invariant failed: feature window is not [T-window, T).")
                window_bpm = bpm[left:right]
                window_steps = steps[left:right]
                window_exercise = exercise[left:right]
                valid_bpm = _finite(window_bpm)
                valid_steps = _finite(window_steps)
                eligible = len(valid_bpm) >= math.ceil(window / 2) and len(valid_steps) >= math.ceil(window / 2)
                row[f"eligible_h{window}"] = eligible
                all_windows_eligible &= eligible
                if not eligible:
                    continue

                summary = _summary(valid_bpm)
                for name, value in summary.items():
                    row[f"{p}hr_{name}"] = value
                row[f"{p}steps_sum"] = float(np.sum(valid_steps))
                row[f"{p}hr_mean_minus_rhr"] = summary["mean"] - resting_hr
                row[f"{p}hr_min_minus_rhr"] = summary["min"] - resting_hr
                row[f"{p}hr_max_minus_rhr"] = summary["max"] - resting_hr

                for threshold in LOW_ACTIVITY_THRESHOLDS:
                    low_mask = np.isfinite(window_bpm) & np.isfinite(window_steps) & (window_steps <= threshold)
                    low_values = window_bpm[low_mask]
                    low_summary = _summary(low_values)
                    row[f"{p}low{threshold}_hr_mean"] = low_summary["mean"]
                    row[f"{p}low{threshold}_hr_std"] = low_summary["std"]
                    row[f"{p}low{threshold}_hours"] = int(len(low_values))

                masked_values = window_bpm[np.isfinite(window_bpm) & ~window_exercise]
                masked_summary = _summary(masked_values)
                for name in ("mean", "std", "median", "p25", "p75"):
                    row[f"{p}masked_hr_{name}"] = masked_summary[name]
                row[f"{p}masked_hr_hours"] = int(len(masked_values))
                row[f"{p}exercise_hours"] = int(np.sum(window_exercise))

            row["eligible_all_windows"] = all_windows_eligible
            if all_windows_eligible:
                row["recency_hr_mean_delta_2h_6h"] = row["h2_hr_mean"] - row["h6_hr_mean"]
                row["recency_hr_std_delta_2h_6h"] = row["h2_hr_std"] - row["h6_hr_std"]
                rows.append(row)

    frame = pd.DataFrame(rows).sort_values(["id", "event_time"]).reset_index(drop=True)
    if frame.empty:
        raise ValueError("No events satisfy the common V2 cohort requirements.")
    audit = {
        "common_cohort_policy": "D-1 sleep/RHR plus half-window HR and steps coverage in every 2h/4h/6h/12h window",
        "events": int(len(frame)),
        "positives": int(frame["target"].sum()),
        "prevalence": float(frame["target"].mean()),
        "participants": int(frame["id"].nunique()),
        "participants_with_positive": int(frame.loc[frame["target"].eq(1), "id"].nunique()),
        "events_with_exercise_in_previous_6h": int(frame["h6_exercise_hours"].gt(0).sum()),
        "low100_missing_rate_4h": float(frame["h4_low100_hr_mean"].isna().mean()),
        "low100_missing_rate_6h": float(frame["h6_low100_hr_mean"].isna().mean()),
    }
    return frame, audit


def grouped_splits(y: np.ndarray, groups: np.ndarray, folds: int, seed: int):
    splitter = StratifiedGroupKFold(n_splits=folds, shuffle=True, random_state=seed)
    return list(splitter.split(np.zeros(len(y)), y, groups))


def fixed_parameter(kind: str) -> dict:
    if kind == "logistic":
        return {"C": 1.0}
    if kind == "histgb":
        return {"max_leaf_nodes": 7, "learning_rate": 0.05, "max_iter": 200}
    if kind == "xgboost":
        return {"max_depth": 2, "learning_rate": 0.03, "n_estimators": 200}
    raise ValueError(kind)


def parameter_grid(kind: str) -> list[dict]:
    if kind == "logistic":
        return [{"C": value} for value in (0.03, 0.1, 0.3, 1.0, 3.0, 10.0)]
    if kind == "histgb":
        return [
            {"max_leaf_nodes": leaves, "learning_rate": rate, "max_iter": iterations}
            for leaves, rate, iterations in ((5, 0.03, 200), (7, 0.05, 200), (15, 0.03, 250), (31, 0.03, 250))
        ]
    if kind == "xgboost":
        return [
            {"max_depth": depth, "learning_rate": rate, "n_estimators": estimators}
            for depth, rate, estimators in ((1, 0.03, 200), (2, 0.03, 200), (2, 0.05, 250), (3, 0.03, 250))
        ]
    raise ValueError(kind)


def build_estimator(kind: str, parameter: dict, seed: int):
    if kind == "logistic":
        return Pipeline(
            [
                ("impute", SimpleImputer(strategy="median", keep_empty_features=True)),
                ("scale", StandardScaler()),
                (
                    "classifier",
                    LogisticRegression(
                        C=float(parameter["C"]),
                        class_weight="balanced",
                        max_iter=3000,
                        random_state=seed,
                    ),
                ),
            ]
        )
    if kind == "histgb":
        return HistGradientBoostingClassifier(
            learning_rate=float(parameter["learning_rate"]),
            max_iter=int(parameter["max_iter"]),
            max_leaf_nodes=int(parameter["max_leaf_nodes"]),
            l2_regularization=2.0,
            min_samples_leaf=30,
            random_state=seed,
        )
    if kind == "xgboost":
        return XGBClassifier(
            objective="binary:logistic",
            eval_metric="logloss",
            max_depth=int(parameter["max_depth"]),
            learning_rate=float(parameter["learning_rate"]),
            n_estimators=int(parameter["n_estimators"]),
            min_child_weight=10,
            subsample=0.8,
            colsample_bytree=0.8,
            reg_lambda=5.0,
            reg_alpha=0.2,
            n_jobs=1,
            random_state=seed,
        )
    raise ValueError(kind)


def fit_estimator(estimator, kind: str, x: np.ndarray, y: np.ndarray):
    if kind in {"histgb", "xgboost"}:
        estimator.fit(x, y, sample_weight=compute_sample_weight("balanced", y))
    else:
        estimator.fit(x, y)
    return estimator


def safe_auroc(y: np.ndarray, p: np.ndarray) -> float:
    return float(roc_auc_score(y, p)) if np.unique(y).size == 2 else float("nan")


def probability_metrics(y: np.ndarray, p: np.ndarray) -> dict:
    return {
        "auprc": float(average_precision_score(y, p)),
        "auroc": safe_auroc(y, p),
        "brier": float(brier_score_loss(y, p)),
    }


def evaluate_candidate(
    frame: pd.DataFrame,
    spec: FeatureSpec,
    kind: str,
    splits: list[tuple[np.ndarray, np.ndarray]],
    parameter: dict,
    seed: int,
) -> dict:
    x = frame[list(spec.features)].to_numpy(float)
    y = frame["target"].to_numpy(int)
    scores = []
    aurocs = []
    for fold, (train, test) in enumerate(splits):
        estimator = fit_estimator(build_estimator(kind, parameter, seed + fold), kind, x[train], y[train])
        p = estimator.predict_proba(x[test])[:, 1]
        scores.append(float(average_precision_score(y[test], p)))
        aurocs.append(safe_auroc(y[test], p))
    return {
        "feature_spec": spec.name,
        "experiment": spec.experiment,
        "model": kind,
        "window_hours": spec.window_hours,
        "feature_count": len(spec.features),
        "mean_auprc": float(np.mean(scores)),
        "se_auprc": float(np.std(scores, ddof=1) / np.sqrt(len(scores))),
        "mean_auroc": float(np.nanmean(aurocs)),
        "fold_auprc": scores,
        "fold_auroc": aurocs,
    }


def one_se_select(results: pd.DataFrame) -> pd.Series:
    ranked = results.sort_values("mean_auprc", ascending=False).reset_index(drop=True)
    best = ranked.iloc[0]
    floor = float(best["mean_auprc"] - best["se_auprc"])
    eligible = ranked.loc[ranked["mean_auprc"].ge(floor)].copy()
    eligible["model_rank"] = eligible["model"].map({"logistic": 0, "histgb": 1, "xgboost": 2})
    eligible["window_rank"] = (eligible["window_hours"] - 4).abs()
    return eligible.sort_values(
        ["model_rank", "feature_count", "window_rank", "mean_auprc"],
        ascending=[True, True, True, False],
    ).iloc[0]


def benchmark_candidates(
    frame: pd.DataFrame,
    specs: list[FeatureSpec],
    splits: list[tuple[np.ndarray, np.ndarray]],
    seed: int,
) -> pd.DataFrame:
    rows = []
    for spec in specs:
        for kind in MODEL_KINDS:
            rows.append(evaluate_candidate(frame, spec, kind, splits, fixed_parameter(kind), seed))
    return pd.DataFrame(rows).sort_values("mean_auprc", ascending=False).reset_index(drop=True)


def tune_parameter(
    frame: pd.DataFrame,
    spec: FeatureSpec,
    kind: str,
    splits: list[tuple[np.ndarray, np.ndarray]],
    seed: int,
) -> tuple[dict, list[dict]]:
    rows = []
    for parameter in parameter_grid(kind):
        result = evaluate_candidate(frame, spec, kind, splits, parameter, seed)
        rows.append({"parameter": parameter, "mean_auprc": result["mean_auprc"], "se_auprc": result["se_auprc"]})
    rows.sort(key=lambda row: (-row["mean_auprc"], json.dumps(row["parameter"], sort_keys=True)))
    return rows[0]["parameter"], rows


def grouped_oof_base(
    frame: pd.DataFrame,
    spec: FeatureSpec,
    kind: str,
    parameter: dict,
    splits: list[tuple[np.ndarray, np.ndarray]],
    seed: int,
) -> np.ndarray:
    x = frame[list(spec.features)].to_numpy(float)
    y = frame["target"].to_numpy(int)
    oof = np.full(len(frame), np.nan)
    for fold, (train, test) in enumerate(splits):
        estimator = fit_estimator(build_estimator(kind, parameter, seed + fold), kind, x[train], y[train])
        oof[test] = estimator.predict_proba(x[test])[:, 1]
    if np.isnan(oof).any():
        raise AssertionError("OOF generation left unpredicted rows.")
    return oof


def fit_calibrator(y: np.ndarray, base_probabilities: np.ndarray) -> Calibration:
    z = logit(np.clip(base_probabilities, 1e-6, 1 - 1e-6)).reshape(-1, 1)
    model = LogisticRegression(C=1e6, max_iter=2000, random_state=SEED).fit(z, y)
    return Calibration(float(model.coef_[0, 0]), float(model.intercept_[0]))


def choose_threshold(y: np.ndarray, p: np.ndarray) -> dict:
    precision, recall, thresholds = precision_recall_curve(y, p)
    candidates = []
    for current_precision, current_recall, threshold in zip(precision[:-1], recall[:-1], thresholds):
        if current_recall >= MIN_RECALL:
            f1 = 2 * current_precision * current_recall / max(current_precision + current_recall, 1e-12)
            candidates.append((f1, current_precision, current_recall, threshold))
    chosen = max(candidates, key=lambda item: (item[0], item[1], item[3]))
    return {
        "threshold": float(chosen[3]),
        "training_f1": float(chosen[0]),
        "training_precision": float(chosen[1]),
        "training_recall": float(chosen[2]),
        "minimum_recall_constraint": MIN_RECALL,
    }


def nested_selection_evaluation(frame: pd.DataFrame, specs: list[FeatureSpec]):
    y = frame["target"].to_numpy(int)
    groups = frame["id"].to_numpy()
    outer_splits = grouped_splits(y, groups, 5, SEED)
    oof = np.full(len(frame), np.nan)
    predictions = np.full(len(frame), -1, dtype=int)
    thresholds = np.full(len(frame), np.nan)
    fold_ids = np.full(len(frame), -1, dtype=int)
    fold_rows = []
    all_inner_benchmarks = []

    for outer_fold, (outer_train, outer_test) in enumerate(outer_splits, start=1):
        print(f"V2 outer fold {outer_fold}/5: candidate selection", flush=True)
        train_frame = frame.iloc[outer_train].reset_index(drop=True)
        train_y = train_frame["target"].to_numpy(int)
        train_groups = train_frame["id"].to_numpy()
        inner_splits = grouped_splits(train_y, train_groups, 4, SEED + outer_fold)
        inner_results = benchmark_candidates(train_frame, specs, inner_splits, SEED + 100 * outer_fold)
        inner_results["outer_fold"] = outer_fold
        all_inner_benchmarks.append(inner_results)
        selected = one_se_select(inner_results)
        spec = next(item for item in specs if item.name == selected["feature_spec"])
        kind = str(selected["model"])
        parameter, tuning = tune_parameter(train_frame, spec, kind, inner_splits, SEED + 1000 + outer_fold)

        inner_base = grouped_oof_base(
            train_frame, spec, kind, parameter, inner_splits, SEED + 2000 + outer_fold
        )
        calibration = fit_calibrator(train_y, inner_base)
        threshold_info = choose_threshold(train_y, calibration.apply(inner_base))
        x_train = train_frame[list(spec.features)].to_numpy(float)
        test_frame = frame.iloc[outer_test]
        x_test = test_frame[list(spec.features)].to_numpy(float)
        estimator = fit_estimator(build_estimator(kind, parameter, SEED + outer_fold), kind, x_train, train_y)
        test_base = estimator.predict_proba(x_test)[:, 1]
        test_probability = calibration.apply(test_base)
        test_prediction = (test_probability >= threshold_info["threshold"]).astype(int)
        test_y = y[outer_test]

        oof[outer_test] = test_probability
        predictions[outer_test] = test_prediction
        thresholds[outer_test] = threshold_info["threshold"]
        fold_ids[outer_test] = outer_fold
        fold_metric = probability_metrics(test_y, test_probability)
        fold_rows.append(
            {
                "fold": outer_fold,
                "feature_spec": spec.name,
                "experiment": spec.experiment,
                "model": kind,
                "window_hours": spec.window_hours,
                "feature_count": len(spec.features),
                "parameter": parameter,
                "train_participants": int(train_frame["id"].nunique()),
                "test_participants": int(test_frame["id"].nunique()),
                "train_events": int(len(train_frame)),
                "test_events": int(len(test_frame)),
                "test_positives": int(test_y.sum()),
                "inner_selected_mean_auprc": float(selected["mean_auprc"]),
                "calibration_slope": calibration.slope,
                "calibration_intercept": calibration.intercept,
                "threshold": threshold_info["threshold"],
                **fold_metric,
                "precision": float(precision_score(test_y, test_prediction, zero_division=0)),
                "recall": float(recall_score(test_y, test_prediction, zero_division=0)),
                "f1": float(f1_score(test_y, test_prediction, zero_division=0)),
                "tuning": tuning,
            }
        )
        print(
            f"  selected={spec.name}/{kind}; outer AUPRC={fold_metric['auprc']:.3f}; AUROC={fold_metric['auroc']:.3f}",
            flush=True,
        )
    if np.isnan(oof).any() or (fold_ids < 0).any():
        raise AssertionError("Nested selection left unpredicted rows.")
    return (
        oof,
        predictions,
        thresholds,
        fold_ids,
        pd.DataFrame(fold_rows),
        pd.concat(all_inner_benchmarks, ignore_index=True),
    )


def classification_metrics(y: np.ndarray, p: np.ndarray, pred: np.ndarray) -> dict:
    tn, fp, fn, tp = confusion_matrix(y, pred, labels=[0, 1]).ravel()
    result = probability_metrics(y, p)
    result.update(
        {
            "precision": float(precision_score(y, pred, zero_division=0)),
            "recall": float(recall_score(y, pred, zero_division=0)),
            "f1": float(f1_score(y, pred, zero_division=0)),
            "specificity": float(tn / (tn + fp)),
            "confusion_matrix": {"tn": int(tn), "fp": int(fp), "fn": int(fn), "tp": int(tp)},
        }
    )
    return result


def participant_bootstrap(frame: pd.DataFrame, p: np.ndarray, replicates: int = 1000) -> dict:
    rng = np.random.default_rng(SEED)
    indices_by_participant = {
        participant: np.asarray(list(index), dtype=int)
        for participant, index in frame.groupby("id").groups.items()
    }
    participants = np.asarray(list(indices_by_participant))
    values = {"auprc": [], "auroc": [], "brier": []}
    for _ in range(replicates):
        sampled = rng.choice(participants, len(participants), replace=True)
        indices = np.concatenate([indices_by_participant[item] for item in sampled])
        y = frame.loc[indices, "target"].to_numpy(int)
        probabilities = p[indices]
        if np.unique(y).size < 2:
            continue
        values["auprc"].append(average_precision_score(y, probabilities))
        values["auroc"].append(roc_auc_score(y, probabilities))
        values["brier"].append(brier_score_loss(y, probabilities))
    return {
        name: {
            "lower_95": float(np.quantile(metric_values, 0.025)),
            "upper_95": float(np.quantile(metric_values, 0.975)),
        }
        for name, metric_values in values.items()
    }


def evaluate_gate(metrics: dict, fold_metrics: pd.DataFrame, bootstrap: dict) -> dict:
    checks = {
        "auprc": metrics["auprc"] >= MVP_GATE["auprc_min"],
        "auroc": metrics["auroc"] >= MVP_GATE["auroc_min"],
        "lowest_fold_auroc": float(fold_metrics["auroc"].min()) >= MVP_GATE["lowest_fold_auroc_min"],
        "auroc_ci_lower": bootstrap["auroc"]["lower_95"] > MVP_GATE["auroc_ci_lower_min_exclusive"],
    }
    return {
        "passed": bool(all(checks.values())),
        "checks": checks,
        "thresholds": MVP_GATE,
        "observed": {
            "auprc": metrics["auprc"],
            "auroc": metrics["auroc"],
            "lowest_fold_auroc": float(fold_metrics["auroc"].min()),
            "auroc_ci_lower": bootstrap["auroc"]["lower_95"],
        },
    }


def export_onnx(estimator, kind: str, feature_count: int, path: Path, sample: np.ndarray) -> float:
    if kind in {"logistic", "histgb"}:
        options = {}
        if kind == "logistic":
            options[id(estimator.named_steps["classifier"])] = {"zipmap": False}
        else:
            options[id(estimator)] = {"zipmap": False}
        model = convert_sklearn(
            estimator,
            initial_types=[("float_input", FloatTensorType([None, feature_count]))],
            options=options,
            target_opset=17,
        )
    else:
        from onnxmltools.convert import convert_xgboost
        from onnxmltools.convert.common.data_types import FloatTensorType as XGBFloatTensorType

        model = convert_xgboost(
            estimator,
            initial_types=[("float_input", XGBFloatTensorType([None, feature_count]))],
            target_opset=15,
        )
    path.write_bytes(model.SerializeToString())
    onnx.checker.check_model(onnx.load(path))
    session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    outputs = session.run(None, {session.get_inputs()[0].name: sample.astype(np.float32)})
    probability_candidates = [item for item in outputs if isinstance(item, np.ndarray) and item.ndim == 2]
    if not probability_candidates:
        raise ValueError("Could not locate ONNX probability tensor.")
    onnx_probability = probability_candidates[-1][:, 1]
    python_probability = estimator.predict_proba(sample)[:, 1]
    return float(np.max(np.abs(onnx_probability - python_probability)))


def create_report(
    frame: pd.DataFrame,
    probabilities: np.ndarray,
    folds: pd.DataFrame,
    final_benchmark: pd.DataFrame,
    gate: dict,
    output_path: Path,
) -> None:
    y = frame["target"].to_numpy(int)
    fig, axes = plt.subplots(2, 2, figsize=(12, 9))
    precision, recall, _ = precision_recall_curve(y, probabilities)
    axes[0, 0].plot(recall, precision, color="#00695c", lw=2)
    axes[0, 0].axhline(y.mean(), color="#777", ls="--", label=f"Prevalence {y.mean():.3f}")
    axes[0, 0].axhline(MVP_GATE["auprc_min"], color="#c62828", ls=":", label="MVP AUPRC gate")
    axes[0, 0].set(title="Nested-selection OOF precision-recall", xlabel="Recall", ylabel="Precision")
    axes[0, 0].legend()

    fpr, tpr, _ = roc_curve(y, probabilities)
    axes[0, 1].plot(fpr, tpr, color="#1565c0", lw=2)
    axes[0, 1].plot([0, 1], [0, 1], color="#777", ls="--")
    axes[0, 1].set(title="Nested-selection OOF ROC", xlabel="False-positive rate", ylabel="True-positive rate")

    top = final_benchmark.head(12).iloc[::-1]
    labels = top["feature_spec"] + " / " + top["model"]
    colors = ["#ef6c00" if value >= MVP_GATE["auprc_min"] else "#607d8b" for value in top["mean_auprc"]]
    axes[1, 0].barh(labels, top["mean_auprc"], color=colors)
    axes[1, 0].axvline(y.mean(), color="#777", ls="--")
    axes[1, 0].axvline(MVP_GATE["auprc_min"], color="#c62828", ls=":")
    axes[1, 0].set(title="Top development candidates", xlabel="Mean fold AUPRC")
    axes[1, 0].tick_params(axis="y", labelsize=8)

    axes[1, 1].bar(folds["fold"].astype(str), folds["auroc"], color="#7b1fa2")
    axes[1, 1].axhline(0.5, color="#777", ls="--", label="Chance")
    axes[1, 1].axhline(MVP_GATE["lowest_fold_auroc_min"], color="#c62828", ls=":", label="Fold gate")
    axes[1, 1].set_ylim(0.35, 0.75)
    axes[1, 1].set(title=f"Outer-fold AUROC (gate {'PASS' if gate['passed'] else 'FAIL'})", xlabel="Fold", ylabel="AUROC")
    axes[1, 1].legend()
    fig.suptitle("HealthPal stress-risk V2 validation", fontsize=15)
    fig.tight_layout()
    fig.savefig(output_path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def write_model_card(path: Path, metrics: dict, config: dict) -> None:
    pooled = metrics["nested_selection_oof"]
    ci = metrics["cluster_bootstrap_95_ci"]
    gate = metrics["mvp_gate"]
    path.write_text(
        f"""# HealthPal stress-risk model V2

## Decision

MVP engineering gate: **{'PASS' if gate['passed'] else 'FAIL'}**.

This model estimates the probability that a LifeSnaps SEMA event is labelled `TENSE/ANXIOUS`. It is a wellness research signal, not a medical diagnosis or clinical stress score. Training readiness remains a separate conservative rule engine.

## V2 experiments

- Short windows: 2h, 4h, 6h and 12h.
- Recency: paired 2h/6h features and their mean/std deltas.
- HR relative to resting HR.
- Low-activity HR at 100 and 250 steps/hour.
- Binary exercise masking from non-null exercise-session-like records; activity type names are never inputs.
- Robust HR summaries (median/p25/p75) versus min/max.
- Logistic regression, histogram gradient boosting and XGBoost; no neural network.

## Validation design

All candidate rows use one common event cohort. Five outer folds are grouped by participant. Each outer training fold uses four grouped inner folds to select the feature specification and model family with a one-standard-error simplicity rule, tune hyperparameters, fit sigmoid calibration and select a threshold. Outer labels are untouched until final fold scoring.

- Events: {metrics['dataset']['events']:,}; positives: {metrics['dataset']['positives']:,}; prevalence: {metrics['dataset']['prevalence']:.3f}
- Participants: {metrics['dataset']['participants']}
- AUPRC: {pooled['auprc']:.3f} (participant-cluster 95% CI {ci['auprc']['lower_95']:.3f}–{ci['auprc']['upper_95']:.3f})
- AUROC: {pooled['auroc']:.3f} (95% CI {ci['auroc']['lower_95']:.3f}–{ci['auroc']['upper_95']:.3f})
- Lowest outer-fold AUROC: {gate['observed']['lowest_fold_auroc']:.3f}
- Brier score: {pooled['brier']:.3f}
- Recall: {pooled['recall']:.3f}; precision: {pooled['precision']:.3f}; F1: {pooled['f1']:.3f}

## Final artifact

- Feature specification: `{config['feature_spec']}`
- Model: `{config['model_family']}`
- Features: {', '.join(config['feature_order'])}
- Daily alignment: D-1 sleep and resting HR
- All rolling windows are strictly `[T-window, T)`.

The ONNX output is the uncalibrated positive-class probability. Apply the calibration formula and deployment threshold in the config JSON. Missing required base-window coverage or D-1 values must produce `insufficient_data`. Low-activity summary fields may use the training-fold median imputation embedded in a logistic ONNX pipeline; tree models consume missing values natively.

## Limitations

- The cohort is small and self-reported, and the final gate determines whether this remains research-only.
- Candidate selection explores many plausible features; nested outer evaluation limits but cannot eliminate uncertainty from a small number of participants.
- Exercise-session records are sparse. Production must use Health Connect's binary Exercise Session overlap, never infer exercise type from this dataset.
- Source labels are concentrated between 10:00 and 23:00; early-morning validity is unsupported.
- Do not include demographics, Fitbit `stress_score`, or the event-hour sensor record.
""",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent / "artifacts" / "healthpal_stress_v2")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)

    hourly, daily, source_manifest = read_sources(args.data_dir.resolve())
    frame, dataset_audit = build_wide_event_dataset(hourly, daily)
    specs = feature_specs()
    print(f"V2 common cohort: {len(frame)} events, {frame['target'].sum()} positives, {frame['id'].nunique()} participants", flush=True)
    print(f"V2 candidates: {len(specs)} feature specs x {len(MODEL_KINDS)} model families", flush=True)

    oof, predictions, thresholds, fold_ids, fold_metrics, inner_benchmarks = nested_selection_evaluation(frame, specs)
    y = frame["target"].to_numpy(int)
    groups = frame["id"].to_numpy()
    pooled = classification_metrics(y, oof, predictions)
    bootstrap = participant_bootstrap(frame, oof)
    gate = evaluate_gate(pooled, fold_metrics, bootstrap)

    print("V2 final full-data candidate benchmark", flush=True)
    full_splits = grouped_splits(y, groups, 5, SEED + 5000)
    final_benchmark = benchmark_candidates(frame, specs, full_splits, SEED + 6000)
    best_research_candidate = final_benchmark.iloc[0]
    selected = one_se_select(final_benchmark.loc[final_benchmark["model"].isin(ONNX_DEPLOYABLE_KINDS)])
    final_spec = next(item for item in specs if item.name == selected["feature_spec"])
    final_kind = str(selected["model"])
    final_parameter, final_tuning = tune_parameter(
        frame, final_spec, final_kind, full_splits, SEED + 7000
    )
    full_oof_base = grouped_oof_base(
        frame, final_spec, final_kind, final_parameter, full_splits, SEED + 8000
    )
    final_calibration = fit_calibrator(y, full_oof_base)
    final_threshold = choose_threshold(y, final_calibration.apply(full_oof_base))
    x = frame[list(final_spec.features)].to_numpy(float)
    final_estimator = fit_estimator(
        build_estimator(final_kind, final_parameter, SEED + 9000), final_kind, x, y
    )

    model_path = output / "healthpal_stress_v2.onnx"
    parity_error = export_onnx(final_estimator, final_kind, len(final_spec.features), model_path, x[:256])
    if parity_error > 1e-5:
        raise AssertionError(f"ONNX parity failed: maximum absolute error {parity_error}")
    joblib.dump(final_estimator, output / "healthpal_stress_v2.joblib")
    if final_kind == "xgboost":
        final_estimator.save_model(output / "healthpal_stress_v2_xgboost.json")

    config = {
        "model_name": "healthpal_stress_v2",
        "target": TARGET,
        "positive_class": 1,
        "feature_spec": final_spec.name,
        "experiment": final_spec.experiment,
        "model_family": final_kind,
        "model_parameter": final_parameter,
        "feature_order": list(final_spec.features),
        "primary_window_hours": final_spec.window_hours,
        "window_interval": "[T-window,T)",
        "daily_alignment": "previous_calendar_day_D_minus_1",
        "minimum_hourly_coverage": {str(window): math.ceil(window / 2) for window in WINDOWS},
        "low_activity_steps_per_hour_threshold": final_spec.low_activity_threshold,
        "requires_binary_exercise_session_mask": final_spec.requires_exercise_mask,
        "exercise_mask_contract": "Exclude hourly HR bins overlapping any Health Connect Exercise Session; exercise type is unused.",
        "hourly_aggregation": {
            "heart_rate": "mean raw HR samples by hour, then aggregate the hourly means",
            "steps": "sum by hour, then sum within each causal window",
            "quantiles": "p25/median/p75 over hourly HR means",
        },
        "missing_base_data_policy": "return_insufficient_data",
        "calibration": {
            "method": "sigmoid_on_logit_probability",
            "slope": final_calibration.slope,
            "intercept": final_calibration.intercept,
            "formula": "sigmoid(slope * logit(clamp(base_probability,1e-6,1-1e-6)) + intercept)",
        },
        "decision_threshold": final_threshold,
        "onnx_output": "uncalibrated_positive_class_probability",
        "mvp_gate_passed": gate["passed"],
    }
    (output / "healthpal_stress_v2_config.json").write_text(
        json.dumps(json_ready(config), indent=2), encoding="utf-8"
    )

    fold_export = fold_metrics.drop(columns=["tuning"]).copy()
    fold_export["parameter"] = fold_export["parameter"].apply(lambda value: json.dumps(value, sort_keys=True))
    fold_export.to_csv(output / "nested_selection_fold_metrics.csv", index=False)
    inner_export = inner_benchmarks.copy()
    inner_export["fold_auprc"] = inner_export["fold_auprc"].apply(json.dumps)
    inner_export["fold_auroc"] = inner_export["fold_auroc"].apply(json.dumps)
    inner_export.to_csv(output / "inner_candidate_benchmarks.csv", index=False)
    final_export = final_benchmark.copy()
    final_export["fold_auprc"] = final_export["fold_auprc"].apply(json.dumps)
    final_export["fold_auroc"] = final_export["fold_auroc"].apply(json.dumps)
    final_export.to_csv(output / "final_candidate_benchmark.csv", index=False)

    selected_counts = Counter(f"{row.feature_spec}/{row.model}" for row in fold_metrics.itertuples())
    pd.DataFrame(
        [{"candidate": candidate, "outer_fold_selections": count} for candidate, count in selected_counts.items()]
    ).sort_values("outer_fold_selections", ascending=False).to_csv(output / "outer_selection_frequency.csv", index=False)

    oof_frame = frame[["id", "event_time", "target"]].copy()
    oof_frame["fold"] = fold_ids
    oof_frame["calibrated_probability"] = oof
    oof_frame["fold_threshold"] = thresholds
    oof_frame["prediction"] = predictions
    oof_frame.to_csv(output / "nested_selection_oof_predictions.csv", index=False)
    export_columns = ["id", "event_time", "target", *sorted({feature for spec in specs for feature in spec.features})]
    frame[export_columns].to_csv(output / "v2_common_training_dataset.csv", index=False)

    metrics = {
        "evaluation_unit": "complete inner feature/model selection policy evaluated on held-out participant outer folds",
        "dataset": dataset_audit,
        "candidate_count": len(specs) * len(MODEL_KINDS),
        "nested_selection_oof": pooled,
        "cluster_bootstrap_95_ci": bootstrap,
        "outer_fold_metrics": fold_metrics.to_dict("records"),
        "outer_selection_frequency": dict(selected_counts),
        "mvp_gate": gate,
        "final_full_data_selection": selected.to_dict(),
        "best_research_candidate": best_research_candidate.to_dict(),
        "onnx_deployable_model_families": list(ONNX_DEPLOYABLE_KINDS),
        "final_parameter_tuning": final_tuning,
        "onnx_max_absolute_probability_error": parity_error,
        "v1_reference": {"auprc": 0.13196815490773095, "auroc": 0.5562454718578942},
    }
    (output / "healthpal_stress_v2_metrics.json").write_text(
        json.dumps(json_ready(metrics), indent=2), encoding="utf-8"
    )

    manifest = {
        **source_manifest,
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "python": sys.version,
        "platform": platform.platform(),
        "packages": {
            "numpy": np.__version__,
            "pandas": pd.__version__,
            "scikit_learn": sklearn.__version__,
            "xgboost": xgboost.__version__,
            "onnx": onnx.__version__,
            "onnxruntime": ort.__version__,
        },
        "seed": SEED,
        "feature_specifications": [
            {
                "name": spec.name,
                "experiment": spec.experiment,
                "features": list(spec.features),
                "window_hours": spec.window_hours,
                "requires_exercise_mask": spec.requires_exercise_mask,
                "low_activity_threshold": spec.low_activity_threshold,
            }
            for spec in specs
        ],
    }
    (output / "dataset_manifest.json").write_text(
        json.dumps(json_ready(manifest), indent=2), encoding="utf-8"
    )
    create_report(frame, oof, fold_metrics, final_benchmark, gate, output / "validation_report_v2.png")
    write_model_card(output / "MODEL_CARD_V2.md", metrics, config)

    hashes = {
        path.name: sha256(path)
        for path in sorted(output.iterdir())
        if path.is_file() and path.name != "artifact_checksums.sha256.json"
    }
    (output / "artifact_checksums.sha256.json").write_text(
        json.dumps(hashes, indent=2), encoding="utf-8"
    )
    print(
        json.dumps(
            json_ready(
                {
                    "output_dir": str(output),
                    "nested_selection_oof": pooled,
                    "mvp_gate": gate,
                    "final_config": config,
                    "onnx_parity_error": parity_error,
                }
            ),
            indent=2,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
