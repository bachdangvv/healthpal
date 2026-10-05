using System.Data;
using System.Text.Json;
using HealthPal.Application.Contracts;
using Npgsql;
using NpgsqlTypes;

namespace HealthPal.Infrastructure.Sync;

public class HealthUpsertExecutor
{
    private static readonly JsonSerializerOptions JsonOptions = new();

    public async Task<int> DeleteHourlyWindowAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        DateTime startUtc,
        DateTime endUtcExclusive,
        CancellationToken cancellationToken)
    {
        const string sql = """
            DELETE FROM hourly_health_bins
            WHERE user_id = @user_id
              AND hour_utc >= @start
              AND hour_utc < @end
            """;
        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("start", DateTime.SpecifyKind(startUtc.ToUniversalTime(), DateTimeKind.Utc));
        cmd.Parameters.AddWithValue("end", DateTime.SpecifyKind(endUtcExclusive.ToUniversalTime(), DateTimeKind.Utc));
        return await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<int> DeleteDailyWindowAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        DateOnly localDateStart,
        DateOnly localDateEndExclusive,
        CancellationToken cancellationToken)
    {
        const string sql = """
            DELETE FROM daily_health_summaries
            WHERE user_id = @user_id
              AND local_date >= @date_start
              AND local_date < @date_end
            """;
        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("date_start", localDateStart);
        cmd.Parameters.AddWithValue("date_end", localDateEndExclusive);
        return await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<int> DeleteExerciseWindowAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        DateTime startUtc,
        DateTime endUtcExclusive,
        CancellationToken cancellationToken)
    {
        const string sql = """
            DELETE FROM exercise_sessions
            WHERE user_id = @user_id
              AND end_utc > @start
              AND start_utc < @end
            """;
        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("start", DateTime.SpecifyKind(startUtc.ToUniversalTime(), DateTimeKind.Utc));
        cmd.Parameters.AddWithValue("end", DateTime.SpecifyKind(endUtcExclusive.ToUniversalTime(), DateTimeKind.Utc));
        return await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    public virtual async Task UpsertHourlyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        HourlyHealthBinDto bin,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO hourly_health_bins (
                id, user_id, hour_utc, zone_offset_minutes, hr_mean, hr_min, hr_max,
                hr_sample_count, steps, active_calories, source_id, updated_at)
            VALUES (
                @id, @user_id, @hour_utc, @zone_offset_minutes, @hr_mean, @hr_min, @hr_max,
                @hr_sample_count, @steps, @active_calories, @source_id, @updated_at)
            ON CONFLICT (user_id, hour_utc, source_id)
            DO UPDATE SET
                zone_offset_minutes = EXCLUDED.zone_offset_minutes,
                hr_mean = EXCLUDED.hr_mean,
                hr_min = EXCLUDED.hr_min,
                hr_max = EXCLUDED.hr_max,
                hr_sample_count = EXCLUDED.hr_sample_count,
                steps = EXCLUDED.steps,
                active_calories = EXCLUDED.active_calories,
                updated_at = EXCLUDED.updated_at
            """;

        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("id", Guid.NewGuid());
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("hour_utc", DateTime.SpecifyKind(bin.HourUtc.ToUniversalTime(), DateTimeKind.Utc));
        cmd.Parameters.AddWithValue("zone_offset_minutes", bin.ZoneOffsetMinutes);
        cmd.Parameters.AddWithValue("hr_mean", (object?)bin.HrMean ?? DBNull.Value);
        cmd.Parameters.AddWithValue("hr_min", (object?)bin.HrMin ?? DBNull.Value);
        cmd.Parameters.AddWithValue("hr_max", (object?)bin.HrMax ?? DBNull.Value);
        cmd.Parameters.AddWithValue("hr_sample_count", bin.HrSampleCount);
        cmd.Parameters.AddWithValue("steps", (object?)bin.Steps ?? DBNull.Value);
        cmd.Parameters.AddWithValue("active_calories", (object?)bin.ActiveCalories ?? DBNull.Value);
        cmd.Parameters.AddWithValue("source_id", bin.SourceId);
        cmd.Parameters.AddWithValue("updated_at", now);
        await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task UpsertDailyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        DailyHealthSummaryDto summary,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO daily_health_summaries (
                id, user_id, local_date, timezone, sleep_minutes, steps, average_heart_rate,
                min_heart_rate, max_heart_rate, resting_heart_rate, active_calories,
                exercise_count, exercise_duration_minutes, coverage_flags, updated_at)
            VALUES (
                @id, @user_id, @local_date, @timezone, @sleep_minutes, @steps, @average_heart_rate,
                @min_heart_rate, @max_heart_rate, @resting_heart_rate, @active_calories,
                @exercise_count, @exercise_duration_minutes, @coverage_flags, @updated_at)
            ON CONFLICT (user_id, local_date)
            DO UPDATE SET
                timezone = EXCLUDED.timezone,
                sleep_minutes = EXCLUDED.sleep_minutes,
                steps = EXCLUDED.steps,
                average_heart_rate = EXCLUDED.average_heart_rate,
                min_heart_rate = EXCLUDED.min_heart_rate,
                max_heart_rate = EXCLUDED.max_heart_rate,
                resting_heart_rate = EXCLUDED.resting_heart_rate,
                active_calories = EXCLUDED.active_calories,
                exercise_count = EXCLUDED.exercise_count,
                exercise_duration_minutes = EXCLUDED.exercise_duration_minutes,
                coverage_flags = EXCLUDED.coverage_flags,
                updated_at = EXCLUDED.updated_at
            """;

        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("id", Guid.NewGuid());
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("local_date", summary.LocalDate);
        cmd.Parameters.AddWithValue("timezone", summary.Timezone);
        cmd.Parameters.AddWithValue("sleep_minutes", (object?)summary.SleepMinutes ?? DBNull.Value);
        cmd.Parameters.AddWithValue("steps", (object?)summary.Steps ?? DBNull.Value);
        cmd.Parameters.AddWithValue("average_heart_rate", (object?)summary.AverageHeartRate ?? DBNull.Value);
        cmd.Parameters.AddWithValue("min_heart_rate", (object?)summary.MinHeartRate ?? DBNull.Value);
        cmd.Parameters.AddWithValue("max_heart_rate", (object?)summary.MaxHeartRate ?? DBNull.Value);
        cmd.Parameters.AddWithValue("resting_heart_rate", (object?)summary.RestingHeartRate ?? DBNull.Value);
        cmd.Parameters.AddWithValue("active_calories", (object?)summary.ActiveCalories ?? DBNull.Value);
        cmd.Parameters.AddWithValue("exercise_count", summary.ExerciseCount);
        cmd.Parameters.AddWithValue("exercise_duration_minutes", summary.ExerciseDurationMinutes);
        cmd.Parameters.AddWithValue("coverage_flags", NpgsqlDbType.Jsonb, JsonSerializer.Serialize(summary.CoverageFlags, JsonOptions));
        cmd.Parameters.AddWithValue("updated_at", now);
        await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task UpsertExerciseAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        ExerciseSessionDto session,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO exercise_sessions (
                id, user_id, external_record_id, type, start_utc, end_utc,
                zone_offset_minutes, duration_minutes, calories, source_id)
            VALUES (
                @id, @user_id, @external_record_id, @type, @start_utc, @end_utc,
                @zone_offset_minutes, @duration_minutes, @calories, @source_id)
            ON CONFLICT (user_id, external_record_id)
            DO UPDATE SET
                type = EXCLUDED.type,
                start_utc = EXCLUDED.start_utc,
                end_utc = EXCLUDED.end_utc,
                zone_offset_minutes = EXCLUDED.zone_offset_minutes,
                duration_minutes = EXCLUDED.duration_minutes,
                calories = EXCLUDED.calories,
                source_id = EXCLUDED.source_id
            """;

        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("id", Guid.NewGuid());
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("external_record_id", session.ExternalRecordId);
        cmd.Parameters.AddWithValue("type", session.Type);
        cmd.Parameters.AddWithValue("start_utc", DateTime.SpecifyKind(session.StartUtc.ToUniversalTime(), DateTimeKind.Utc));
        cmd.Parameters.AddWithValue("end_utc", DateTime.SpecifyKind(session.EndUtc.ToUniversalTime(), DateTimeKind.Utc));
        cmd.Parameters.AddWithValue("zone_offset_minutes", session.ZoneOffsetMinutes);
        cmd.Parameters.AddWithValue("duration_minutes", session.DurationMinutes);
        cmd.Parameters.AddWithValue("calories", (object?)session.Calories ?? DBNull.Value);
        cmd.Parameters.AddWithValue("source_id", session.SourceId);
        await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task UpsertAssessmentAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        FatigueAssessmentDto assessment,
        bool storeFeatureVector,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO fatigue_assessments (
                id, user_id, evaluated_at_utc, local_date, model_version, base_probability,
                calibrated_probability, threshold, status, coverage_hours, latest_sample_at_utc,
                data_freshness_minutes, missing_reasons, feature_vector_hash, feature_vector_json,
                created_by, created_at)
            VALUES (
                @id, @user_id, @evaluated_at_utc, @local_date, @model_version, @base_probability,
                @calibrated_probability, @threshold, @status, @coverage_hours, @latest_sample_at_utc,
                @data_freshness_minutes, @missing_reasons, @feature_vector_hash, @feature_vector_json,
                @created_by, @created_at)
            ON CONFLICT (user_id, evaluated_at_utc, model_version)
            DO UPDATE SET
                local_date = EXCLUDED.local_date,
                base_probability = EXCLUDED.base_probability,
                calibrated_probability = EXCLUDED.calibrated_probability,
                threshold = EXCLUDED.threshold,
                status = EXCLUDED.status,
                coverage_hours = EXCLUDED.coverage_hours,
                latest_sample_at_utc = EXCLUDED.latest_sample_at_utc,
                data_freshness_minutes = EXCLUDED.data_freshness_minutes,
                missing_reasons = EXCLUDED.missing_reasons,
                feature_vector_hash = EXCLUDED.feature_vector_hash,
                feature_vector_json = EXCLUDED.feature_vector_json,
                created_by = EXCLUDED.created_by
            """;

        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("id", assessment.Id);
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("evaluated_at_utc", DateTime.SpecifyKind(assessment.EvaluatedAtUtc.ToUniversalTime(), DateTimeKind.Utc));
        cmd.Parameters.AddWithValue("local_date", assessment.LocalDate);
        cmd.Parameters.AddWithValue("model_version", assessment.ModelVersion);
        cmd.Parameters.AddWithValue("base_probability", (object?)assessment.BaseProbability ?? DBNull.Value);
        cmd.Parameters.AddWithValue("calibrated_probability", (object?)assessment.CalibratedProbability ?? DBNull.Value);
        cmd.Parameters.AddWithValue("threshold", assessment.Threshold);
        cmd.Parameters.AddWithValue("status", assessment.Status.ToString());
        cmd.Parameters.AddWithValue("coverage_hours", assessment.CoverageHours);
        cmd.Parameters.AddWithValue(
            "latest_sample_at_utc",
            assessment.LatestSampleAtUtc is { } sample
                ? DateTime.SpecifyKind(sample.ToUniversalTime(), DateTimeKind.Utc)
                : DBNull.Value);
        cmd.Parameters.AddWithValue("data_freshness_minutes", (object?)assessment.DataFreshnessMinutes ?? DBNull.Value);
        cmd.Parameters.AddWithValue("missing_reasons", NpgsqlDbType.Jsonb, JsonSerializer.Serialize(assessment.MissingReasons, JsonOptions));
        cmd.Parameters.AddWithValue("feature_vector_hash", assessment.FeatureVectorHash);
        cmd.Parameters.AddWithValue(
            "feature_vector_json",
            storeFeatureVector ? (object?)assessment.FeatureVectorJson ?? DBNull.Value : DBNull.Value);
        cmd.Parameters.AddWithValue("created_by", assessment.CreatedBy.ToString());
        cmd.Parameters.AddWithValue("created_at", now);
        await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task UpsertDeviceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        string deviceId,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO devices (user_id, id, platform, last_seen_at)
            VALUES (@user_id, @id, 'android', @last_seen_at)
            ON CONFLICT (user_id, id)
            DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at
            """;

        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("id", deviceId);
        cmd.Parameters.AddWithValue("last_seen_at", now);
        await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<Guid?> TryInsertBatchAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        SyncBatchDto batch,
        string payloadHash,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO sync_batches (
                id, user_id, device_id, idempotency_key, schema_version, generated_at_utc,
                status, payload_hash, result_json, created_at)
            VALUES (
                @id, @user_id, @device_id, @idempotency_key, @schema_version, @generated_at_utc,
                'Applied', @payload_hash, '{}', @created_at)
            ON CONFLICT (user_id, device_id, idempotency_key) DO NOTHING
            RETURNING id
            """;

        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        var id = Guid.NewGuid();
        cmd.Parameters.AddWithValue("id", id);
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("device_id", batch.DeviceId);
        cmd.Parameters.AddWithValue("idempotency_key", batch.IdempotencyKey);
        cmd.Parameters.AddWithValue("schema_version", batch.SchemaVersion);
        cmd.Parameters.AddWithValue("generated_at_utc", DateTime.SpecifyKind(batch.GeneratedAtUtc.ToUniversalTime(), DateTimeKind.Utc));
        cmd.Parameters.AddWithValue("payload_hash", payloadHash);
        cmd.Parameters.AddWithValue("created_at", now);
        var result = await cmd.ExecuteScalarAsync(cancellationToken);
        return result is Guid guid ? guid : result is null || result is DBNull ? null : (Guid)result;
    }

    public async Task<SyncBatchLookup?> FindBatchAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string userId,
        string deviceId,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT payload_hash, result_json, created_at
            FROM sync_batches
            WHERE user_id = @user_id AND device_id = @device_id AND idempotency_key = @idempotency_key
            """;

        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("device_id", deviceId);
        cmd.Parameters.AddWithValue("idempotency_key", idempotencyKey);
        await using var reader = await cmd.ExecuteReaderAsync(CommandBehavior.SingleRow, cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new SyncBatchLookup(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetFieldValue<DateTimeOffset>(2));
    }

    public async Task StoreBatchResultAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid batchId,
        string resultJson,
        CancellationToken cancellationToken)
    {
        const string sql = "UPDATE sync_batches SET result_json = @result_json WHERE id = @id";
        await using var cmd = new NpgsqlCommand(sql, connection, transaction);
        cmd.Parameters.AddWithValue("id", batchId);
        cmd.Parameters.AddWithValue("result_json", NpgsqlDbType.Jsonb, resultJson);
        await cmd.ExecuteNonQueryAsync(cancellationToken);
    }
}

public sealed record SyncBatchLookup(string PayloadHash, string ResultJson, DateTimeOffset CreatedAt);
