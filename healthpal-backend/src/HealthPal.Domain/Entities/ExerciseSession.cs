namespace HealthPal.Domain.Entities;

public sealed class ExerciseSession
{
    public Guid Id { get; set; }
    public string UserId { get; set; } = string.Empty;
    public string ExternalRecordId { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public DateTime StartUtc { get; set; }
    public DateTime EndUtc { get; set; }
    public int ZoneOffsetMinutes { get; set; }
    public int DurationMinutes { get; set; }
    public double? Calories { get; set; }
    public string SourceId { get; set; } = string.Empty;
}
