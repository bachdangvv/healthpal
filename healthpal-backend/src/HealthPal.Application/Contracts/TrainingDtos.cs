namespace HealthPal.Application.Contracts;

public sealed class TrainingReadinessDto
{
    public DateOnly LocalDate { get; init; }
    public string? Stress { get; init; }
    public int? SleepMinutes { get; init; }
    public int? Steps { get; init; }
    public double? ActiveCalories { get; init; }
    public DateTime CollectedAtUtc { get; init; }
    public string Status { get; init; } = "insufficientData";
    public string Suggestion { get; init; } = string.Empty;
    public bool MovementAdjusted { get; init; }
}

public sealed class ExerciseCatalogItemDto
{
    public string Id { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string? EnglishName { get; init; }
    public string MuscleGroup { get; init; } = string.Empty;
    public string ExerciseType { get; init; } = string.Empty;
    public string Equipment { get; init; } = string.Empty;
    public string Instructions { get; init; } = string.Empty;
    public bool Favorite { get; init; }
}

public sealed class SetExerciseFavoriteRequest
{
    public bool Favorite { get; init; }
}
