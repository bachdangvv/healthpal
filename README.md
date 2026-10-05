# HealthPal

Android-first health companion. Fatigue V4 is an experimental signal, not a medical diagnosis.

## Layout

- `healthpal-flutter/` — Flutter app, local SQLite, Health Connect, Rust model crate
- `healthpal-backend/` — ASP.NET Core 8 API + PostgreSQL
- `model_training/` — training and mobile-export scripts

## Version control

This workspace is a single monorepo containing the mobile app, backend, and model-training source. Generated training artifacts, raw datasets, local notes, `rust/target`, .NET `bin`/`obj`, Gradle caches, and APKs are intentionally excluded from version control.

## Flutter

Android toolchain pin: **AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.14** (Flutter 3.38). APKs: `healthpal-flutter/build/app/outputs/flutter-apk/`.

```sh
cd healthpal-flutter
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080 --dart-define=ENABLE_EXPERIMENTAL_FATIGUE=true
```

Set `ENABLE_EXPERIMENTAL_FATIGUE=false` for builds outside the trial group.

Fatigue V4 is an experimental recovery/fatigue signal, not a medical diagnosis.

## Backend

Requires .NET 8 and Docker.

```sh
cd healthpal-backend
dotnet restore
dotnet test
docker compose up --build
```

API listens on port 5080. Do not commit real connection strings.

## Huawei Band 10

Band → Huawei Health → Health Sync (Daily Sync on) → Health Connect → HealthPal.
HealthPal cannot force Health Sync to run. If data is stale, open Health Sync, sync, then tap Đồng bộ ngay.

## Model

Training artifacts are generated locally under `model_training/artifacts/` and are not committed.
The frozen mobile runtime copy is tracked under `healthpal-flutter/rust/assets/healthpal_fatigue_v4/`.
