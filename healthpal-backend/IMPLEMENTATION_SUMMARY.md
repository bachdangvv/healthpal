# BE-01..BE-07 implementation summary

Backend lives only under `healthpal-backend/`. Flutter, model training and `grok_progress.md` were not modified.

## Test results

```
dotnet build  — 0 warnings, 0 errors
dotnet test   — Passed: 42, Failed: 0
  HealthPal.UnitTests:         17 passed
  HealthPal.IntegrationTests:  25 passed (Testcontainers PostgreSQL 16)
```

Covered: register/login/refresh rotation/reuse-family-revoke/logout/change-password/delete-account; user A cannot read user B; profile validation and 409 rowVersion; 10× idempotent batch; hash mismatch 409; invalid payload rollback; concurrent hourly upsert; null vs 0 history; timezone midnight exercises; cascade delete; migration up/down; live/ready; OpenAPI snapshot.

## Decisions

- Clean architecture: Api / Application / Domain / Infrastructure, net8.0, nullable, `TreatWarningsAsErrors`.
- Identity + JWT access (15 min) + hashed rotating refresh tokens; reuse of a rotated token revokes the family.
- Login unknown email and wrong password return the same 401 body.
- PostgreSQL via Npgsql + snake_case. `xmin` is the profile concurrency token (exposed as decimal string `rowVersion`).
- Health upserts use `INSERT ... ON CONFLICT` inside the same transaction as the sync-batch idempotency row.
- Server stores client fatigue probabilities as-is (`healthpal_fatigue_v4` only). Feature vector JSON is stored only when `experimentalFatigueConsent` is true.
- History/dashboard do not invent days or zeros. Exercises are filtered by local date using `startUtc + zoneOffsetMinutes`.
- Structured Serilog JSON logs with correlation id. Request bodies, tokens, passwords and health payloads are not logged.
- CORS only in Development; no wildcard. HSTS/HTTPS redirect outside Development and Testing. Kestrel listens on 5080.

## Layout

- `HealthPal.sln`, `Directory.Build.props`, `Dockerfile`, `docker-compose.yml`
- `src/HealthPal.Api` — controllers, middleware, Program
- `src/HealthPal.Application` — DTOs, validators, token hash
- `src/HealthPal.Domain` — entities and enums
- `src/HealthPal.Infrastructure` — EF Core, Identity, auth/profile/sync/query
- `src/HealthPal.Infrastructure/Persistence/Migrations` — `InitialCreate`
- `tests/HealthPal.UnitTests`, `tests/HealthPal.IntegrationTests`
- `openapi/healthpal-v1.json`

## Skipped / out of scope

- Flutter, Rust, Training Readiness, V5, SpO2, HRV model inputs, iOS.
- Physical Huawei Band 10 / Health Connect device checks (device-only).
- `docker compose up` was not left running; Compose files apply migrations on API startup. Integration tests already applied migrations against real PostgreSQL.
- Logout-all-devices as a separate endpoint: `POST /auth/logout` without a refresh token revokes every active refresh token for the user; with a refresh token it revokes that family.
