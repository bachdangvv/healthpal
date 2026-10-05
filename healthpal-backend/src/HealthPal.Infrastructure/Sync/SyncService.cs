using System.Data;
using System.Text.Json;
using System.Text.Json.Serialization;
using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using HealthPal.Application.Exceptions;
using HealthPal.Application.Security;
using HealthPal.Application.Validation;
using HealthPal.Domain;
using HealthPal.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.Logging;
using Npgsql;

namespace HealthPal.Infrastructure.Sync;

public sealed class SyncService : ISyncService
{
    private static readonly JsonSerializerOptions ResultJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never
    };

    private readonly HealthPalDbContext _db;
    private readonly HealthUpsertExecutor _upsert;
    private readonly IClock _clock;
    private readonly ILogger<SyncService> _logger;

    public SyncService(HealthPalDbContext db, HealthUpsertExecutor upsert, IClock clock, ILogger<SyncService> logger)
    {
        _db = db;
        _upsert = upsert;
        _clock = clock;
        _logger = logger;
    }

    public async Task<SyncBatchResultDto> IngestAsync(string userId, SyncBatchDto batch, CancellationToken cancellationToken)
    {
        SyncBatchValidator.Validate(batch);
        var payloadHash = PayloadCanonicalizer.Hash(batch);
        var now = _clock.UtcNow;

        await using var transaction = await _db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);
        var connection = (NpgsqlConnection)_db.Database.GetDbConnection();
        if (connection.State != ConnectionState.Open)
        {
            await connection.OpenAsync(cancellationToken);
        }

        var npgsqlTransaction = (NpgsqlTransaction)transaction.GetDbTransaction();
        var insertedId = await _upsert.TryInsertBatchAsync(connection, npgsqlTransaction, userId, batch, payloadHash, now, cancellationToken);
        if (insertedId is null)
        {
            var existing = await _upsert.FindBatchAsync(connection, npgsqlTransaction, userId, batch.DeviceId, batch.IdempotencyKey, cancellationToken)
                ?? throw new ConflictAppException("Idempotency key conflict could not be resolved.", "idempotencyKey");
            if (!string.Equals(existing.PayloadHash, payloadHash, StringComparison.Ordinal))
            {
                throw new ConflictAppException("Idempotency key was reused with a different payload.", "idempotencyKey");
            }

            await transaction.CommitAsync(cancellationToken);
            var previous = JsonSerializer.Deserialize<SyncBatchResultDto>(existing.ResultJson, ResultJsonOptions)
                ?? throw new InvalidOperationException("Stored sync result is unreadable.");
            _logger.LogInformation(
                "Sync batch idempotent replay. UserId={UserId} DeviceId={DeviceId} IdempotencyKey={IdempotencyKey} PayloadHash={PayloadHash}",
                userId,
                batch.DeviceId,
                batch.IdempotencyKey,
                payloadHash);
            return previous;
        }

        var storeFeatureVector = await _db.UserProfiles
            .AsNoTracking()
            .Where(p => p.UserId == userId)
            .Select(p => p.ExperimentalFatigueConsent)
            .SingleAsync(cancellationToken);

        await _upsert.UpsertDeviceAsync(connection, npgsqlTransaction, userId, batch.DeviceId, now, cancellationToken);

        var hourlyDeleted = 0;
        var dailyDeleted = 0;
        var exerciseDeleted = 0;
        if (batch.SchemaVersion == HealthPalConstants.SyncSchemaVersionV2 &&
            batch.ReplacementWindow is { } window)
        {
            hourlyDeleted = await _upsert.DeleteHourlyWindowAsync(
                connection,
                npgsqlTransaction,
                userId,
                window.StartUtc,
                window.EndUtcExclusive,
                cancellationToken);
            dailyDeleted = await _upsert.DeleteDailyWindowAsync(
                connection,
                npgsqlTransaction,
                userId,
                window.LocalDateStart,
                window.LocalDateEndExclusive,
                cancellationToken);
            exerciseDeleted = await _upsert.DeleteExerciseWindowAsync(
                connection,
                npgsqlTransaction,
                userId,
                window.StartUtc,
                window.EndUtcExclusive,
                cancellationToken);
        }

        foreach (var hourly in batch.HourlyBins)
        {
            await _upsert.UpsertHourlyAsync(connection, npgsqlTransaction, userId, hourly, now, cancellationToken);
        }

        foreach (var daily in batch.DailySummaries)
        {
            await _upsert.UpsertDailyAsync(connection, npgsqlTransaction, userId, daily, now, cancellationToken);
        }

        foreach (var exercise in batch.ExerciseSessions)
        {
            await _upsert.UpsertExerciseAsync(connection, npgsqlTransaction, userId, exercise, cancellationToken);
        }

        foreach (var assessment in batch.FatigueAssessments)
        {
            // Server stores client probabilities as-is; it never re-runs the model.
            await _upsert.UpsertAssessmentAsync(connection, npgsqlTransaction, userId, assessment, storeFeatureVector, now, cancellationToken);
        }

        var result = new SyncBatchResultDto
        {
            IdempotencyKey = batch.IdempotencyKey,
            Status = "applied",
            PayloadHash = payloadHash,
            AcceptedAtUtc = now.UtcDateTime,
            HourlyBinsUpserted = batch.HourlyBins.Count,
            DailySummariesUpserted = batch.DailySummaries.Count,
            ExerciseSessionsUpserted = batch.ExerciseSessions.Count,
            FatigueAssessmentsUpserted = batch.FatigueAssessments.Count,
            HourlyBinsDeleted = hourlyDeleted,
            DailySummariesDeleted = dailyDeleted,
            ExerciseSessionsDeleted = exerciseDeleted
        };

        var resultJson = JsonSerializer.Serialize(result, ResultJsonOptions);
        await _upsert.StoreBatchResultAsync(connection, npgsqlTransaction, insertedId.Value, resultJson, cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        _logger.LogInformation(
            "Sync batch applied. UserId={UserId} DeviceId={DeviceId} IdempotencyKey={IdempotencyKey} SchemaVersion={SchemaVersion} PayloadHash={PayloadHash} Hourly={Hourly} Daily={Daily} Exercises={Exercises} Assessments={Assessments}",
            userId,
            batch.DeviceId,
            batch.IdempotencyKey,
            batch.SchemaVersion,
            payloadHash,
            result.HourlyBinsUpserted,
            result.DailySummariesUpserted,
            result.ExerciseSessionsUpserted,
            result.FatigueAssessmentsUpserted);

        return result;
    }
}
