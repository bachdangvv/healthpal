using System.ComponentModel.DataAnnotations;

namespace HealthPal.Application.Contracts;

public sealed class ProfileDto
{
    public required string UserId { get; init; }
    public required string DisplayName { get; init; }
    public string? Email { get; init; }
    public DateOnly? BirthDate { get; init; }
    public string? Gender { get; init; }
    public double? HeightCm { get; init; }
    public double? WeightKg { get; init; }
    public string? Goal { get; init; }
    public int DailyStepGoal { get; init; } = 8000;
    public string? Timezone { get; init; }
    public string? PreferredSourceId { get; init; }
    public string? RowVersion { get; init; }
    public bool ExperimentalFatigueConsent { get; init; }
}

public sealed class UpdateProfileRequest
{
    [StringLength(100, MinimumLength = 1)]
    public string? DisplayName { get; set; }

    public DateOnly? BirthDate { get; set; }

    [StringLength(32)]
    public string? Gender { get; set; }

    public double? HeightCm { get; set; }

    public double? WeightKg { get; set; }

    [StringLength(64)]
    public string? Goal { get; set; }

    public int? DailyStepGoal { get; set; }

    [StringLength(64)]
    public string? Timezone { get; set; }

    [StringLength(256)]
    public string? PreferredSourceId { get; set; }

    public bool? ExperimentalFatigueConsent { get; set; }

    [Required]
    public string RowVersion { get; set; } = string.Empty;
}

public sealed class UpdatePreferencesRequest
{
    [StringLength(64)]
    public string? Goal { get; set; }

    public int? DailyStepGoal { get; set; }

    public bool? ExperimentalFatigueConsent { get; set; }

    [StringLength(256)]
    public string? PreferredSourceId { get; set; }

    [Required]
    public string RowVersion { get; set; } = string.Empty;
}
