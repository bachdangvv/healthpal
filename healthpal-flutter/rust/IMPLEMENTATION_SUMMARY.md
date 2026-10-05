# ML-01 and RS-01..RS-05 implementation summary

## ML-01 Freeze artifact bundle

Copied from `model_training/artifacts/healthpal_fatigue_v4/` into
`healthpal-flutter/rust/assets/healthpal_fatigue_v4/`:

- `healthpal_fatigue_v4.onnx`
- `healthpal_fatigue_v4_config.json`
- `artifact_checksums.sha256.json`

`model_training/export_mobile_v4.py` rebuilds a mobile graph with only standard
ONNX tensor ops (`Sub`, `Div`, `MatMul`, `Add`, `Sigmoid`). It includes
StandardScaler + logistic positive-class probability and **does not** include
the training `SimpleImputer`. Calibration slope/intercept and the decision
threshold stay in `healthpal_fatigue_v4_config.json`.

Build/test checksum gates:

- `rust/build.rs` fails the crate build if SHA-256 of the copied ONNX/config
  does not match `artifact_checksums.sha256.json`, or if the mobile artifacts
  do not match `mobile_artifact_checksums.sha256.json`.
- `python export_mobile_v4.py --check` repeats the same verification.

Verified probability parity (max abs diff, all < `1e-6`):

| Comparison set | Count | Max abs diff |
| --- | --- | --- |
| Finite training fixture vectors | 3398 | `1.24e-7` |
| Random valid vectors | 1000 | `1.97e-7` |

Compared sklearn/joblib, existing `ai.onnx.ml` ONNX, and mobile ONNX.

`python -m unittest test_export_mobile_v4.py` passed.

## RS-01 flutter_rust_bridge scaffold

Rust crate: `healthpal-flutter/rust` (`healthpal_core`, `Cargo.lock` pinned).

Dart API in `healthpal-flutter/lib/src/rust/`:

- `initHealthpalRust()`
- `modelInfo()`
- `assess({required AssessmentRequest request})`

ONNX Runtime session pointers never leave Rust.

`flutter_rust_bridge_codegen` 2.13.0 was installed and did generate a partial
bridge, then failed because it required `freezed`, which is incompatible with
the existing `drift_dev` constraint. The allowed fallback is in place: thin C
ABI (`healthpal_init`, `healthpal_model_info_json`, `healthpal_assess_json`)
plus `dart:ffi` with the same Dart API surface.

Android native lib `libhealthpal_core.so` is built by
`android/app/src/main/cpp/CMakeLists.txt` for:

| ABI | Rust target | Verified `.so` |
| --- | --- | --- |
| `arm64-v8a` | `aarch64-linux-android` | 26,624,000 bytes (ort linked) |
| `armeabi-v7a` | `armv7-linux-androideabi` | 624,644 bytes |
| `x86_64` | `x86_64-linux-android` | 901,752 bytes |

`ndk.abiFilters` is set to those three ABIs. A full APK build was not run in
this pass; the three `.so` files were produced with NDK 28.2 clang.

## RS-02 DTO + validation

`AssessmentRequest` / `AssessmentResult` live in `rust/src/types.rs`. Validation
rejects NaN/Infinity, negative counts, invalid durations, and timestamps after
`T`. Inputs are sorted internally. FFI catches panics and returns a typed
`AssessmentError` instead of unwinding across the boundary.

Fuzz loop of 200 shuffled/mutated requests did not panic.

## RS-03 Feature extraction parity

Window `[T-6h, T)`, exclusive of `T`. Raw samples are aggregated to local-hour
bins. Coverage requires ≥3 finite HR hours and ≥3 finite step hours
(`ceil(6/2)`). Stats match training:

- mean
- population std `ddof=0`
- median / p25 / p75 with NumPy default linear interpolation
- `h6_steps_sum` on finite step hours
- low activity `steps <= 250`
- `h6_hr_mean_minus_rhr`
- RHR and sleep D-1, no imputation

Golden test: 100 event fixtures reconstructed from the V4 training CSV /
hourly source. Each feature abs error `< 1e-5`.

Boundary tests: `T-6h` included, `T` excluded, midnight D-1, low-activity
exactly 250 included.

## RS-04 Inference

Host and Android arm64 run the mobile ONNX graph through the `ort` crate.
`ort` 2.0.0-rc.11 does not ship prebuilts for `armeabi-v7a` or
`x86_64-linux-android`; those ABIs execute the same frozen float32
scaler+logistic weights exported beside the ONNX file. Tests compare ort,
weights, sklearn, and Python mobile ONNX; max abs base/calibrated diff
`< 1e-5`.

Calibration is `sigmoid(slope * logit(clamp(p, 1e-6, 1-1e-6)) + intercept)`
from config (slope `0.7806493861342522`, intercept `-1.2659313281484506`).
Decision uses `calibrated >= threshold` (`0.18170608515558545`). SHA-256 is
computed over canonical little-endian f32 feature bytes and is not a result id.

## RS-05 Eligibility

Stable reason codes:

- `missing_hr_permission`
- `missing_steps_permission`
- `missing_sleep_permission`
- `missing_rhr_permission`
- `coverage_below_3_of_6`
- `missing_sleep_d1`
- `missing_rhr_d1`
- `missing_low250_hr` (no impute when low-activity hours is 0)
- `stale_latest_sample` (latest physiology older than 2 hours vs `T`)
- `watermark_incomplete`
- `no_new_data_since_previous`
- `suppressed_during_exercise` (session contains `T` or ended within 60 minutes before `T`)
- `uncanonical_sleep`

Missing/suppression paths return `insufficientData` or
`suppressedDuringExercise` and never invent a score.

## Commands verified

```text
python export_mobile_v4.py --check
python -m unittest test_export_mobile_v4.py
cargo fmt
cargo clippy --all-targets -- -D warnings
cargo test
dart analyze lib/src/rust
```

All of the above passed after the implementation.
