# HealthPal backend

ASP.NET Core 8 API for authentication, profile, idempotent health sync, dashboard and history. JSON contracts match the Flutter DTOs (camelCase).

## Requirements

- .NET SDK 8.0.425+
- Docker (for Compose and integration tests)
- PostgreSQL 16 (Compose provides this)

## Configuration

Do not commit real secrets. `appsettings.json` contains placeholders only.

| Setting | Source |
| --- | --- |
| `ConnectionStrings:DefaultConnection` | `Host=postgres;Database=healthpal;Username=healthpal;Password=CHANGE_ME` |
| `POSTGRES_PASSWORD` | Replaces the connection-string password when set |
| `Jwt:SigningKey` | At least 32 characters. Required outside Development/Testing |

User secrets (local `dotnet run`):

```powershell
cd src/HealthPal.Api
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Host=localhost;Database=healthpal;Username=healthpal;Password=healthpal_dev_password"
dotnet user-secrets set "POSTGRES_PASSWORD" "healthpal_dev_password"
dotnet user-secrets set "Jwt:SigningKey" "dev-only-signing-key-not-for-production-use!!"
```

`Properties/launchSettings.json` sets Development env vars for a local Kestrel listener on port **5080**.

## Restore, migrate, run

```powershell
cd healthpal-backend
dotnet restore
dotnet tool restore
dotnet ef database update --project src/HealthPal.Infrastructure --startup-project src/HealthPal.Api
dotnet run --project src/HealthPal.Api
```

Or apply migrations with `scripts/ef-migrate.ps1`.

Health checks:

- `GET http://localhost:5080/health/live` — process is up
- `GET http://localhost:5080/health/ready` — PostgreSQL is reachable

OpenAPI UI (non-Production): `http://localhost:5080/swagger`

## Docker Compose

```powershell
cd healthpal-backend
$env:POSTGRES_PASSWORD = "healthpal_dev_password"
$env:JWT_SIGNING_KEY = "dev-only-signing-key-not-for-production-use!!"
docker compose up --build
```

The API container listens on **HTTP :5080 only** (no in-container HTTPS redirect). Put TLS on a reverse proxy if needed. EF migrations run on startup. Postgres is healthy before the API starts. Compose interpolates `POSTGRES_PASSWORD` into both the database and the API connection string.

## Tests

```powershell
dotnet test
```

Integration tests start PostgreSQL with Testcontainers. Docker Desktop must be running.

## API (v1)

All health/profile routes take the user id from the JWT only.

| Method | Path |
| --- | --- |
| POST | `/api/v1/auth/register` |
| POST | `/api/v1/auth/login` |
| POST | `/api/v1/auth/refresh` |
| POST | `/api/v1/auth/logout` |
| GET | `/api/v1/auth/me` |
| POST | `/api/v1/auth/change-password` |
| DELETE | `/api/v1/auth/account` |
| GET/PUT | `/api/v1/profile` |
| PUT | `/api/v1/profile/preferences` |
| POST | `/api/v1/sync/batches` |
| GET | `/api/v1/dashboard/today?localDate=YYYY-MM-DD&timezone=...` |
| GET | `/api/v1/assessments/latest` |
| GET | `/api/v1/history?from=YYYY-MM-DD&to=YYYY-MM-DD` |
| GET | `/api/v1/exercises?from=YYYY-MM-DD&to=YYYY-MM-DD` |
| GET | `/api/v1/training/readiness?localDate=YYYY-MM-DD` |
| GET | `/api/v1/training/exercises?muscleGroup=legs&query=squat` |
| PUT | `/api/v1/training/exercises/{exerciseId}/favorite` |

Committed OpenAPI snapshot: `openapi/healthpal-v1.json`.

## Notes

- Access JWT lifetime is 15 minutes. Refresh tokens are 32 random bytes, stored as SHA-256 only, rotated on every use. Reuse of a rotated token revokes the family.
- Sync does not re-run the fatigue model or change client probabilities.
- Development only: seeds `demo@healthpal.app` / `HealthPal123`.
- CORS is Development-only and never `*`. HTTPS redirect and HSTS run only when `ASPNETCORE_URLS` contains `https://`. The Compose/Dockerfile image binds HTTP `:5080` only.
