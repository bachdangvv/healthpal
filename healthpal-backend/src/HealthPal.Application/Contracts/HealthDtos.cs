using HealthPal.Domain;

namespace HealthPal.Application.Contracts;

public sealed class HourlyHealthBinDto
{
    public DateTime HourUtc { get; set; }
    public int ZoneOffsetMinutes { get; set; }
    public double? HrMean { get; set; }
    public double? HrMin { get; set; }
    public double? HrMax { get; set; }
    public int HrSampleCount { get; set; }
    public int? Steps { get; set; }
    public double? ActiveCalories { get; set; }
    public string SourceId { get; set; } = string.Empty;
}

public sealed class FatigueDailyValueDto
{
    public double? Probability { get; set; }
    public FatigueAssessmentStatus Status { get; set; }
    public DateTime EvaluatedAtUtc { get; set; }
}

public sealed class DailyHealthSummaryDto
{
    public DateOnly LocalDate { get; set; }
    public string Timezone { get; set; } = "UTC";
    public int? SleepMinutes { get; set; }
    public int? Steps { get; set; }
    public double? AverageHeartRate { get; set; }
    public double? MinHeartRate { get; set; }
    public double? MaxHeartRate { get; set; }
    public double? RestingHeartRate { get; set; }
    public double? ActiveCalories { get; set; }
    public int ExerciseCount { get; set; }
    public int ExerciseDurationMinutes { get; set; }
    public Dictionary<string, bool> CoverageFlags { get; set; } = new();
    public FatigueDailyValueDto? Fatigue { get; set; }
}

public sealed class ExerciseSessionDto
{
    public string ExternalRecordId { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public DateTime StartUtc { get; set; }
    public DateTime EndUtc { get; set; }
    public int ZoneOffsetMinutes { get; set; }
    public int DurationMinutes { get; set; }
    public double? Calories { get; set; }
    public string SourceId { get; set; } = string.Empty;
}

public sealed class FatigueAssessmentDto
{
    public string Id { get; set; } = string.Empty;
    public DateTime EvaluatedAtUtc { get; set; }
    public DateOnly LocalDate { get; set; }
    public string ModelVersion { get; set; } = string.Empty;
    public double? BaseProbability { get; set; }
    public double? CalibratedProbability { get; set; }
    public double Threshold { get; set; }
    public FatigueAssessmentStatus Status { get; set; }
    public int CoverageHours { get; set; }
    public DateTime? LatestSampleAtUtc { get; set; }
    public int? DataFreshnessMinutes { get; set; }
    public List<string> MissingReasons { get; set; } = [];
    public string FeatureVectorHash { get; set; } = string.Empty;
    public AssessmentCreatedBy CreatedBy { get; set; }
    public string? FeatureVectorJson { get; set; }
}

public sealed class ReplacementWindowDto
{
    public DateTime StartUtc { get; set; }
    public DateTime EndUtcExclusive { get; set; }
    public DateOnly LocalDateStart { get; set; }
    public DateOnly LocalDateEndExclusive { get; set; }
}

public sealed class SyncBatchDto
{
    public int SchemaVersion { get; set; } = 1;
    public string DeviceId { get; set; } = string.Empty;
    public string IdempotencyKey { get; set; } = string.Empty;
    public DateTime GeneratedAtUtc { get; set; }
    public List<HourlyHealthBinDto> HourlyBins { get; set; } = [];
    public List<DailyHealthSummaryDto> DailySummaries { get; set; } = [];
    public List<ExerciseSessionDto> ExerciseSessions { get; set; } = [];
    public List<FatigueAssessmentDto> FatigueAssessments { get; set; } = [];
    public ReplacementWindowDto? ReplacementWindow { get; set; }
}

public sealed class SyncBatchResultDto
{
    public required string IdempotencyKey { get; init; }
    public required string Status { get; init; }
    public required string PayloadHash { get; init; }
    public required DateTime AcceptedAtUtc { get; init; }
    public int HourlyBinsUpserted { get; init; }
    public int DailySummariesUpserted { get; init; }
    public int ExerciseSessionsUpserted { get; init; }
    public int FatigueAssessmentsUpserted { get; init; }
    public int HourlyBinsDeleted { get; init; }
    public int DailySummariesDeleted { get; init; }
    public int ExerciseSessionsDeleted { get; init; }
}

public sealed class DashboardTodayDto
{
    public DateOnly LocalDate { get; set; }
    public DailyHealthSummaryDto? Summary { get; set; }
    public FatigueAssessmentDto? LatestAssessment { get; set; }
    public DateTime? LatestSampleAtUtc { get; set; }
    public DateTime? ServerSyncedAtUtc { get; set; }
}
