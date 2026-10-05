namespace HealthPal.Domain.Entities;

public sealed class HourlyHealthBin
{
    public Guid Id { get; set; }
    public string UserId { get; set; } = string.Empty;
    public DateTime HourUtc { get; set; }
    public int ZoneOffsetMinutes { get; set; }
    public double? HrMean { get; set; }
    public double? HrMin { get; set; }
    public double? HrMax { get; set; }
    public int HrSampleCount { get; set; }
    public int? Steps { get; set; }
    public double? ActiveCalories { get; set; }
    public string SourceId { get; set; } = string.Empty;
    public DateTimeOffset UpdatedAt { get; set; }
}
