FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY Directory.Build.props ./
COPY HealthPal.sln ./
COPY src/HealthPal.Domain/HealthPal.Domain.csproj src/HealthPal.Domain/
COPY src/HealthPal.Application/HealthPal.Application.csproj src/HealthPal.Application/
COPY src/HealthPal.Infrastructure/HealthPal.Infrastructure.csproj src/HealthPal.Infrastructure/
COPY src/HealthPal.Api/HealthPal.Api.csproj src/HealthPal.Api/
RUN dotnet restore src/HealthPal.Api/HealthPal.Api.csproj
COPY src/ src/
RUN dotnet publish src/HealthPal.Api/HealthPal.Api.csproj -c Release -o /app/publish --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:5080
ENV ASPNETCORE_ENVIRONMENT=Production
EXPOSE 5080
USER $APP_UID
ENTRYPOINT ["dotnet", "HealthPal.Api.dll"]
