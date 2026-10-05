"""Train HealthPal fatigue V5 with parity-safe D-1 sleep-quality features.

V5 changes only the feature set. The target (TIRED), model family (class-balanced
logistic regression), participant-grouped nested validation, calibration and
threshold policy remain fixed. Fitbit proprietary/normalized sleep fields and
SpO2 are deliberately excluded because they cannot be reproduced reliably from
Health Connect records produced by Huawei Health Sync.
"""

from __future__ import annotations

import argparse
import json
import platform
import sys
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
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score

import train_healthpal_stress_v2 as v2
from train_healthpal_stress import json_ready, read_sources, sha256
from train_healthpal_target_benchmark_v3 import attach_target

TARGET = "TIRED"
SEED = 20260929
MODEL_KIND = "logistic"

BASE_FEATURES = (
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

SLEEP_QUALITY_FEATURES = (
    "sleep_session_minutes",
    "sleep_awake_minutes",
    "sleep_onset_minutes",
    "sleep_after_wakeup_minutes",
    "sleep_awake_fraction",
    "sleep_onset_fraction",
    "sleep_after_wakeup_fraction",
)

SPECS = {
    "V4_baseline": v2.FeatureSpec(
        "v4_w6_low_activity_250",
        "baseline",
        BASE_FEATURES,
        6,
        low_activity_threshold=250,
    ),
    "V5_sleep_quality": v2.FeatureSpec(
        "v5_w6_low_activity_250_plus_raw_sleep_quality",
        "parity_safe_sleep_quality",
        BASE_FEATURES + SLEEP_QUALITY_FEATURES,
        6,
        low_activity_threshold=250,
    ),
}

RESEARCH_GATE = {
    "auroc_min": 0.60,
    "auprc_lift_min": 1.25,
    "lowest_fold_auroc_min_exclusive": 0.52,
}
MVP_GATE = {
    "auroc_min": 0.65,
    "auprc_lift_min": 1.50,
    "lowest_fold_auroc_min": 0.55,
}
REPLACEMENT_GATE = {
    "auprc_delta_min": 0.02,
    "auroc_delta_min": 0.01,
    "lowest_fold_auroc_not_worse": True,
}


def attach_sleep_quality(frame: pd.DataFrame, daily: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    """Attach D-1 raw sleep fields and derive device-agnostic ratios."""
    required = {
        "id",
        "date",
        "sleep_duration",
        "minutesAwake",
        "minutesToFallAsleep",
        "minutesAfterWakeup",
    }
    missing = required.difference(daily.columns)
    if missing:
        raise ValueError(f"Missing daily sleep columns: {sorted(missing)}")

    result = frame.copy()
    result["sleep_date"] = result["event_time"].dt.normalize() - pd.Timedelta(days=1)
    lookup = daily[
        [
            "id",
            "date",
            "sleep_duration",
            "minutesAwake",
            "minutesToFallAsleep",
            "minutesAfterWakeup",
        ]
    ].rename(columns={"date": "sleep_date"})
    result = result.merge(lookup, on=["id", "sleep_date"], how="left", validate="many_to_one")

    result["sleep_session_minutes"] = pd.to_numeric(result["sleep_duration"], errors="coerce") / 60000.0
    result["sleep_awake_minutes"] = pd.to_numeric(result["minutesAwake"], errors="coerce")
    result["sleep_onset_minutes"] = pd.to_numeric(result["minutesToFallAsleep"], errors="coerce")
    result["sleep_after_wakeup_minutes"] = pd.to_numeric(result["minutesAfterWakeup"], errors="coerce")
    denominator = result["sleep_minutes"] + result["sleep_awake_minutes"]
    valid_denominator = denominator.where(denominator.gt(0))
    result["sleep_awake_fraction"] = result["sleep_awake_minutes"] / valid_denominator
    result["sleep_onset_fraction"] = result["sleep_onset_minutes"] / valid_denominator
    result["sleep_after_wakeup_fraction"] = result["sleep_after_wakeup_minutes"] / valid_denominator

    invalid = {}
    for feature in SLEEP_QUALITY_FEATURES:
        values = pd.to_numeric(result[feature], errors="coerce")
        invalid[feature] = int((~np.isfinite(values)).sum())
        result[feature] = values
    if any(invalid.values()):
        raise ValueError(f"V5 sleep features are incomplete on the locked cohort: {invalid}")
    if (result[list(SLEEP_QUALITY_FEATURES)] < 0).any().any():
        raise ValueError("Negative sleep-quality feature encountered.")

    audit = {
        "alignment": "previous_calendar_day_D_minus_1",
        "events": int(len(result)),
        "missing_counts": invalid,
        "feature_summary": result[list(SLEEP_QUALITY_FEATURES)].describe().to_dict(),
        "excluded_source_fields": {
            "sleep_efficiency": "Fitbit value was not reproducible from raw duration fields",
            "sleep_deep_ratio/sleep_light_ratio/sleep_rem_ratio/sleep_wake_ratio": "source ratios are normalized Fitbit fields, not raw Health Connect stage fractions",
            "spo2": "not part of user-selected V5 Candidate B",
        },
    }
    return result.drop(
        columns=[
            "sleep_duration",
            "minutesAwake",
            "minutesToFallAsleep",
            "minutesAfterWakeup",
        ]
    ), audit


def evaluate_gates(auprc: float, prevalence: float, auroc: float, lowest_fold_auroc: float) -> dict:
    lift = float(auprc / prevalence)
    research_checks = {
        "auroc": auroc >= RESEARCH_GATE["auroc_min"],
        "auprc_lift": lift >= RESEARCH_GATE["auprc_lift_min"],
        "lowest_fold_auroc": lowest_fold_auroc > RESEARCH_GATE["lowest_fold_auroc_min_exclusive"],
    }
    mvp_checks = {
        "auroc": auroc >= MVP_GATE["auroc_min"],
        "auprc_lift": lift >= MVP_GATE["auprc_lift_min"],
        "lowest_fold_auroc": lowest_fold_auroc >= MVP_GATE["lowest_fold_auroc_min"],
    }
    return {
        "auprc_lift": lift,
        "research": {"passed": bool(all(research_checks.values())), "checks": research_checks, "thresholds": RESEARCH_GATE},
        "user_facing_mvp": {"passed": bool(all(mvp_checks.values())), "checks": mvp_checks, "thresholds": MVP_GATE},
    }


def nested_paired_evaluation(frame: pd.DataFrame) -> dict:
    y = frame["target"].to_numpy(int)
    groups = frame["id"].to_numpy()
    outer_splits = v2.grouped_splits(y, groups, 5, SEED)
    probabilities = {name: np.full(len(frame), np.nan) for name in SPECS}
    predictions = {name: np.full(len(frame), -1, dtype=int) for name in SPECS}
    thresholds = {name: np.full(len(frame), np.nan) for name in SPECS}
    fold_ids = np.full(len(frame), -1, dtype=int)
    fold_rows: list[dict] = []

    for outer_fold, (outer_train, outer_test) in enumerate(outer_splits, start=1):
        print(f"V5 outer fold {outer_fold}/5", flush=True)
        train = frame.iloc[outer_train].reset_index(drop=True)
        test = frame.iloc[outer_test].reset_index(drop=True)
        train_y = train["target"].to_numpy(int)
        test_y = test["target"].to_numpy(int)
        inner_splits = v2.grouped_splits(train_y, train["id"].to_numpy(), 4, SEED + outer_fold)

        for offset, (name, spec) in enumerate(SPECS.items(), start=1):
            parameter, tuning = v2.tune_parameter(
                train, spec, MODEL_KIND, inner_splits, SEED + outer_fold * 100 + offset
            )
            inner = v2.evaluate_candidate(
                train, spec, MODEL_KIND, inner_splits, parameter, SEED + outer_fold * 1000 + offset
            )
            inner_base = v2.grouped_oof_base(
                train, spec, MODEL_KIND, parameter, inner_splits, SEED + outer_fold * 2000 + offset
            )
            calibration = v2.fit_calibrator(train_y, inner_base)
            threshold = v2.choose_threshold(train_y, calibration.apply(inner_base))
            estimator = v2.fit_estimator(
                v2.build_estimator(MODEL_KIND, parameter, SEED + outer_fold),
                MODEL_KIND,
                train[list(spec.features)].to_numpy(float),
                train_y,
            )
            probability = calibration.apply(
                estimator.predict_proba(test[list(spec.features)].to_numpy(float))[:, 1]
            )
            prediction = (probability >= threshold["threshold"]).astype(int)
            metric = v2.classification_metrics(test_y, probability, prediction)
            probabilities[name][outer_test] = probability
            predictions[name][outer_test] = prediction
            thresholds[name][outer_test] = threshold["threshold"]
            fold_rows.append(
                {
                    "fold": outer_fold,
                    "candidate": name,
                    "feature_spec": spec.name,
                    "feature_count": len(spec.features),
                    "model": MODEL_KIND,
                    "parameter": parameter,
                    "inner_mean_auprc": inner["mean_auprc"],
                    "inner_mean_auroc": inner["mean_auroc"],
                    "train_participants": int(train["id"].nunique()),
                    "test_participants": int(test["id"].nunique()),
                    "test_events": int(len(test)),
                    "test_positives": int(test_y.sum()),
                    "calibration_slope": calibration.slope,
                    "calibration_intercept": calibration.intercept,
                    "threshold": threshold["threshold"],
                    "tuning": tuning,
                    **metric,
                }
            )
            print(f"  {name}: AUPRC={metric['auprc']:.3f}; AUROC={metric['auroc']:.3f}", flush=True)
        fold_ids[outer_test] = outer_fold

    if (fold_ids < 0).any() or any(np.isnan(values).any() for values in probabilities.values()):
        raise AssertionError("Nested paired evaluation left unpredicted rows.")
    return {
        "probabilities": probabilities,
        "predictions": predictions,
        "thresholds": thresholds,
        "fold_ids": fold_ids,
        "fold_metrics": pd.DataFrame(fold_rows),
    }


def paired_bootstrap_delta(frame: pd.DataFrame, baseline: np.ndarray, candidate: np.ndarray, replicates: int = 1000) -> dict:
    rng = np.random.default_rng(SEED + 55)
    groups = {key: np.asarray(list(idx), dtype=int) for key, idx in frame.groupby("id").groups.items()}
    participants = np.asarray(list(groups))
    deltas = {"auprc": [], "auroc": [], "brier": []}
    for _ in range(replicates):
        sampled = rng.choice(participants, len(participants), replace=True)
        idx = np.concatenate([groups[item] for item in sampled])
        y = frame.loc[idx, "target"].to_numpy(int)
        if np.unique(y).size < 2:
            continue
        deltas["auprc"].append(average_precision_score(y, candidate[idx]) - average_precision_score(y, baseline[idx]))
        deltas["auroc"].append(roc_auc_score(y, candidate[idx]) - roc_auc_score(y, baseline[idx]))
        deltas["brier"].append(brier_score_loss(y, candidate[idx]) - brier_score_loss(y, baseline[idx]))
    return {
        name: {
            "lower_95": float(np.quantile(values, 0.025)),
            "upper_95": float(np.quantile(values, 0.975)),
        }
        for name, values in deltas.items()
    }


def summarize(frame: pd.DataFrame, nested: dict) -> tuple[dict, pd.DataFrame]:
    y = frame["target"].to_numpy(int)
    prevalence = float(y.mean())
    rows = []
    details = {}
    for name in SPECS:
        pooled = v2.classification_metrics(y, nested["probabilities"][name], nested["predictions"][name])
        folds = nested["fold_metrics"].loc[nested["fold_metrics"]["candidate"].eq(name)]
        lowest = float(folds["auroc"].min())
        gates = evaluate_gates(pooled["auprc"], prevalence, pooled["auroc"], lowest)
        details[name] = {
            "nested_locked_oof": pooled,
            "cluster_bootstrap_95_ci": v2.participant_bootstrap(frame, nested["probabilities"][name]),
            "lowest_fold_auroc": lowest,
            "gates": gates,
            "outer_fold_metrics": folds.to_dict("records"),
        }
        rows.append(
            {
                "candidate": name,
                "feature_count": len(SPECS[name].features),
                "prevalence": prevalence,
                "auprc": pooled["auprc"],
                "auprc_lift": gates["auprc_lift"],
                "auroc": pooled["auroc"],
                "lowest_fold_auroc": lowest,
                "brier": pooled["brier"],
                "research_gate": gates["research"]["passed"],
                "mvp_gate": gates["user_facing_mvp"]["passed"],
            }
        )
    comparison = pd.DataFrame(rows)
    base = comparison.loc[comparison.candidate.eq("V4_baseline")].iloc[0]
    v5_row = comparison.loc[comparison.candidate.eq("V5_sleep_quality")].iloc[0]
    checks = {
        "auprc_delta": float(v5_row.auprc - base.auprc) >= REPLACEMENT_GATE["auprc_delta_min"],
        "auroc_delta": float(v5_row.auroc - base.auroc) >= REPLACEMENT_GATE["auroc_delta_min"],
        "lowest_fold_auroc_not_worse": float(v5_row.lowest_fold_auroc) >= float(base.lowest_fold_auroc),
    }
    replacement = {
        "passed": bool(all(checks.values())),
        "checks": checks,
        "thresholds": REPLACEMENT_GATE,
        "observed": {
            "auprc_delta": float(v5_row.auprc - base.auprc),
            "auroc_delta": float(v5_row.auroc - base.auroc),
            "lowest_fold_auroc_delta": float(v5_row.lowest_fold_auroc - base.lowest_fold_auroc),
        },
        "paired_participant_bootstrap_delta_95_ci": paired_bootstrap_delta(
            frame,
            nested["probabilities"]["V4_baseline"],
            nested["probabilities"]["V5_sleep_quality"],
        ),
    }
    return {
        "dataset": {
            "events": int(len(frame)),
            "positives": int(y.sum()),
            "prevalence": prevalence,
            "participants": int(frame["id"].nunique()),
        },
        "candidates": details,
        "replacement_gate": replacement,
    }, comparison


def create_report(comparison: pd.DataFrame, fold_metrics: pd.DataFrame, output: Path) -> None:
    labels = ["V4 baseline", "V5 sleep"]
    colors = ["#607d8b", "#00695c"]
    x = np.arange(2)
    fig, axes = plt.subplots(2, 2, figsize=(11, 8))
    axes[0, 0].bar(x, comparison.auprc, color=colors)
    axes[0, 0].axhline(comparison.prevalence.iloc[0], color="#777", ls="--", label="Prevalence")
    axes[0, 0].set_xticks(x, labels)
    axes[0, 0].set_title("Nested OOF AUPRC")
    axes[0, 0].legend()
    axes[0, 1].bar(x, comparison.auroc, color=colors)
    axes[0, 1].axhline(RESEARCH_GATE["auroc_min"], color="#ef6c00", ls="--", label="Research gate")
    axes[0, 1].set_xticks(x, labels)
    axes[0, 1].set_title("Nested OOF AUROC")
    axes[0, 1].legend()
    for name, label, color in zip(SPECS, labels, colors):
        rows = fold_metrics.loc[fold_metrics.candidate.eq(name)]
        axes[1, 0].plot(rows.fold, rows.auroc, marker="o", label=label, color=color)
        axes[1, 1].plot(rows.fold, rows.auprc, marker="o", label=label, color=color)
    axes[1, 0].set(title="Outer-fold AUROC", xlabel="Fold", ylabel="AUROC", xticks=range(1, 6))
    axes[1, 1].set(title="Outer-fold AUPRC", xlabel="Fold", ylabel="AUPRC", xticks=range(1, 6))
    axes[1, 0].legend()
    axes[1, 1].legend()
    fig.suptitle("HealthPal fatigue V5 — parity-safe sleep quality")
    fig.tight_layout()
    fig.savefig(output, dpi=170, bbox_inches="tight")
    plt.close(fig)


def write_model_card(path: Path, metrics: dict, comparison: pd.DataFrame, config: dict) -> None:
    base = comparison.loc[comparison.candidate.eq("V4_baseline")].iloc[0]
    row = comparison.loc[comparison.candidate.eq("V5_sleep_quality")].iloc[0]
    decision = "REPLACE V4" if metrics["replacement_gate"]["passed"] else "RETAIN V4"
    path.write_text(
        f"""# HealthPal fatigue V5 — sleep quality

## Decision

**{decision}** as the production recommendation. V5 is exported for reproducibility, but replacement requires all predeclared improvement checks.

| Candidate | AUPRC | Lift | AUROC | Lowest-fold AUROC | Research | MVP |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| V4 baseline | {base.auprc:.3f} | {base.auprc_lift:.2f}× | {base.auroc:.3f} | {base.lowest_fold_auroc:.3f} | {'PASS' if base.research_gate else 'FAIL'} | {'PASS' if base.mvp_gate else 'FAIL'} |
| V5 sleep quality | {row.auprc:.3f} | {row.auprc_lift:.2f}× | {row.auroc:.3f} | {row.lowest_fold_auroc:.3f} | {'PASS' if row.research_gate else 'FAIL'} | {'PASS' if row.mvp_gate else 'FAIL'} |

V5 deltas: AUPRC {row.auprc - base.auprc:+.3f}, AUROC {row.auroc - base.auroc:+.3f}, lowest-fold AUROC {row.lowest_fold_auroc - base.lowest_fold_auroc:+.3f}.

## Scope

Target is self-reported `TIRED`. V5 keeps the V4 6-hour low-activity HR Logistic model and adds only D-1 sleep quantities reproducible from Health Connect: session duration, awake duration, onset latency, post-wakeup duration, and ratios derived from those durations. It excludes Fitbit `sleep_efficiency`, normalized stage ratios and SpO2. It is a research fatigue signal, not a clinical measure.

## Deployment contract

Use the exact feature order in `{config['model_name']}_config.json`. HR/steps use `[T-6h,T)`; sleep and RHR use D-1. Canonicalize one D-1 sleep session before deriving fields. Return `insufficient_data` when required coverage is missing. Apply sigmoid calibration from config to the ONNX base probability, then apply the threshold.
""",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "artifacts" / "healthpal_fatigue_v5_sleep_quality",
    )
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)

    hourly, daily, source_manifest = read_sources(args.data_dir.resolve())
    common, cohort_audit = v2.build_wide_event_dataset(hourly, daily)
    frame = attach_target(common, hourly, TARGET)
    frame, sleep_audit = attach_sleep_quality(frame, daily)
    print(
        f"V5 cohort: {len(frame)} events, {frame.target.sum()} positives, {frame.id.nunique()} participants",
        flush=True,
    )

    nested = nested_paired_evaluation(frame)
    metrics, comparison = summarize(frame, nested)
    comparison.to_csv(output / "v5_vs_v4_locked_comparison.csv", index=False)

    spec = SPECS["V5_sleep_quality"]
    y = frame.target.to_numpy(int)
    full_splits = v2.grouped_splits(y, frame.id.to_numpy(), 5, SEED + 5000)
    parameter, tuning = v2.tune_parameter(frame, spec, MODEL_KIND, full_splits, SEED + 6000)
    base_oof = v2.grouped_oof_base(frame, spec, MODEL_KIND, parameter, full_splits, SEED + 7000)
    calibration = v2.fit_calibrator(y, base_oof)
    threshold = v2.choose_threshold(y, calibration.apply(base_oof))
    x = frame[list(spec.features)].to_numpy(float)
    estimator = v2.fit_estimator(v2.build_estimator(MODEL_KIND, parameter, SEED + 8000), MODEL_KIND, x, y)
    model_path = output / "healthpal_fatigue_v5.onnx"
    parity_error = v2.export_onnx(estimator, MODEL_KIND, len(spec.features), model_path, x[:256])
    if parity_error > 1e-5:
        raise AssertionError(f"ONNX parity failed: {parity_error}")
    joblib.dump(estimator, output / "healthpal_fatigue_v5.joblib")

    recommendation = "replace_v4" if metrics["replacement_gate"]["passed"] else "retain_v4"
    config = {
        "model_name": "healthpal_fatigue_v5",
        "target": TARGET,
        "product_concept": "fatigue_risk",
        "candidate": "B_second_method_parity_safe_raw_sleep",
        "model_family": MODEL_KIND,
        "model_parameter": parameter,
        "feature_order": list(spec.features),
        "primary_window_hours": 6,
        "window_interval": "[T-6h,T)",
        "daily_alignment": "previous_calendar_day_D_minus_1",
        "low_activity_steps_per_hour_threshold": 250,
        "missing_base_data_policy": "return_insufficient_data",
        "deployment_recommendation": recommendation,
        "sleep_feature_contract": {
            "canonical_session": "one deduplicated D-1 sleep session; reject ambiguous duplicates",
            "sleep_session_minutes": "(session_end - session_start) / 60 seconds",
            "sleep_minutes": "sum duration of non-awake sleep stages",
            "sleep_awake_minutes": "sum duration of awake stages",
            "sleep_onset_minutes": "session_start to first non-awake sleep stage",
            "sleep_after_wakeup_minutes": "last non-awake sleep-stage end to session_end",
            "ratio_denominator": "sleep_minutes + sleep_awake_minutes",
            "excluded": ["Fitbit sleep_efficiency", "Fitbit normalized stage ratios", "SpO2"],
        },
        "calibration": {
            "method": "sigmoid_on_logit_probability",
            "slope": calibration.slope,
            "intercept": calibration.intercept,
            "formula": "sigmoid(slope * logit(clamp(base_probability,1e-6,1-1e-6)) + intercept)",
        },
        "decision_threshold": threshold,
        "onnx_output": "uncalibrated_positive_class_probability",
    }
    (output / "healthpal_fatigue_v5_config.json").write_text(
        json.dumps(json_ready(config), indent=2), encoding="utf-8"
    )

    fold_export = nested["fold_metrics"].copy()
    fold_export["parameter"] = fold_export.parameter.apply(lambda value: json.dumps(value, sort_keys=True))
    fold_export["tuning"] = fold_export.tuning.apply(json.dumps)
    fold_export["confusion_matrix"] = fold_export.confusion_matrix.apply(json.dumps)
    fold_export.to_csv(output / "locked_nested_fold_metrics.csv", index=False)
    oof = frame[["id", "event_time", "target"]].copy()
    oof["fold"] = nested["fold_ids"]
    for name in SPECS:
        oof[f"{name}_probability"] = nested["probabilities"][name]
        oof[f"{name}_threshold"] = nested["thresholds"][name]
        oof[f"{name}_prediction"] = nested["predictions"][name]
    oof.to_csv(output / "nested_oof_predictions.csv", index=False)
    frame[["id", "event_time", "target", *spec.features]].to_csv(output / "training_dataset.csv", index=False)

    classifier = estimator.named_steps["classifier"]
    pd.DataFrame(
        {"feature": spec.features, "standardized_logistic_coefficient": classifier.coef_[0]}
    ).sort_values("standardized_logistic_coefficient", key=abs, ascending=False).to_csv(
        output / "model_coefficients.csv", index=False
    )

    metrics.update(
        {
            "target": TARGET,
            "cohort": cohort_audit,
            "sleep_feature_audit": sleep_audit,
            "v5_feature_spec": {"name": spec.name, "features": list(spec.features)},
            "full_data_tuning": tuning,
            "full_data_parameter": parameter,
            "calibration": {"slope": calibration.slope, "intercept": calibration.intercept},
            "deployment_threshold": threshold,
            "onnx_max_absolute_probability_error": parity_error,
            "deployment_recommendation": recommendation,
        }
    )
    (output / "healthpal_fatigue_v5_metrics.json").write_text(
        json.dumps(json_ready(metrics), indent=2), encoding="utf-8"
    )
    create_report(comparison, nested["fold_metrics"], output / "validation_report_v5.png")
    write_model_card(output / "MODEL_CARD_V5.md", metrics, comparison, config)

    manifest = {
        "hourly": source_manifest["hourly"],
        "daily": source_manifest["daily"],
        "v5_target": {
            "label": TARGET,
            "modeling_events": int(len(frame)),
            "modeling_positives": int(frame.target.sum()),
            "modeling_participants": int(frame.id.nunique()),
            "modeling_prevalence": float(frame.target.mean()),
        },
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
    (output / "dataset_manifest.json").write_text(json.dumps(json_ready(manifest), indent=2), encoding="utf-8")
    checksums = {
        path.name: sha256(path)
        for path in sorted(output.iterdir())
        if path.is_file() and path.name != "artifact_checksums.sha256.json"
    }
    (output / "artifact_checksums.sha256.json").write_text(json.dumps(checksums, indent=2), encoding="utf-8")
    print(
        json.dumps(
            json_ready(
                {
                    "output_dir": str(output),
                    "comparison": comparison.to_dict("records"),
                    "replacement_gate": metrics["replacement_gate"],
                    "deployment_recommendation": recommendation,
                    "onnx_parity_error": parity_error,
                }
            ),
            indent=2,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
