using System.Net;
using FluentAssertions;
using HealthPal.Application.Contracts;
using HealthPal.Domain;
using HealthPal.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace HealthPal.IntegrationTests;

[Collection("api")]
public sealed class SyncTests
{
    private readonly HealthPalApiFactory _factory;

    public SyncTests(HealthPalApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Idempotent_retry_ten_times_creates_one_record_set()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);

        var key = Guid.NewGuid().ToString("N");
        var batch = SyncFixtures.CreateBatch(
            deviceId: "phone-1",
            idempotencyKey: key,
            steps: 2500,
            assessment: SyncFixtures.Assessment());

        SyncBatchResultDto? last = null;
        for (var i = 0; i < 10; i++)
        {
            var response = await client.PostAsync("/api/v1/sync/batches", TestJson.Body(batch));
            response.StatusCode.Should().Be(HttpStatusCode.OK);
            last = await TestJson.Read<SyncBatchResultDto>(response);
            last.Status.Should().Be("applied");
            last.IdempotencyKey.Should().Be(key);
        }

        last.Should().NotBeNull();
        last!.HourlyBinsUpserted.Should().Be(1);

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        (await db.HourlyHealthBins.CountAsync(h => h.UserId == session.User.Id)).Should().Be(1);
        (await db.DailyHealthSummaries.CountAsync(d => d.UserId == session.User.Id)).Should().Be(1);
        (await db.FatigueAssessments.CountAsync(a => a.UserId == session.User.Id)).Should().Be(1);
        (await db.SyncBatches.CountAsync(s => s.UserId == session.User.Id && s.IdempotencyKey == key)).Should().Be(1);
    }

    [Fact]
    public async Task Same_key_different_hash_returns_409()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var key = Guid.NewGuid().ToString("N");
        var first = await client.PostAsync(
            "/api/v1/sync/batches",
            TestJson.Body(SyncFixtures.CreateBatch(idempotencyKey: key, steps: 100)));
        first.EnsureSuccessStatusCode();

        var conflict = await client.PostAsync(
            "/api/v1/sync/batches",
            TestJson.Body(SyncFixtures.CreateBatch(idempotencyKey: key, steps: 999)));
        conflict.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Invalid_payload_rolls_back_entire_batch()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);

        var batch = SyncFixtures.CreateBatch(steps: 50);
        batch.FatigueAssessments =
        [
            SyncFixtures.Assessment()
        ];
        batch.FatigueAssessments[0].ModelVersion = "wrong_model";
        batch.FatigueAssessments[0].CalibratedProbability = 4;

        var response = await client.PostAsync("/api/v1/sync/batches", TestJson.Body(batch));
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("fatigueAssessments[0].modelVersion");
        body.Should().Contain("fatigueAssessments[0].calibratedProbability");

        var history = await TestJson.Read<List<DailyHealthSummaryDto>>(
            await client.GetAsync("/api/v1/history?from=2026-03-15&to=2026-03-15"));
        history.Should().BeEmpty();

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        (await db.HourlyHealthBins.CountAsync(h => h.UserId == session.User.Id)).Should().Be(0);
        (await db.SyncBatches.CountAsync(s => s.UserId == session.User.Id)).Should().Be(0);
    }

    [Fact]
    public async Task Concurrent_upsert_does_not_duplicate_hourly_bins()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);

        var hour = new DateTime(2026, 3, 15, 4, 0, 0, DateTimeKind.Utc);
        var first = SyncFixtures.CreateBatch(deviceId: "phone-1", idempotencyKey: Guid.NewGuid().ToString("N"), steps: 10, hourUtc: hour);
        var second = SyncFixtures.CreateBatch(deviceId: "phone-1", idempotencyKey: Guid.NewGuid().ToString("N"), steps: 20, hourUtc: hour);

        var responses = await Task.WhenAll(
            client.PostAsync("/api/v1/sync/batches", TestJson.Body(first)),
            client.PostAsync("/api/v1/sync/batches", TestJson.Body(second)));
        responses.Should().OnlyContain(r => r.IsSuccessStatusCode);

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        var bins = await db.HourlyHealthBins.Where(h => h.UserId == session.User.Id && h.HourUtc == hour).ToListAsync();
        bins.Should().HaveCount(1);
        bins[0].Steps.Should().BeOneOf(10, 20);
    }

    [Fact]
    public async Task Server_does_not_alter_client_probabilities()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var assessment = SyncFixtures.Assessment(probability: 0.18170608515558545);
        var response = await client.PostAsync(
            "/api/v1/sync/batches",
            TestJson.Body(SyncFixtures.CreateBatch(assessment: assessment)));
        response.EnsureSuccessStatusCode();

        var latest = await TestJson.Read<FatigueAssessmentDto>(await client.GetAsync("/api/v1/assessments/latest"));
        latest.CalibratedProbability.Should().Be(0.18170608515558545);
        latest.ModelVersion.Should().Be(HealthPalConstants.FatigueModelVersion);
        latest.Status.Should().Be(FatigueAssessmentStatus.SignalDetected);
    }
}
