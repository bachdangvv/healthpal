namespace HealthPal.Domain.Entities;

public sealed class ExerciseCatalogItem
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? EnglishName { get; set; }
    public string MuscleGroup { get; set; } = string.Empty;
    public string ExerciseType { get; set; } = string.Empty;
    public string Equipment { get; set; } = string.Empty;
    public string Instructions { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
}
