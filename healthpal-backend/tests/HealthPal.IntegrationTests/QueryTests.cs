using System.Net;
using System.Text.Json;
using FluentAssertions;
using HealthPal.Application.Contracts;
using HealthPal.Domain;

namespace HealthPal.IntegrationTests;

[Collection("api")]
public sealed class QueryTests
{
    private readonly HealthPalApiFactory _factory;

    public QueryTests(HealthPalApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task History_does_not_fill_gaps_and_distinguishes_null_from_zero()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);

        var withZero = SyncFixtures.CreateBatch(
            idempotencyKey: Guid.NewGuid().ToString("N"),
            localDate: new DateOnly(2026, 3, 10),
            steps: 0,
            sleepMinutes: 0);
        withZero.DailySummaries[0].ActiveCalories = 0;
        var withNull = SyncFixtures.CreateBatch(
            idempotencyKey: Guid.NewGuid().ToString("N"),
            localDate: new DateOnly(2026, 3, 12),
            steps: null,
            sleepMinutes: null);
        withNull.DailySummaries[0].ActiveCalories = null;
        withNull.HourlyBins[0].Steps = null;
        withNull.HourlyBins[0].ActiveCalories = null;

        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(withZero))).EnsureSuccessStatusCode();
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(withNull))).EnsureSuccessStatusCode();

        var response = await client.GetAsync("/api/v1/history?from=2026-03-10&to=2026-03-12");
        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync();
        using var document = JsonDocument.Parse(json);
        document.RootElement.GetArrayLength().Should().Be(2);

        var zeroDay = document.RootElement.EnumerateArray().Single(e => e.GetProperty("localDate").GetString() == "2026-03-10");
        zeroDay.GetProperty("steps").GetInt32().Should().Be(0);
        zeroDay.GetProperty("sleepMinutes").GetInt32().Should().Be(0);
        zeroDay.GetProperty("activeCalories").GetDouble().Should().Be(0);

        var nullDay = document.RootElement.EnumerateArray().Single(e => e.GetProperty("localDate").GetString() == "2026-03-12");
        nullDay.GetProperty("steps").ValueKind.Should().Be(JsonValueKind.Null);
        nullDay.GetProperty("sleepMinutes").ValueKind.Should().Be(JsonValueKind.Null);
        nullDay.GetProperty("activeCalories").ValueKind.Should().Be(JsonValueKind.Null);

        var history = JsonSerializer.Deserialize<List<DailyHealthSummaryDto>>(json, TestJson.Options);
        history.Should().NotBeNull();
        history!.Select(h => h.LocalDate).Should().Equal(new DateOnly(2026, 3, 10), new DateOnly(2026, 3, 12));
    }

    [Fact]
    public async Task Dashboard_and_latest_assessment_are_user_scoped()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var assessment = SyncFixtures.Assessment(probability: 0.22);
        (await client.PostAsync(
            "/api/v1/sync/batches",
            TestJson.Body(SyncFixtures.CreateBatch(steps: 8000, assessment: assessment)))).EnsureSuccessStatusCode();

        var dashboard = await TestJson.Read<DashboardTodayDto>(
            await client.GetAsync("/api/v1/dashboard/today?localDate=2026-03-15&timezone=Asia/Ho_Chi_Minh"));
        dashboard.LocalDate.Should().Be(new DateOnly(2026, 3, 15));
        dashboard.Summary.Should().NotBeNull();
        dashboard.Summary!.Steps.Should().Be(8000);
        dashboard.Summary.Fatigue.Should().NotBeNull();
        dashboard.Summary.Fatigue!.Probability.Should().Be(0.22);
        dashboard.LatestAssessment.Should().NotBeNull();
        dashboard.LatestSampleAtUtc.Should().NotBeNull();
        dashboard.ServerSyncedAtUtc.Should().NotBeNull();

        var latest = await TestJson.Read<FatigueAssessmentDto>(await client.GetAsync("/api/v1/assessments/latest"));
        latest.Id.Should().Be(assessment.Id);
    }

    [Fact]
    public async Task Exercises_honor_local_timezone_midnight()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);

        var exercise = new ExerciseSessionDto
        {
            ExternalRecordId = "ex-midnight",
            Type = "running",
            StartUtc = new DateTime(2026, 3, 15, 23, 30, 0, DateTimeKind.Utc),
            EndUtc = new DateTime(2026, 3, 16, 0, 10, 0, DateTimeKind.Utc),
            ZoneOffsetMinutes = 420,
            DurationMinutes = 40,
            Calories = 300,
            SourceId = "health_sync"
        };
        var batch = SyncFixtures.CreateBatch(
            localDate: new DateOnly(2026, 3, 16),
            exercise: exercise);
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(batch))).EnsureSuccessStatusCode();

        var fifteenth = await TestJson.Read<List<ExerciseSessionDto>>(
            await client.GetAsync("/api/v1/exercises?from=2026-03-15&to=2026-03-15"));
        fifteenth.Should().BeEmpty();

        var sixteenth = await TestJson.Read<List<ExerciseSessionDto>>(
            await client.GetAsync("/api/v1/exercises?from=2026-03-16&to=2026-03-16"));
        sixteenth.Should().ContainSingle();
        sixteenth[0].ExternalRecordId.Should().Be("ex-midnight");
        sixteenth[0].Calories.Should().Be(300);
    }

    [Fact]
    public async Task History_rejects_range_over_90_days()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var response = await client.GetAsync("/api/v1/history?from=2026-01-01&to=2026-04-15");
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Latest_assessment_is_404_when_missing()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var response = await client.GetAsync("/api/v1/assessments/latest");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
