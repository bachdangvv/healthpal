# HealthPal stress-model training

This folder trains a participant-grouped binary stress-risk model from the two LifeSnaps CSV snapshots. Source CSVs are read-only. Derived data and model artifacts are written to `artifacts/healthpal_stress_v1/`.

## Reproduce

From the repository root on Windows:

```powershell
.\.venv\Scripts\python.exe -m unittest model_training\test_training_pipeline.py -v
.\.venv\Scripts\python.exe model_training\train_healthpal_stress.py
.\.venv\Scripts\python.exe -m unittest model_training\test_training_pipeline_v2.py -v
.\.venv\Scripts\python.exe model_training\train_healthpal_stress_v2.py
.\.venv\Scripts\python.exe -m unittest model_training\test_target_benchmark_v3.py -v
.\.venv\Scripts\python.exe model_training\train_healthpal_target_benchmark_v3.py
.\.venv\Scripts\python.exe -m unittest model_training\test_fatigue_v4.py -v
.\.venv\Scripts\python.exe model_training\train_healthpal_fatigue_v4.py
.\.venv\Scripts\python.exe -m unittest model_training\test_fatigue_v5.py -v
.\.venv\Scripts\python.exe model_training\train_healthpal_fatigue_v5.py
```

The pipeline:

1. validates the source schema, row snapshot and SHA-256 hashes;
2. deduplicates unlabelled hourly keys deterministically;
3. creates 6h/12h/24h event datasets from `[T-window, T)` and joins sleep/RHR from D-1;
4. benchmarks class-balanced logistic regression and histogram gradient boosting with 5-fold participant-grouped validation;
5. applies a one-standard-error simplicity rule;
6. runs nested participant-grouped evaluation for the selected model, with calibration and threshold choice inside each outer training fold;
7. refits on all eligible events and exports ONNX, config, checksums, OOF predictions, validation plots and a model card.

The ONNX model emits a base positive-class probability. Apply the calibration formula and threshold from `healthpal_stress_v1_config.json`. When coverage or D-1 sleep/RHR is unavailable, return `insufficient_data`; do not silently impute.

V2 adds 2h/4h/6h/12h windows, 2h-versus-6h recency deltas, HR relative to RHR, low-activity HR, binary exercise masking, robust quantiles and XGBoost. Its reported metric comes from a full nested feature/model-selection procedure, not from selecting the best row and reporting that same row's development score.

V3 leaves the V2 pipeline unchanged and compares `TENSE/ANXIOUS`, `TIRED`, and `RESTED/RELAXED` on the same event cohort. It selects the product target by nested-OOF AUPRC lift over target prevalence and exports a new ONNX artifact only for the winning target.

V4 fixes the target to `TIRED` and compares three predeclared production candidates. It reports locked nested OOF metrics for each candidate and a separate nested model-selection policy. XGBoost is chosen only when it clears predeclared AUPRC/AUROC improvement and fold-stability margins; otherwise the logistic candidate is preferred.

V5 keeps the V4 6-hour low-activity Logistic candidate and tests one change only: D-1 sleep-quality features that can be reconstructed from Health Connect session/stage timestamps. Fitbit proprietary efficiency, normalized stage ratios and SpO2 are excluded to reduce Fitbit-to-Huawei domain shift. V5 replaces V4 only if all predeclared paired improvement checks pass.
