"""Train HealthPal fatigue V4 from three predeclared production candidates.

Each candidate receives a locked nested participant-CV evaluation. A separate
nested selection policy prefers the logistic candidate unless XGBoost improves
inner AUPRC and AUROC by predeclared margins with fold-level consistency.
"""

from __future__ import annotations

import argparse
import json
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
import xgboost
from sklearn.metrics import average_precision_score

import train_healthpal_stress_v2 as v2
from train_healthpal_stress import json_ready, read_sources, sha256
from train_healthpal_target_benchmark_v3 import attach_target

TARGET = "TIRED"
SEED = 20260929
XGB_MIN_AUPRC_DELTA = 0.02
XGB_MIN_AUROC_DELTA = 0.01
XGB_MIN_INNER_FOLD_WINS = 3
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


@dataclass(frozen=True)
class Candidate:
    candidate_id: str
    label: str
    feature_spec: str
    model: str


CANDIDATES = (
    Candidate("A", "6h low-activity HR + Logistic", "w6_low_activity_250", "logistic"),
    Candidate("B", "6h robust HR quantiles + XGBoost", "w6_robust_quantiles", "xgboost"),
    Candidate("C", "2h + 6h multiscale robust + XGBoost", "multiscale_2h_6h_robust", "xgboost"),
)


def candidate_specs() -> dict[str, v2.FeatureSpec]:
    available = {spec.name: spec for spec in v2.feature_specs()}
    missing = [candidate.feature_spec for candidate in CANDIDATES if candidate.feature_spec not in available]
    if missing:
        raise ValueError(f"Missing V2 feature specifications: {missing}")
    return {candidate.candidate_id: available[candidate.feature_spec] for candidate in CANDIDATES}


def select_candidate(inner_summaries: list[dict]) -> tuple[str, dict]:
    by_id = {row["candidate_id"]: row for row in inner_summaries}
    logistic = by_id["A"]
    best_xgb = max((by_id["B"], by_id["C"]), key=lambda row: row["mean_auprc"])
    auprc_delta = float(best_xgb["mean_auprc"] - logistic["mean_auprc"])
    auroc_delta = float(best_xgb["mean_auroc"] - logistic["mean_auroc"])
    fold_wins = int(
        np.sum(np.asarray(best_xgb["fold_auprc"]) > np.asarray(logistic["fold_auprc"]))
    )
    xgb_lowest_auroc = float(np.min(best_xgb["fold_auroc"]))
    logistic_lowest_auroc = float(np.min(logistic["fold_auroc"]))
    checks = {
        "auprc_delta": auprc_delta >= XGB_MIN_AUPRC_DELTA,
        "auroc_delta": auroc_delta >= XGB_MIN_AUROC_DELTA,
        "inner_fold_wins": fold_wins >= XGB_MIN_INNER_FOLD_WINS,
        "worst_fold_not_lower": xgb_lowest_auroc >= logistic_lowest_auroc,
    }
    choose_xgb = bool(all(checks.values()))
    selected = best_xgb["candidate_id"] if choose_xgb else "A"
    return selected, {
        "selected_candidate": selected,
        "best_xgboost_candidate": best_xgb["candidate_id"],
        "xgboost_auprc_delta_vs_logistic": auprc_delta,
        "xgboost_auroc_delta_vs_logistic": auroc_delta,
        "xgboost_inner_fold_auprc_wins": fold_wins,
        "xgboost_lowest_inner_fold_auroc": xgb_lowest_auroc,
        "logistic_lowest_inner_fold_auroc": logistic_lowest_auroc,
        "checks": checks,
        "rule": {
            "min_auprc_delta": XGB_MIN_AUPRC_DELTA,
            "min_auroc_delta": XGB_MIN_AUROC_DELTA,
            "min_inner_fold_auprc_wins": XGB_MIN_INNER_FOLD_WINS,
            "require_worst_fold_not_lower": True,
        },
    }


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
        "research": {
            "passed": bool(all(research_checks.values())),
            "checks": research_checks,
            "thresholds": RESEARCH_GATE,
        },
        "user_facing_mvp": {
            "passed": bool(all(mvp_checks.values())),
            "checks": mvp_checks,
            "thresholds": MVP_GATE,
        },
    }


def nested_three_candidate_evaluation(frame: pd.DataFrame, specs: dict[str, v2.FeatureSpec]):
    y = frame["target"].to_numpy(int)
    groups = frame["id"].to_numpy()
    outer_splits = v2.grouped_splits(y, groups, 5, SEED)
    locked_probabilities = {candidate.candidate_id: np.full(len(frame), np.nan) for candidate in CANDIDATES}
    locked_predictions = {candidate.candidate_id: np.full(len(frame), -1, dtype=int) for candidate in CANDIDATES}
    locked_thresholds = {candidate.candidate_id: np.full(len(frame), np.nan) for candidate in CANDIDATES}
    adaptive_probabilities = np.full(len(frame), np.nan)
    adaptive_predictions = np.full(len(frame), -1, dtype=int)
    adaptive_thresholds = np.full(len(frame), np.nan)
    fold_ids = np.full(len(frame), -1, dtype=int)
    locked_fold_rows: list[dict] = []
    selection_rows: list[dict] = []

    for outer_fold, (outer_train, outer_test) in enumerate(outer_splits, start=1):
        print(f"V4 outer fold {outer_fold}/5", flush=True)
        train_frame = frame.iloc[outer_train].reset_index(drop=True)
        test_frame = frame.iloc[outer_test].reset_index(drop=True)
        train_y = train_frame["target"].to_numpy(int)
        test_y = test_frame["target"].to_numpy(int)
        train_groups = train_frame["id"].to_numpy()
        inner_splits = v2.grouped_splits(train_y, train_groups, 4, SEED + outer_fold)
        inner_summaries: list[dict] = []
        outer_outputs: dict[str, dict] = {}

        for candidate in CANDIDATES:
            spec = specs[candidate.candidate_id]
            parameter, tuning = v2.tune_parameter(
                train_frame,
                spec,
                candidate.model,
                inner_splits,
                SEED + outer_fold * 100 + ord(candidate.candidate_id),
            )
            inner_summary = v2.evaluate_candidate(
                train_frame,
                spec,
                candidate.model,
                inner_splits,
                parameter,
                SEED + outer_fold * 1000 + ord(candidate.candidate_id),
            )
            inner_summary.update(
                {
                    "candidate_id": candidate.candidate_id,
                    "candidate_label": candidate.label,
                    "parameter": parameter,
                    "tuning": tuning,
                }
            )
            inner_summaries.append(inner_summary)
            inner_base = v2.grouped_oof_base(
                train_frame,
                spec,
                candidate.model,
                parameter,
                inner_splits,
                SEED + outer_fold * 2000 + ord(candidate.candidate_id),
            )
            calibration = v2.fit_calibrator(train_y, inner_base)
            threshold_info = v2.choose_threshold(train_y, calibration.apply(inner_base))
            x_train = train_frame[list(spec.features)].to_numpy(float)
            x_test = test_frame[list(spec.features)].to_numpy(float)
            estimator = v2.fit_estimator(
                v2.build_estimator(candidate.model, parameter, SEED + outer_fold),
                candidate.model,
                x_train,
                train_y,
            )
            probability = calibration.apply(estimator.predict_proba(x_test)[:, 1])
            prediction = (probability >= threshold_info["threshold"]).astype(int)
            metric = v2.classification_metrics(test_y, probability, prediction)
            locked_probabilities[candidate.candidate_id][outer_test] = probability
            locked_predictions[candidate.candidate_id][outer_test] = prediction
            locked_thresholds[candidate.candidate_id][outer_test] = threshold_info["threshold"]
            outer_outputs[candidate.candidate_id] = {
                "probability": probability,
                "prediction": prediction,
                "threshold": threshold_info["threshold"],
            }
            locked_fold_rows.append(
                {
                    "fold": outer_fold,
                    "candidate_id": candidate.candidate_id,
                    "candidate_label": candidate.label,
                    "feature_spec": candidate.feature_spec,
                    "model": candidate.model,
                    "parameter": parameter,
                    "inner_mean_auprc": inner_summary["mean_auprc"],
                    "inner_mean_auroc": inner_summary["mean_auroc"],
                    "test_events": int(len(test_y)),
                    "test_positives": int(test_y.sum()),
                    "calibration_slope": calibration.slope,
                    "calibration_intercept": calibration.intercept,
                    "threshold": threshold_info["threshold"],
                    **metric,
                }
            )

        selected_id, decision = select_candidate(inner_summaries)
        selected_output = outer_outputs[selected_id]
        adaptive_probabilities[outer_test] = selected_output["probability"]
        adaptive_predictions[outer_test] = selected_output["prediction"]
        adaptive_thresholds[outer_test] = selected_output["threshold"]
        fold_ids[outer_test] = outer_fold
        adaptive_metric = v2.classification_metrics(
            test_y, selected_output["probability"], selected_output["prediction"]
        )
        selection_rows.append(
            {
                "fold": outer_fold,
                "selected_candidate": selected_id,
                "selected_label": next(c.label for c in CANDIDATES if c.candidate_id == selected_id),
                "decision": decision,
                **adaptive_metric,
            }
        )
        print(
            f"  selected={selected_id}; adaptive outer AUPRC={adaptive_metric['auprc']:.3f}; AUROC={adaptive_metric['auroc']:.3f}",
            flush=True,
        )

    arrays = [adaptive_probabilities, *locked_probabilities.values()]
    if any(np.isnan(values).any() for values in arrays) or (fold_ids < 0).any():
        raise AssertionError("V4 nested evaluation left unpredicted rows.")
    return {
        "locked_probabilities": locked_probabilities,
        "locked_predictions": locked_predictions,
        "locked_thresholds": locked_thresholds,
        "adaptive_probabilities": adaptive_probabilities,
        "adaptive_predictions": adaptive_predictions,
        "adaptive_thresholds": adaptive_thresholds,
        "fold_ids": fold_ids,
        "locked_fold_metrics": pd.DataFrame(locked_fold_rows),
        "selection_fold_metrics": pd.DataFrame(selection_rows),
    }


def summarize_nested(frame: pd.DataFrame, nested: dict) -> tuple[dict, pd.DataFrame]:
    y = frame["target"].to_numpy(int)
    prevalence = float(y.mean())
    fold_metrics = nested["locked_fold_metrics"]
    candidate_results = {}
    rows = []
    for candidate in CANDIDATES:
        candidate_id = candidate.candidate_id
        probabilities = nested["locked_probabilities"][candidate_id]
        predictions = nested["locked_predictions"][candidate_id]
        pooled = v2.classification_metrics(y, probabilities, predictions)
        bootstrap = v2.participant_bootstrap(frame, probabilities)
        candidate_folds = fold_metrics.loc[fold_metrics["candidate_id"].eq(candidate_id)]
        lowest_fold_auroc = float(candidate_folds["auroc"].min())
        gates = evaluate_gates(pooled["auprc"], prevalence, pooled["auroc"], lowest_fold_auroc)
        candidate_results[candidate_id] = {
            "candidate": candidate.__dict__,
            "nested_locked_oof": pooled,
            "cluster_bootstrap_95_ci": bootstrap,
            "lowest_fold_auroc": lowest_fold_auroc,
            "gates": gates,
            "outer_fold_metrics": candidate_folds.to_dict("records"),
        }
        rows.append(
            {
                "candidate_id": candidate_id,
                "candidate_label": candidate.label,
                "model": candidate.model,
                "feature_spec": candidate.feature_spec,
                "prevalence": prevalence,
                "auprc": pooled["auprc"],
                "auprc_lift": gates["auprc_lift"],
                "auroc": pooled["auroc"],
                "lowest_fold_auroc": lowest_fold_auroc,
                "brier": pooled["brier"],
                "precision": pooled["precision"],
                "recall": pooled["recall"],
                "f1": pooled["f1"],
                "research_gate": gates["research"]["passed"],
                "mvp_gate": gates["user_facing_mvp"]["passed"],
            }
        )

    adaptive_pooled = v2.classification_metrics(
        y, nested["adaptive_probabilities"], nested["adaptive_predictions"]
    )
    adaptive_bootstrap = v2.participant_bootstrap(frame, nested["adaptive_probabilities"])
    selection_folds = nested["selection_fold_metrics"]
    adaptive_lowest = float(selection_folds["auroc"].min())
    adaptive_gates = evaluate_gates(
        adaptive_pooled["auprc"], prevalence, adaptive_pooled["auroc"], adaptive_lowest
    )
    summary = {
        "dataset": {
            "events": int(len(frame)),
            "positives": int(y.sum()),
            "prevalence": prevalence,
            "participants": int(frame["id"].nunique()),
            "participants_with_positive": int(frame.loc[frame["target"].eq(1), "id"].nunique()),
        },
        "locked_candidates": candidate_results,
        "nested_selection_policy": {
            "oof_metrics": adaptive_pooled,
            "cluster_bootstrap_95_ci": adaptive_bootstrap,
            "lowest_fold_auroc": adaptive_lowest,
            "gates": adaptive_gates,
            "outer_fold_metrics": selection_folds.to_dict("records"),
            "selection_frequency": selection_folds["selected_candidate"].value_counts().to_dict(),
        },
    }
    return summary, pd.DataFrame(rows)


def final_model_selection(frame: pd.DataFrame, specs: dict[str, v2.FeatureSpec]) -> tuple[Candidate, dict, list[dict], dict]:
    y = frame["target"].to_numpy(int)
    groups = frame["id"].to_numpy()
    splits = v2.grouped_splits(y, groups, 5, SEED + 5000)
    summaries = []
    tuning_by_candidate = {}
    for candidate in CANDIDATES:
        spec = specs[candidate.candidate_id]
        parameter, tuning = v2.tune_parameter(
            frame, spec, candidate.model, splits, SEED + 6000 + ord(candidate.candidate_id)
        )
        summary = v2.evaluate_candidate(
            frame,
            spec,
            candidate.model,
            splits,
            parameter,
            SEED + 7000 + ord(candidate.candidate_id),
        )
        summary.update(
            {
                "candidate_id": candidate.candidate_id,
                "candidate_label": candidate.label,
                "parameter": parameter,
            }
        )
        summaries.append(summary)
        tuning_by_candidate[candidate.candidate_id] = tuning
    selected_id, decision = select_candidate(summaries)
    selected_candidate = next(candidate for candidate in CANDIDATES if candidate.candidate_id == selected_id)
    selected_summary = next(row for row in summaries if row["candidate_id"] == selected_id)
    return selected_candidate, selected_summary, summaries, {
        "decision": decision,
        "tuning": tuning_by_candidate,
        "splits": splits,
    }


def create_report(comparison: pd.DataFrame, metrics: dict, output_path: Path) -> None:
    labels = comparison["candidate_id"].tolist()
    x = np.arange(len(labels))
    prevalence = float(comparison["prevalence"].iloc[0])
    fig, axes = plt.subplots(2, 2, figsize=(11.5, 8.5))
    colors = ["#00695c", "#1565c0", "#7b1fa2"]
    axes[0, 0].bar(x, comparison["auprc"], color=colors)
    axes[0, 0].axhline(prevalence, color="#777", ls="--", label=f"Prevalence {prevalence:.3f}")
    axes[0, 0].axhline(prevalence * MVP_GATE["auprc_lift_min"], color="#c62828", ls=":", label="MVP lift gate")
    axes[0, 0].set_xticks(x, labels)
    axes[0, 0].set(title="Locked nested OOF AUPRC", ylabel="AUPRC")
    axes[0, 0].legend()

    axes[0, 1].bar(x, comparison["auprc_lift"], color=colors)
    axes[0, 1].axhline(RESEARCH_GATE["auprc_lift_min"], color="#ef6c00", ls="--", label="Research gate")
    axes[0, 1].axhline(MVP_GATE["auprc_lift_min"], color="#c62828", ls=":", label="MVP gate")
    axes[0, 1].set_xticks(x, labels)
    axes[0, 1].set(title="AUPRC lift over prevalence", ylabel="Lift (×)")
    axes[0, 1].legend()

    for index, candidate in enumerate(CANDIDATES):
        candidate_metrics = metrics["locked_candidates"][candidate.candidate_id]
        ci = candidate_metrics["cluster_bootstrap_95_ci"]["auroc"]
        value = candidate_metrics["nested_locked_oof"]["auroc"]
        axes[1, 0].errorbar(
            index,
            value,
            yerr=[[value - ci["lower_95"]], [ci["upper_95"] - value]],
            fmt="o",
            capsize=5,
            color=colors[index],
        )
    axes[1, 0].axhline(RESEARCH_GATE["auroc_min"], color="#ef6c00", ls="--", label="Research gate")
    axes[1, 0].axhline(MVP_GATE["auroc_min"], color="#c62828", ls=":", label="MVP gate")
    axes[1, 0].set_xticks(x, labels)
    axes[1, 0].set_ylim(0.45, 0.72)
    axes[1, 0].set(title="AUROC with participant-cluster 95% CI", ylabel="AUROC")
    axes[1, 0].legend()

    for candidate, color in zip(CANDIDATES, colors):
        folds = pd.DataFrame(metrics["locked_candidates"][candidate.candidate_id]["outer_fold_metrics"])
        axes[1, 1].plot(folds["fold"], folds["auroc"], marker="o", color=color, label=candidate.candidate_id)
    axes[1, 1].axhline(RESEARCH_GATE["lowest_fold_auroc_min_exclusive"], color="#ef6c00", ls="--")
    axes[1, 1].axhline(MVP_GATE["lowest_fold_auroc_min"], color="#c62828", ls=":")
    axes[1, 1].set_xticks(range(1, 6))
    axes[1, 1].set(title="Locked outer-fold AUROC", xlabel="Fold", ylabel="AUROC")
    axes[1, 1].legend(title="Candidate")
    fig.suptitle("HealthPal fatigue V4 validation", fontsize=15)
    fig.tight_layout()
    fig.savefig(output_path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def write_model_card(path: Path, metrics: dict, comparison: pd.DataFrame, config: dict) -> None:
    selected = config["candidate_id"]
    selected_row = comparison.loc[comparison["candidate_id"].eq(selected)].iloc[0]
    selected_metrics = metrics["locked_candidates"][selected]
    ci = selected_metrics["cluster_bootstrap_95_ci"]
    path.write_text(
        f"""# HealthPal fatigue V4

## Decision

Production candidate: **{selected} — {config['candidate_label']}**.

- Research gate: **{'PASS' if selected_row['research_gate'] else 'FAIL'}**
- User-facing MVP gate: **{'PASS' if selected_row['mvp_gate'] else 'FAIL'}**

The model remains a self-reported fatigue research signal, not a clinical measure. User-facing use is permitted only if the MVP gate passes and a prospective Health Connect pilot confirms performance.

## Locked nested participant-CV comparison

| Candidate | AUPRC | Lift | AUROC | Lowest-fold AUROC | Research | MVP |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| A | {comparison.loc[comparison.candidate_id.eq('A'), 'auprc'].iloc[0]:.3f} | {comparison.loc[comparison.candidate_id.eq('A'), 'auprc_lift'].iloc[0]:.2f}× | {comparison.loc[comparison.candidate_id.eq('A'), 'auroc'].iloc[0]:.3f} | {comparison.loc[comparison.candidate_id.eq('A'), 'lowest_fold_auroc'].iloc[0]:.3f} | {'PASS' if comparison.loc[comparison.candidate_id.eq('A'), 'research_gate'].iloc[0] else 'FAIL'} | {'PASS' if comparison.loc[comparison.candidate_id.eq('A'), 'mvp_gate'].iloc[0] else 'FAIL'} |
| B | {comparison.loc[comparison.candidate_id.eq('B'), 'auprc'].iloc[0]:.3f} | {comparison.loc[comparison.candidate_id.eq('B'), 'auprc_lift'].iloc[0]:.2f}× | {comparison.loc[comparison.candidate_id.eq('B'), 'auroc'].iloc[0]:.3f} | {comparison.loc[comparison.candidate_id.eq('B'), 'lowest_fold_auroc'].iloc[0]:.3f} | {'PASS' if comparison.loc[comparison.candidate_id.eq('B'), 'research_gate'].iloc[0] else 'FAIL'} | {'PASS' if comparison.loc[comparison.candidate_id.eq('B'), 'mvp_gate'].iloc[0] else 'FAIL'} |
| C | {comparison.loc[comparison.candidate_id.eq('C'), 'auprc'].iloc[0]:.3f} | {comparison.loc[comparison.candidate_id.eq('C'), 'auprc_lift'].iloc[0]:.2f}× | {comparison.loc[comparison.candidate_id.eq('C'), 'auroc'].iloc[0]:.3f} | {comparison.loc[comparison.candidate_id.eq('C'), 'lowest_fold_auroc'].iloc[0]:.3f} | {'PASS' if comparison.loc[comparison.candidate_id.eq('C'), 'research_gate'].iloc[0] else 'FAIL'} | {'PASS' if comparison.loc[comparison.candidate_id.eq('C'), 'mvp_gate'].iloc[0] else 'FAIL'} |

Selected-candidate AUPRC 95% CI: {ci['auprc']['lower_95']:.3f}–{ci['auprc']['upper_95']:.3f}. AUROC 95% CI: {ci['auroc']['lower_95']:.3f}–{ci['auroc']['upper_95']:.3f}.

## Selection policy

Candidate A is preferred unless the best XGBoost candidate improves inner AUPRC by at least {XGB_MIN_AUPRC_DELTA:.2f}, inner AUROC by at least {XGB_MIN_AUROC_DELTA:.2f}, wins at least {XGB_MIN_INNER_FOLD_WINS}/4 AUPRC folds, and does not lower worst-fold AUROC. These rules were fixed before outer evaluation.

The final artifact uses `{config['feature_spec']}` with `{config['model_family']}`. Inputs follow the config's exact feature order; windows are `[T-window,T)`, daily sleep/RHR comes from D-1, and missing base coverage returns `insufficient_data`. Apply config calibration after ONNX inference, then the deployment threshold.
""",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent / "artifacts" / "healthpal_fatigue_v4")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)

    hourly, daily, source_manifest = read_sources(args.data_dir.resolve())
    tense_frame, cohort_audit = v2.build_wide_event_dataset(hourly, daily)
    frame = attach_target(tense_frame, hourly, TARGET)
    specs = candidate_specs()
    print(
        f"V4 cohort: {len(frame)} events, {frame['target'].sum()} positives, {frame['id'].nunique()} participants",
        flush=True,
    )
    nested = nested_three_candidate_evaluation(frame, specs)
    metrics, comparison = summarize_nested(frame, nested)
    comparison.to_csv(output / "locked_candidate_comparison.csv", index=False)

    selected_candidate, selected_summary, full_summaries, full_selection = final_model_selection(frame, specs)
    selected_spec = specs[selected_candidate.candidate_id]
    selected_parameter = selected_summary["parameter"]
    y = frame["target"].to_numpy(int)
    splits = full_selection.pop("splits")
    base_oof = v2.grouped_oof_base(
        frame,
        selected_spec,
        selected_candidate.model,
        selected_parameter,
        splits,
        SEED + 8000,
    )
    calibration = v2.fit_calibrator(y, base_oof)
    threshold = v2.choose_threshold(y, calibration.apply(base_oof))
    x = frame[list(selected_spec.features)].to_numpy(float)
    estimator = v2.fit_estimator(
        v2.build_estimator(selected_candidate.model, selected_parameter, SEED + 9000),
        selected_candidate.model,
        x,
        y,
    )
    model_path = output / "healthpal_fatigue_v4.onnx"
    parity_error = v2.export_onnx(
        estimator, selected_candidate.model, len(selected_spec.features), model_path, x[:256]
    )
    if parity_error > 1e-5:
        raise AssertionError(f"ONNX parity failed: {parity_error}")
    joblib.dump(estimator, output / "healthpal_fatigue_v4.joblib")
    if selected_candidate.model == "xgboost":
        estimator.save_model(output / "healthpal_fatigue_v4_xgboost.json")

    config = {
        "model_name": "healthpal_fatigue_v4",
        "target": TARGET,
        "product_concept": "fatigue_risk",
        "candidate_id": selected_candidate.candidate_id,
        "candidate_label": selected_candidate.label,
        "feature_spec": selected_spec.name,
        "model_family": selected_candidate.model,
        "model_parameter": selected_parameter,
        "feature_order": list(selected_spec.features),
        "primary_window_hours": selected_spec.window_hours,
        "window_interval": "[T-window,T)",
        "daily_alignment": "previous_calendar_day_D_minus_1",
        "minimum_hourly_coverage": {str(window): int(np.ceil(window / 2)) for window in v2.WINDOWS},
        "low_activity_steps_per_hour_threshold": selected_spec.low_activity_threshold,
        "requires_binary_exercise_session_mask": selected_spec.requires_exercise_mask,
        "missing_base_data_policy": "return_insufficient_data",
        "calibration": {
            "method": "sigmoid_on_logit_probability",
            "slope": calibration.slope,
            "intercept": calibration.intercept,
            "formula": "sigmoid(slope * logit(clamp(base_probability,1e-6,1-1e-6)) + intercept)",
        },
        "decision_threshold": threshold,
        "onnx_output": "uncalibrated_positive_class_probability",
    }
    (output / "healthpal_fatigue_v4_config.json").write_text(
        json.dumps(json_ready(config), indent=2), encoding="utf-8"
    )

    locked_export = nested["locked_fold_metrics"].copy()
    locked_export["parameter"] = locked_export["parameter"].apply(lambda value: json.dumps(value, sort_keys=True))
    locked_export["confusion_matrix"] = locked_export["confusion_matrix"].apply(json.dumps)
    locked_export.to_csv(output / "locked_nested_fold_metrics.csv", index=False)
    selection_export = nested["selection_fold_metrics"].copy()
    selection_export["decision"] = selection_export["decision"].apply(json.dumps)
    selection_export["confusion_matrix"] = selection_export["confusion_matrix"].apply(json.dumps)
    selection_export.to_csv(output / "selection_policy_fold_metrics.csv", index=False)
    oof = frame[["id", "event_time", "target"]].copy()
    oof["fold"] = nested["fold_ids"]
    for candidate in CANDIDATES:
        candidate_id = candidate.candidate_id
        oof[f"candidate_{candidate_id}_probability"] = nested["locked_probabilities"][candidate_id]
        oof[f"candidate_{candidate_id}_threshold"] = nested["locked_thresholds"][candidate_id]
        oof[f"candidate_{candidate_id}_prediction"] = nested["locked_predictions"][candidate_id]
    oof["selection_policy_probability"] = nested["adaptive_probabilities"]
    oof["selection_policy_threshold"] = nested["adaptive_thresholds"]
    oof["selection_policy_prediction"] = nested["adaptive_predictions"]
    oof.to_csv(output / "nested_oof_predictions.csv", index=False)
    frame[["id", "event_time", "target", *selected_spec.features]].to_csv(
        output / "training_dataset.csv", index=False
    )

    selected_locked = metrics["locked_candidates"][selected_candidate.candidate_id]
    metrics.update(
        {
            "target": TARGET,
            "cohort": cohort_audit,
            "predeclared_candidates": [candidate.__dict__ for candidate in CANDIDATES],
            "predeclared_selection_rule": full_selection["decision"]["rule"],
            "full_data_candidate_summaries": full_summaries,
            "full_data_selection": {
                "candidate": selected_candidate.__dict__,
                "summary": selected_summary,
                **full_selection,
            },
            "production_candidate_locked_nested_oof": selected_locked,
            "onnx_max_absolute_probability_error": parity_error,
            "deployment_threshold": threshold,
        }
    )
    (output / "healthpal_fatigue_v4_metrics.json").write_text(
        json.dumps(json_ready(metrics), indent=2), encoding="utf-8"
    )
    create_report(comparison, metrics, output / "validation_report_v4.png")
    write_model_card(output / "MODEL_CARD_V4.md", metrics, comparison, config)

    manifest = {
        "hourly": source_manifest["hourly"],
        "daily": source_manifest["daily"],
        "source_snapshot_contract": {
            "label": "TENSE/ANXIOUS",
            "labelled_events_raw": source_manifest["labelled_events_raw"],
            "positives_raw": source_manifest["positives_raw"],
            "purpose": "Input snapshot validation inherited from the V1 loader; not the V4 target prevalence.",
        },
        "v4_target": {
            "label": TARGET,
            "labelled_events_raw": int(hourly[TARGET].notna().sum()),
            "positives_raw": int(hourly.loc[hourly[TARGET].notna(), TARGET].sum()),
            "participants_raw": int(hourly.loc[hourly[TARGET].notna(), "id"].nunique()),
            "modeling_events": int(len(frame)),
            "modeling_positives": int(frame["target"].sum()),
            "modeling_participants": int(frame["id"].nunique()),
            "modeling_prevalence": float(frame["target"].mean()),
        },
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
    }
    (output / "dataset_manifest.json").write_text(
        json.dumps(json_ready(manifest), indent=2), encoding="utf-8"
    )
    checksums = {
        path.name: sha256(path)
        for path in sorted(output.iterdir())
        if path.is_file() and path.name != "artifact_checksums.sha256.json"
    }
    (output / "artifact_checksums.sha256.json").write_text(
        json.dumps(checksums, indent=2), encoding="utf-8"
    )
    print(
        json.dumps(
            json_ready(
                {
                    "output_dir": str(output),
                    "candidate_comparison": comparison.to_dict("records"),
                    "selection_policy": metrics["nested_selection_policy"],
                    "production_candidate": selected_candidate.__dict__,
                    "config": config,
                    "onnx_parity_error": parity_error,
                }
            ),
            indent=2,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
