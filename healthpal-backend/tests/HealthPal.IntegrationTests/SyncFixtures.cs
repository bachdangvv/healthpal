using HealthPal.Application.Contracts;
using HealthPal.Domain;

namespace HealthPal.IntegrationTests;

internal static class SyncFixtures
{
    public static SyncBatchDto CreateBatch(
        string? deviceId = null,
        string? idempotencyKey = null,
        DateOnly? localDate = null,
        int? steps = 100,
        int? sleepMinutes = 420,
        string sourceId = "health_sync",
        DateTime? hourUtc = null,
        int zoneOffsetMinutes = 0,
        FatigueAssessmentDto? assessment = null,
        ExerciseSessionDto? exercise = null)
    {
        var date = localDate ?? new DateOnly(2026, 3, 15);
        var hour = hourUtc ?? new DateTime(2026, 3, 15, 1, 0, 0, DateTimeKind.Utc);
        return new SyncBatchDto
        {
            SchemaVersion = 1,
            DeviceId = deviceId ?? "device-1",
            IdempotencyKey = idempotencyKey ?? Guid.NewGuid().ToString("N"),
            GeneratedAtUtc = new DateTime(2026, 3, 15, 8, 0, 0, DateTimeKind.Utc),
            HourlyBins =
            [
                new HourlyHealthBinDto
                {
                    HourUtc = hour,
                    ZoneOffsetMinutes = zoneOffsetMinutes,
                    HrMean = 72,
                    HrMin = 60,
                    HrMax = 90,
                    HrSampleCount = 12,
                    Steps = steps,
                    ActiveCalories = 15.5,
                    SourceId = sourceId
                }
            ],
            DailySummaries =
            [
                new DailyHealthSummaryDto
                {
                    LocalDate = date,
                    Timezone = "Asia/Ho_Chi_Minh",
                    SleepMinutes = sleepMinutes,
                    Steps = steps,
                    AverageHeartRate = 72,
                    MinHeartRate = 60,
                    MaxHeartRate = 90,
                    RestingHeartRate = 58,
                    ActiveCalories = 240,
                    ExerciseCount = exercise is null ? 0 : 1,
                    ExerciseDurationMinutes = exercise?.DurationMinutes ?? 0,
                    CoverageFlags = new Dictionary<string, bool>
                    {
                        ["heartRate"] = true,
                        ["steps"] = steps is not null
                    }
                }
            ],
            ExerciseSessions = exercise is null ? [] : [exercise],
            FatigueAssessments = assessment is null ? [] : [assessment]
        };
    }

    public static ReplacementWindowDto Window(
        DateTime? startUtc = null,
        DateTime? endUtcExclusive = null,
        DateOnly? localDateStart = null,
        DateOnly? localDateEndExclusive = null) =>
        new()
        {
            StartUtc = startUtc ?? new DateTime(2026, 3, 14, 0, 0, 0, DateTimeKind.Utc),
            EndUtcExclusive = endUtcExclusive ?? new DateTime(2026, 3, 16, 0, 0, 0, DateTimeKind.Utc),
            LocalDateStart = localDateStart ?? new DateOnly(2026, 3, 14),
            LocalDateEndExclusive = localDateEndExclusive ?? new DateOnly(2026, 3, 16)
        };

    public static SyncBatchDto CreateV2Batch(
        string? deviceId = null,
        string? idempotencyKey = null,
        DateOnly? localDate = null,
        int? steps = 100,
        int? sleepMinutes = 420,
        string sourceId = "health_sync",
        DateTime? hourUtc = null,
        int zoneOffsetMinutes = 0,
        FatigueAssessmentDto? assessment = null,
        ExerciseSessionDto? exercise = null,
        ReplacementWindowDto? window = null)
    {
        var batch = CreateBatch(
            deviceId: deviceId,
            idempotencyKey: idempotencyKey,
            localDate: localDate,
            steps: steps,
            sleepMinutes: sleepMinutes,
            sourceId: sourceId,
            hourUtc: hourUtc,
            zoneOffsetMinutes: zoneOffsetMinutes,
            assessment: assessment,
            exercise: exercise);
        batch.SchemaVersion = HealthPalConstants.SyncSchemaVersionV2;
        batch.ReplacementWindow = window ?? Window();
        return batch;
    }

    public static FatigueAssessmentDto Assessment(
        string? id = null,
        DateOnly? localDate = null,
        double? probability = 0.4,
        FatigueAssessmentStatus status = FatigueAssessmentStatus.SignalDetected) =>
        new()
        {
            Id = id ?? Guid.NewGuid().ToString("N"),
            EvaluatedAtUtc = new DateTime(2026, 3, 15, 8, 0, 0, DateTimeKind.Utc),
            LocalDate = localDate ?? new DateOnly(2026, 3, 15),
            ModelVersion = HealthPalConstants.FatigueModelVersion,
            BaseProbability = probability,
            CalibratedProbability = probability,
            Threshold = 0.18170608515558545,
            Status = status,
            CoverageHours = 4,
            LatestSampleAtUtc = new DateTime(2026, 3, 15, 7, 50, 0, DateTimeKind.Utc),
            DataFreshnessMinutes = 10,
            MissingReasons = [],
            FeatureVectorHash = "abc123",
            CreatedBy = AssessmentCreatedBy.Foreground
        };
}
