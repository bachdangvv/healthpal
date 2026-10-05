"""V3 target benchmark: stress vs fatigue vs recovery.

The V2 feature/model candidate matrix and nested participant-CV procedure are
unchanged. Only the binary target column changes. The existing V2 TENSE/ANXIOUS
run is reused after strict cohort/protocol checks; TIRED and RESTED/RELAXED are
evaluated anew. Only the winning target receives a new deployment artifact.
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
import xgboost

import train_healthpal_stress_v2 as v2
from train_healthpal_stress import json_ready, read_sources, sha256

TARGETS = ("TENSE/ANXIOUS", "TIRED", "RESTED/RELAXED")
TARGET_SLUGS = {
    "TENSE/ANXIOUS": "tense_anxious",
    "TIRED": "tired",
    "RESTED/RELAXED": "rested_relaxed",
}
PRODUCT_CONCEPTS = {
    "TENSE/ANXIOUS": "stress_risk",
    "TIRED": "fatigue_risk",
    "RESTED/RELAXED": "recovery_likelihood",
}
LIFT_HYPOTHESES = {
    "TENSE/ANXIOUS": 1.15,
    "TIRED": 2.00,
    "RESTED/RELAXED": 2.20,
}


def attach_target(common_frame: pd.DataFrame, hourly: pd.DataFrame, target: str) -> pd.DataFrame:
    if target not in hourly.columns:
        raise ValueError(f"Missing target column: {target}")
    lookup = hourly.loc[hourly[target].notna(), ["id", "timestamp", target]].copy()
    lookup = lookup.rename(columns={"timestamp": "event_time"})
    if lookup.duplicated(["id", "event_time"]).any():
        raise ValueError(f"Duplicated labelled keys for {target}")
    result = common_frame.drop(columns=["target"]).merge(
        lookup, on=["id", "event_time"], how="left", validate="one_to_one"
    )
    if result[target].isna().any():
        raise ValueError(f"The common cohort has missing labels for {target}")
    values = set(result[target].astype(int).unique())
    if not values.issubset({0, 1}):
        raise ValueError(f"Target {target} is not binary: {values}")
    return result.rename(columns={target: "target"}).sort_values(["id", "event_time"]).reset_index(drop=True)


def save_nested_outputs(
    target_dir: Path,
    frame: pd.DataFrame,
    oof: np.ndarray,
    predictions: np.ndarray,
    thresholds: np.ndarray,
    fold_ids: np.ndarray,
    fold_metrics: pd.DataFrame,
    inner_benchmarks: pd.DataFrame,
) -> None:
    target_dir.mkdir(parents=True, exist_ok=True)
    fold_export = fold_metrics.drop(columns=["tuning"]).copy()
    fold_export["parameter"] = fold_export["parameter"].apply(lambda value: json.dumps(value, sort_keys=True))
    fold_export.to_csv(target_dir / "nested_selection_fold_metrics.csv", index=False)
    inner_export = inner_benchmarks.copy()
    inner_export["fold_auprc"] = inner_export["fold_auprc"].apply(json.dumps)
    inner_export["fold_auroc"] = inner_export["fold_auroc"].apply(json.dumps)
    inner_export.to_csv(target_dir / "inner_candidate_benchmarks.csv", index=False)
    oof_frame = frame[["id", "event_time", "target"]].copy()
    oof_frame["fold"] = fold_ids
    oof_frame["calibrated_probability"] = oof
    oof_frame["fold_threshold"] = thresholds
    oof_frame["prediction"] = predictions
    oof_frame.to_csv(target_dir / "nested_selection_oof_predictions.csv", index=False)


def run_nested_target(
    target: str,
    frame: pd.DataFrame,
    specs: list[v2.FeatureSpec],
    output: Path,
) -> dict:
    print(f"V3 target {target}: nested selection", flush=True)
    oof, predictions, thresholds, fold_ids, fold_metrics, inner_benchmarks = v2.nested_selection_evaluation(
        frame, specs
    )
    y = frame["target"].to_numpy(int)
    pooled = v2.classification_metrics(y, oof, predictions)
    bootstrap = v2.participant_bootstrap(frame, oof)
    gate = v2.evaluate_gate(pooled, fold_metrics, bootstrap)
    target_dir = output / "targets" / TARGET_SLUGS[target]
    save_nested_outputs(
        target_dir,
        frame,
        oof,
        predictions,
        thresholds,
        fold_ids,
        fold_metrics,
        inner_benchmarks,
    )
    result = {
        "target": target,
        "source": "v3_fresh_nested_run",
        "events": int(len(frame)),
        "positives": int(y.sum()),
        "prevalence": float(y.mean()),
        "participants": int(frame["id"].nunique()),
        "participants_with_positive": int(frame.loc[frame["target"].eq(1), "id"].nunique()),
        "nested_selection_oof": pooled,
        "auprc_lift_over_prevalence": float(pooled["auprc"] / y.mean()),
        "lift_hypothesis": LIFT_HYPOTHESES[target],
        "lift_hypothesis_met": bool(pooled["auprc"] / y.mean() >= LIFT_HYPOTHESES[target]),
        "cluster_bootstrap_95_ci": bootstrap,
        "lowest_fold_auroc": float(fold_metrics["auroc"].min()),
        "outer_fold_metrics": fold_metrics.to_dict("records"),
        "outer_selection_frequency": fold_metrics.groupby(["feature_spec", "model"]).size().to_dict(),
        "v2_mvp_gate": gate,
    }
    (target_dir / "target_metrics.json").write_text(
        json.dumps(json_ready(result), indent=2), encoding="utf-8"
    )
    return result


def load_v2_tense_result(v2_dir: Path, frame: pd.DataFrame) -> dict:
    metrics_path = v2_dir / "healthpal_stress_v2_metrics.json"
    fold_path = v2_dir / "nested_selection_fold_metrics.csv"
    oof_path = v2_dir / "nested_selection_oof_predictions.csv"
    if not metrics_path.exists() or not fold_path.exists() or not oof_path.exists():
        raise FileNotFoundError("V2 TENSE artifacts are required for exact reuse.")
    metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
    folds = pd.read_csv(fold_path)
    oof = pd.read_csv(oof_path)
    expected_keys = frame[["id", "event_time"]].copy()
    expected_keys["event_time"] = expected_keys["event_time"].astype(str)
    actual_keys = oof[["id", "event_time"]].copy()
    actual_keys["event_time"] = actual_keys["event_time"].astype(str)
    if len(frame) != metrics["dataset"]["events"] or not expected_keys.equals(actual_keys):
        raise ValueError("V2 TENSE artifact cohort does not match the V3 common cohort.")
    prevalence = float(metrics["dataset"]["prevalence"])
    pooled = metrics["nested_selection_oof"]
    result = {
        "target": "TENSE/ANXIOUS",
        "source": "reused_exact_v2_nested_run",
        "events": int(metrics["dataset"]["events"]),
        "positives": int(metrics["dataset"]["positives"]),
        "prevalence": prevalence,
        "participants": int(metrics["dataset"]["participants"]),
        "participants_with_positive": int(metrics["dataset"]["participants_with_positive"]),
        "nested_selection_oof": pooled,
        "auprc_lift_over_prevalence": float(pooled["auprc"] / prevalence),
        "lift_hypothesis": LIFT_HYPOTHESES["TENSE/ANXIOUS"],
        "lift_hypothesis_met": bool(pooled["auprc"] / prevalence >= LIFT_HYPOTHESES["TENSE/ANXIOUS"]),
        "cluster_bootstrap_95_ci": metrics["cluster_bootstrap_95_ci"],
        "lowest_fold_auroc": float(folds["auroc"].min()),
        "outer_fold_metrics": folds.to_dict("records"),
        "outer_selection_frequency": metrics["outer_selection_frequency"],
        "v2_mvp_gate": metrics["mvp_gate"],
        "artifact_reference": str(v2_dir.resolve()),
    }
    return result


def train_winner(
    target: str,
    frame: pd.DataFrame,
    specs: list[v2.FeatureSpec],
    output: Path,
) -> dict:
    print(f"V3 winning target {target}: final full-data model selection", flush=True)
    y = frame["target"].to_numpy(int)
    groups = frame["id"].to_numpy()
    splits = v2.grouped_splits(y, groups, 5, v2.SEED + 5000)
    benchmark = v2.benchmark_candidates(frame, specs, splits, v2.SEED + 6000)
    research_best = benchmark.iloc[0]
    deployable = benchmark.loc[benchmark["model"].isin(v2.ONNX_DEPLOYABLE_KINDS)]
    selected = v2.one_se_select(deployable)
    spec = next(item for item in specs if item.name == selected["feature_spec"])
    kind = str(selected["model"])
    parameter, tuning = v2.tune_parameter(frame, spec, kind, splits, v2.SEED + 7000)
    base_oof = v2.grouped_oof_base(frame, spec, kind, parameter, splits, v2.SEED + 8000)
    calibration = v2.fit_calibrator(y, base_oof)
    threshold = v2.choose_threshold(y, calibration.apply(base_oof))
    x = frame[list(spec.features)].to_numpy(float)
    estimator = v2.fit_estimator(v2.build_estimator(kind, parameter, v2.SEED + 9000), kind, x, y)

    concept = PRODUCT_CONCEPTS[target]
    model_name = f"healthpal_{concept}_v3"
    model_path = output / f"{model_name}.onnx"
    parity_error = v2.export_onnx(estimator, kind, len(spec.features), model_path, x[:256])
    if parity_error > 1e-5:
        raise AssertionError(f"ONNX parity failed: {parity_error}")
    joblib.dump(estimator, output / f"{model_name}.joblib")
    if kind == "xgboost":
        estimator.save_model(output / f"{model_name}_xgboost.json")

    benchmark_export = benchmark.copy()
    benchmark_export["fold_auprc"] = benchmark_export["fold_auprc"].apply(json.dumps)
    benchmark_export["fold_auroc"] = benchmark_export["fold_auroc"].apply(json.dumps)
    benchmark_export.to_csv(output / "winner_final_candidate_benchmark.csv", index=False)
    frame[["id", "event_time", "target", *spec.features]].to_csv(
        output / "winner_training_dataset.csv", index=False
    )

    config = {
        "model_name": model_name,
        "target": target,
        "product_concept": concept,
        "positive_class": 1,
        "feature_spec": spec.name,
        "experiment": spec.experiment,
        "model_family": kind,
        "model_parameter": parameter,
        "feature_order": list(spec.features),
        "primary_window_hours": spec.window_hours,
        "window_interval": "[T-window,T)",
        "daily_alignment": "previous_calendar_day_D_minus_1",
        "minimum_hourly_coverage": {str(window): int(np.ceil(window / 2)) for window in v2.WINDOWS},
        "low_activity_steps_per_hour_threshold": spec.low_activity_threshold,
        "requires_binary_exercise_session_mask": spec.requires_exercise_mask,
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
    (output / f"{model_name}_config.json").write_text(
        json.dumps(json_ready(config), indent=2), encoding="utf-8"
    )
    return {
        "target": target,
        "product_concept": concept,
        "model_name": model_name,
        "deployment_selection": selected.to_dict(),
        "research_best": research_best.to_dict(),
        "final_parameter": parameter,
        "parameter_tuning": tuning,
        "calibration": config["calibration"],
        "threshold": threshold,
        "onnx_parity_error": parity_error,
        "feature_order": list(spec.features),
    }


def comparison_frame(results: dict[str, dict]) -> pd.DataFrame:
    rows = []
    for target in TARGETS:
        result = results[target]
        pooled = result["nested_selection_oof"]
        ci = result["cluster_bootstrap_95_ci"]
        rows.append(
            {
                "target": target,
                "events": result["events"],
                "positives": result["positives"],
                "prevalence": result["prevalence"],
                "auprc": pooled["auprc"],
                "auprc_ci_lower": ci["auprc"]["lower_95"],
                "auprc_ci_upper": ci["auprc"]["upper_95"],
                "auprc_lift": result["auprc_lift_over_prevalence"],
                "lift_hypothesis": result["lift_hypothesis"],
                "lift_hypothesis_met": result["lift_hypothesis_met"],
                "auroc": pooled["auroc"],
                "auroc_ci_lower": ci["auroc"]["lower_95"],
                "auroc_ci_upper": ci["auroc"]["upper_95"],
                "lowest_fold_auroc": result["lowest_fold_auroc"],
                "brier": pooled["brier"],
                "precision": pooled["precision"],
                "recall": pooled["recall"],
                "f1": pooled["f1"],
            }
        )
    return pd.DataFrame(rows)


def create_comparison_plot(comparison: pd.DataFrame, results: dict[str, dict], path: Path) -> None:
    labels = ["TENSE", "TIRED", "RESTED"]
    x = np.arange(len(labels))
    fig, axes = plt.subplots(2, 2, figsize=(11.5, 8.5))
    width = 0.34
    axes[0, 0].bar(x - width / 2, comparison["prevalence"], width, label="Prevalence", color="#90a4ae")
    axes[0, 0].bar(x + width / 2, comparison["auprc"], width, label="Nested OOF AUPRC", color="#00695c")
    axes[0, 0].set_xticks(x, labels)
    axes[0, 0].set(title="AUPRC versus random-ranking baseline", ylabel="Score")
    axes[0, 0].legend()

    colors = ["#2e7d32" if met else "#c62828" for met in comparison["lift_hypothesis_met"]]
    axes[0, 1].bar(x, comparison["auprc_lift"], color=colors)
    axes[0, 1].scatter(x, comparison["lift_hypothesis"], color="#111", marker="_", s=500, label="Hypothesis threshold")
    axes[0, 1].axhline(1.0, color="#777", ls="--")
    axes[0, 1].set_xticks(x, labels)
    axes[0, 1].set(title="AUPRC lift over prevalence", ylabel="Lift (×)")
    axes[0, 1].legend()

    lower = comparison["auroc"] - comparison["auroc_ci_lower"]
    upper = comparison["auroc_ci_upper"] - comparison["auroc"]
    axes[1, 0].errorbar(x, comparison["auroc"], yerr=[lower, upper], fmt="o", capsize=5, color="#1565c0")
    axes[1, 0].axhline(0.5, color="#777", ls="--")
    axes[1, 0].axhline(0.65, color="#c62828", ls=":", label="V2 MVP AUROC gate")
    axes[1, 0].set_xticks(x, labels)
    axes[1, 0].set_ylim(0.4, 0.85)
    axes[1, 0].set(title="AUROC with participant-cluster 95% CI", ylabel="AUROC")
    axes[1, 0].legend()

    for target, label, color in zip(TARGETS, labels, ("#6d4c41", "#ef6c00", "#7b1fa2")):
        folds = pd.DataFrame(results[target]["outer_fold_metrics"])
        axes[1, 1].plot(folds["fold"], folds["auroc"], marker="o", label=label, color=color)
    axes[1, 1].axhline(0.5, color="#777", ls="--")
    axes[1, 1].set_xticks(range(1, 6))
    axes[1, 1].set(title="Outer-fold AUROC stability", xlabel="Fold", ylabel="AUROC")
    axes[1, 1].legend()
    fig.suptitle("HealthPal V3 target benchmark", fontsize=15)
    fig.tight_layout()
    fig.savefig(path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def write_report(path: Path, comparison: pd.DataFrame, winner: dict) -> None:
    rows = {row.target: row for row in comparison.itertuples()}
    recommended = winner["target"]
    concept = winner["product_concept"]
    path.write_text(
        f"""# HealthPal V3 target benchmark

## Result

The nested participant-CV target with the largest AUPRC lift over its prevalence baseline is **{recommended}**. The corresponding product concept is **{concept}**.

This identifies the strongest **research direction**, not a validated product rename. A product pivot is supported only if the winning target meets its predeclared lift hypothesis and AUROC reaches 0.65. Otherwise, keep the artifact in research/shadow mode.

| Target | Prevalence | AUPRC | Lift | AUROC | Lowest fold AUROC |
| --- | ---: | ---: | ---: | ---: | ---: |
| TENSE/ANXIOUS | {rows['TENSE/ANXIOUS'].prevalence:.3f} | {rows['TENSE/ANXIOUS'].auprc:.3f} | {rows['TENSE/ANXIOUS'].auprc_lift:.2f}× | {rows['TENSE/ANXIOUS'].auroc:.3f} | {rows['TENSE/ANXIOUS'].lowest_fold_auroc:.3f} |
| TIRED | {rows['TIRED'].prevalence:.3f} | {rows['TIRED'].auprc:.3f} | {rows['TIRED'].auprc_lift:.2f}× | {rows['TIRED'].auroc:.3f} | {rows['TIRED'].lowest_fold_auroc:.3f} |
| RESTED/RELAXED | {rows['RESTED/RELAXED'].prevalence:.3f} | {rows['RESTED/RELAXED'].auprc:.3f} | {rows['RESTED/RELAXED'].auprc_lift:.2f}× | {rows['RESTED/RELAXED'].auroc:.3f} | {rows['RESTED/RELAXED'].lowest_fold_auroc:.3f} |

The three targets use the same event cohort and the same V2 feature/model candidate matrix. Target selection is based on the complete nested outer OOF procedure, not the best development row. TENSE/ANXIOUS reuses the exact V2 run after cohort-key verification; the other two targets are fresh runs.

## Interpretation constraints

- TIRED is a self-reported momentary fatigue label; RESTED/RELAXED is a self-reported recovery-like label. Neither is a clinical diagnosis.
- A larger lift supports target fit, but deployment still requires prospective Health Connect validation.
- Training readiness remains a separate rule engine and should consume a calibrated recovery/fatigue signal conservatively.
- All features remain causal, use D-1 daily sleep/RHR, and exclude the event hour.
""",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--v2-dir", type=Path, default=Path(__file__).resolve().parent / "artifacts" / "healthpal_stress_v2")
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent / "artifacts" / "healthpal_target_benchmark_v3")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)

    hourly, daily, source_manifest = read_sources(args.data_dir.resolve())
    tense_frame, cohort_audit = v2.build_wide_event_dataset(hourly, daily)
    frames = {target: attach_target(tense_frame, hourly, target) for target in TARGETS}
    keys = [frame[["id", "event_time"]].astype(str) for frame in frames.values()]
    if not all(keys[0].equals(item) for item in keys[1:]):
        raise AssertionError("V3 targets do not share identical event keys.")
    cohort_labels = tense_frame[["id", "event_time"]].copy()
    for target in TARGETS:
        cohort_labels[TARGET_SLUGS[target]] = frames[target]["target"].to_numpy(int)
    cohort_labels.to_csv(output / "common_cohort_targets.csv", index=False)

    specs = v2.feature_specs()
    results = {"TENSE/ANXIOUS": load_v2_tense_result(args.v2_dir.resolve(), frames["TENSE/ANXIOUS"])}
    for target in ("TIRED", "RESTED/RELAXED"):
        results[target] = run_nested_target(target, frames[target], specs, output)
        (output / "partial_target_comparison.json").write_text(
            json.dumps(json_ready(results), indent=2), encoding="utf-8"
        )

    comparison = comparison_frame(results)
    comparison.to_csv(output / "target_comparison.csv", index=False)
    winner_target = str(comparison.sort_values(["auprc_lift", "auroc"], ascending=False).iloc[0]["target"])
    winner = train_winner(winner_target, frames[winner_target], specs, output)

    winning_result = results[winner_target]
    pivot_supported = bool(
        winning_result["lift_hypothesis_met"]
        and winning_result["nested_selection_oof"]["auroc"] >= 0.65
    )
    summary = {
        "decision_rule": "Select the target with the largest nested-selection OOF AUPRC / prevalence lift; AUROC and fold stability are reported as safeguards.",
        "same_event_cohort": True,
        "cohort": cohort_audit,
        "targets": results,
        "winner": winner,
        "recommendation": {
            "target": winner_target,
            "product_concept": winner["product_concept"],
            "research_direction": winner["product_concept"],
            "product_rename_supported": pivot_supported,
            "deployment_mode": "prospective_research_or_shadow" if not pivot_supported else "eligible_for_mvp_review",
            "reason": "Winner must meet its predeclared AUPRC-lift hypothesis and AUROC >= 0.65 before a product rename is supported.",
        },
    }
    (output / "healthpal_v3_target_benchmark_metrics.json").write_text(
        json.dumps(json_ready(summary), indent=2), encoding="utf-8"
    )
    create_comparison_plot(comparison, results, output / "target_comparison_report.png")
    write_report(output / "MODEL_CARD_V3.md", comparison, winner)

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
        "seed": v2.SEED,
        "targets": list(TARGETS),
        "v2_tense_artifact": str(args.v2_dir.resolve()),
    }
    (output / "dataset_manifest.json").write_text(
        json.dumps(json_ready(manifest), indent=2), encoding="utf-8"
    )
    checksums = {
        str(path.relative_to(output)).replace("\\", "/"): sha256(path)
        for path in sorted(output.rglob("*"))
        if path.is_file() and path.name not in {"artifact_checksums.sha256.json", "partial_target_comparison.json"}
    }
    (output / "artifact_checksums.sha256.json").write_text(
        json.dumps(checksums, indent=2), encoding="utf-8"
    )
    (output / "partial_target_comparison.json").unlink(missing_ok=True)
    print(
        json.dumps(
            json_ready(
                {
                    "output_dir": str(output),
                    "comparison": comparison.to_dict("records"),
                    "winner": winner,
                }
            ),
            indent=2,
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
