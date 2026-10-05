using System.Net;
using FluentAssertions;
using HealthPal.Application.Contracts;
using HealthPal.Domain;
using HealthPal.Infrastructure.Persistence;
using HealthPal.Infrastructure.Sync;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;

namespace HealthPal.IntegrationTests;

[Collection("api")]
public sealed class ReplacementWindowTests
{
    private readonly HealthPalApiFactory _factory;

    public ReplacementWindowTests(HealthPalApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Schema_v2_missing_window_returns_400()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var batch = SyncFixtures.CreateV2Batch();
        batch.ReplacementWindow = null;
        var response = await client.PostAsync("/api/v1/sync/batches", TestJson.Body(batch));
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await response.Content.ReadAsStringAsync()).Should().Contain("replacementWindow");
    }

    [Fact]
    public async Task Schema_v2_replaces_inside_window_and_keeps_outside_and_other_users()
    {
        using var client = _factory.CreateClient();
        var userA = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, userA.Tokens.AccessToken);

        var insideHour = new DateTime(2026, 3, 15, 1, 0, 0, DateTimeKind.Utc);
        var outsideHour = new DateTime(2026, 3, 10, 1, 0, 0, DateTimeKind.Utc);
        var insideExercise = Exercise("ex-in", insideHour, insideHour.AddMinutes(30));
        var outsideExercise = Exercise("ex-out", outsideHour, outsideHour.AddMinutes(20));

        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(hourUtc: insideHour, localDate: new DateOnly(2026, 3, 15), steps: 100, exercise: insideExercise))))
            .EnsureSuccessStatusCode();
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(
                deviceId: "device-outside",
                hourUtc: outsideHour,
                localDate: new DateOnly(2026, 3, 10),
                steps: 11,
                exercise: outsideExercise))))
            .EnsureSuccessStatusCode();

        using var clientB = _factory.CreateClient();
        var userB = await TestJson.RegisterAsync(clientB, email: $"b-{Guid.NewGuid():N}@healthpal.app");
        TestJson.Bearer(clientB, userB.Tokens.AccessToken);
        (await clientB.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(hourUtc: insideHour, localDate: new DateOnly(2026, 3, 15), steps: 777))))
            .EnsureSuccessStatusCode();

        var replacement = SyncFixtures.CreateV2Batch(
            steps: 250,
            hourUtc: insideHour,
            localDate: new DateOnly(2026, 3, 15),
            exercise: Exercise("ex-new", insideHour, insideHour.AddMinutes(15)));
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(replacement))).EnsureSuccessStatusCode();

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        var aHours = await db.HourlyHealthBins.Where(h => h.UserId == userA.User.Id).ToListAsync();
        aHours.Should().ContainSingle(h => h.HourUtc == insideHour && h.Steps == 250);
        aHours.Should().ContainSingle(h => h.HourUtc == outsideHour && h.Steps == 11);

        var aDays = await db.DailyHealthSummaries.Where(d => d.UserId == userA.User.Id).ToListAsync();
        aDays.Should().ContainSingle(d => d.LocalDate == new DateOnly(2026, 3, 15) && d.Steps == 250);
        aDays.Should().ContainSingle(d => d.LocalDate == new DateOnly(2026, 3, 10) && d.Steps == 11);

        var aExercises = await db.ExerciseSessions.Where(e => e.UserId == userA.User.Id).ToListAsync();
        aExercises.Select(e => e.ExternalRecordId).Should().BeEquivalentTo("ex-new", "ex-out");

        (await db.HourlyHealthBins.SingleAsync(h => h.UserId == userB.User.Id)).Steps.Should().Be(777);
    }

    [Fact]
    public async Task Empty_v2_snapshot_prunes_stale_rows_in_window()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var hour = new DateTime(2026, 3, 15, 1, 0, 0, DateTimeKind.Utc);
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(
                hourUtc: hour,
                localDate: new DateOnly(2026, 3, 15),
                exercise: Exercise("ex-stale", hour, hour.AddMinutes(10))))))
            .EnsureSuccessStatusCode();

        var empty = new SyncBatchDto
        {
            SchemaVersion = HealthPalConstants.SyncSchemaVersionV2,
            DeviceId = "device-1",
            IdempotencyKey = Guid.NewGuid().ToString("N"),
            GeneratedAtUtc = new DateTime(2026, 3, 15, 8, 0, 0, DateTimeKind.Utc),
            ReplacementWindow = SyncFixtures.Window()
        };
        var response = await client.PostAsync("/api/v1/sync/batches", TestJson.Body(empty));
        response.EnsureSuccessStatusCode();
        var result = await TestJson.Read<SyncBatchResultDto>(response);
        result.HourlyBinsDeleted.Should().BeGreaterThan(0);
        result.DailySummariesDeleted.Should().BeGreaterThan(0);
        result.ExerciseSessionsDeleted.Should().BeGreaterThan(0);

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        (await db.HourlyHealthBins.CountAsync(h => h.UserId == session.User.Id)).Should().Be(0);
        (await db.DailyHealthSummaries.CountAsync(d => d.UserId == session.User.Id)).Should().Be(0);
        (await db.ExerciseSessions.CountAsync(e => e.UserId == session.User.Id)).Should().Be(0);
    }

    [Fact]
    public async Task Schema_v1_does_not_delete_stale_rows()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var firstHour = new DateTime(2026, 3, 15, 1, 0, 0, DateTimeKind.Utc);
        var secondHour = new DateTime(2026, 3, 15, 2, 0, 0, DateTimeKind.Utc);
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(hourUtc: firstHour, steps: 10)))).EnsureSuccessStatusCode();
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(deviceId: "device-2", hourUtc: secondHour, steps: 20)))).EnsureSuccessStatusCode();

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        (await db.HourlyHealthBins.CountAsync(h => h.UserId == session.User.Id)).Should().Be(2);
    }

    [Fact]
    public async Task Idempotent_v2_retry_does_not_replace_twice()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var hour = new DateTime(2026, 3, 15, 1, 0, 0, DateTimeKind.Utc);
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(hourUtc: hour, steps: 10)))).EnsureSuccessStatusCode();

        var key = Guid.NewGuid().ToString("N");
        var empty = new SyncBatchDto
        {
            SchemaVersion = HealthPalConstants.SyncSchemaVersionV2,
            DeviceId = "device-1",
            IdempotencyKey = key,
            GeneratedAtUtc = new DateTime(2026, 3, 15, 8, 0, 0, DateTimeKind.Utc),
            ReplacementWindow = SyncFixtures.Window()
        };
        var first = await client.PostAsync("/api/v1/sync/batches", TestJson.Body(empty));
        first.EnsureSuccessStatusCode();
        var firstResult = await TestJson.Read<SyncBatchResultDto>(first);
        firstResult.HourlyBinsDeleted.Should().BeGreaterThan(0);

        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(deviceId: "seed-after", hourUtc: hour, steps: 99)))).EnsureSuccessStatusCode();

        var retry = await client.PostAsync("/api/v1/sync/batches", TestJson.Body(empty));
        retry.EnsureSuccessStatusCode();
        var retryResult = await TestJson.Read<SyncBatchResultDto>(retry);
        retryResult.HourlyBinsDeleted.Should().Be(firstResult.HourlyBinsDeleted);

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        (await db.HourlyHealthBins.SingleAsync(h => h.UserId == session.User.Id && h.HourUtc == hour))
            .Steps.Should().Be(99);
        (await db.SyncBatches.CountAsync(s => s.UserId == session.User.Id && s.IdempotencyKey == key)).Should().Be(1);
    }

    [Fact]
    public async Task Same_key_different_v2_payload_still_conflicts()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var key = Guid.NewGuid().ToString("N");
        var first = SyncFixtures.CreateV2Batch(idempotencyKey: key, steps: 10);
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(first))).EnsureSuccessStatusCode();
        var conflict = SyncFixtures.CreateV2Batch(idempotencyKey: key, steps: 999);
        var response = await client.PostAsync("/api/v1/sync/batches", TestJson.Body(conflict));
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Injected_failure_after_delete_rolls_back_window()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);

        var insideHour = new DateTime(2026, 3, 15, 1, 0, 0, DateTimeKind.Utc);
        var outsideHour = new DateTime(2026, 3, 10, 1, 0, 0, DateTimeKind.Utc);
        var insideExercise = Exercise("ex-in", insideHour, insideHour.AddMinutes(30));
        var outsideExercise = Exercise("ex-out", outsideHour, outsideHour.AddMinutes(20));

        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(
                hourUtc: insideHour,
                localDate: new DateOnly(2026, 3, 15),
                steps: 42,
                exercise: insideExercise)))).EnsureSuccessStatusCode();
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(
            SyncFixtures.CreateBatch(
                deviceId: "device-outside",
                hourUtc: outsideHour,
                localDate: new DateOnly(2026, 3, 10),
                steps: 11,
                exercise: outsideExercise)))).EnsureSuccessStatusCode();

        await using (var beforeScope = _factory.Services.CreateAsyncScope())
        {
            var beforeDb = beforeScope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
            (await beforeDb.SyncBatches.CountAsync(s => s.UserId == session.User.Id)).Should().Be(2);
        }

        var failKey = Guid.NewGuid().ToString("N");
        using var failingFactory = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<HealthUpsertExecutor>();
                services.AddScoped<HealthUpsertExecutor, ThrowAfterReplacementDeleteExecutor>();
            });
        });
        using var failingClient = failingFactory.CreateClient();
        TestJson.Bearer(failingClient, session.Tokens.AccessToken);
        var failingBatch = SyncFixtures.CreateV2Batch(
            deviceId: "failing-device",
            idempotencyKey: failKey,
            hourUtc: insideHour,
            localDate: new DateOnly(2026, 3, 15),
            steps: 250,
            exercise: Exercise("ex-new", insideHour, insideHour.AddMinutes(15)));
        var response = await failingClient.PostAsync("/api/v1/sync/batches", TestJson.Body(failingBatch));
        response.StatusCode.Should().Be(HttpStatusCode.InternalServerError);
        (await response.Content.ReadAsStringAsync()).Should().Contain("injected_after_replacement_delete");

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        var hours = await db.HourlyHealthBins.AsNoTracking().Where(h => h.UserId == session.User.Id).ToListAsync();
        hours.Should().ContainSingle(h => h.HourUtc == insideHour && h.Steps == 42);
        hours.Should().ContainSingle(h => h.HourUtc == outsideHour && h.Steps == 11);
        hours.Should().NotContain(h => h.Steps == 250);

        var days = await db.DailyHealthSummaries.AsNoTracking().Where(d => d.UserId == session.User.Id).ToListAsync();
        days.Should().ContainSingle(d => d.LocalDate == new DateOnly(2026, 3, 15) && d.Steps == 42);
        days.Should().ContainSingle(d => d.LocalDate == new DateOnly(2026, 3, 10) && d.Steps == 11);

        var exercises = await db.ExerciseSessions.AsNoTracking().Where(e => e.UserId == session.User.Id).ToListAsync();
        exercises.Select(e => e.ExternalRecordId).Should().BeEquivalentTo("ex-in", "ex-out");

        (await db.SyncBatches.AsNoTracking().CountAsync(s => s.UserId == session.User.Id)).Should().Be(2);
        (await db.SyncBatches.AsNoTracking().AnyAsync(s => s.UserId == session.User.Id && s.IdempotencyKey == failKey))
            .Should().BeFalse();
        (await db.Devices.AsNoTracking().AnyAsync(d => d.UserId == session.User.Id && d.Id == "failing-device"))
            .Should().BeFalse();
    }

    private static ExerciseSessionDto Exercise(string id, DateTime start, DateTime end) =>
        new()
        {
            ExternalRecordId = id,
            Type = "walking",
            StartUtc = start,
            EndUtc = end,
            ZoneOffsetMinutes = 0,
            DurationMinutes = (int)(end - start).TotalMinutes,
            Calories = 40,
            SourceId = "health_sync"
        };
}

sealed class ThrowAfterReplacementDeleteExecutor : HealthUpsertExecutor
{
    public override Task UpsertHourlyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        HourlyHealthBinDto bin,
        DateTimeOffset now,
        CancellationToken cancellationToken) =>
        throw new InvalidOperationException("injected_after_replacement_delete");
}
