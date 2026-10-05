namespace HealthPal.Domain.Entities;

public sealed class UserProfile
{
    public string UserId { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public DateOnly? BirthDate { get; set; }
    public string? Gender { get; set; }
    public double? HeightCm { get; set; }
    public double? WeightKg { get; set; }
    public string? Goal { get; set; }
    public int DailyStepGoal { get; set; } = 8000;
    public string? Timezone { get; set; }
    public string? PreferredSourceId { get; set; }
    public bool ExperimentalFatigueConsent { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public uint RowVersion { get; set; }
}
