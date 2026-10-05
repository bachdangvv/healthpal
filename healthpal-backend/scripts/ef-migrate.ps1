$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
& "C:\Program Files\dotnet\dotnet.exe" tool restore
& "C:\Program Files\dotnet\dotnet.exe" ef database update `
  --project src/HealthPal.Infrastructure/HealthPal.Infrastructure.csproj `
  --startup-project src/HealthPal.Api/HealthPal.Api.csproj
