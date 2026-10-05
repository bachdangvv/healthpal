namespace HealthPal.Domain.Entities;

public sealed class FatigueAssessment
{
    public string Id { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;
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
    public string? FeatureVectorJson { get; set; }
    public AssessmentCreatedBy CreatedBy { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}
