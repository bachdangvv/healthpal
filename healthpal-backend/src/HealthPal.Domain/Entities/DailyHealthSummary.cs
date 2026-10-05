namespace HealthPal.Domain.Entities;

public sealed class DailyHealthSummary
{
    public Guid Id { get; set; }
    public string UserId { get; set; } = string.Empty;
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
    public DateTimeOffset UpdatedAt { get; set; }
}
