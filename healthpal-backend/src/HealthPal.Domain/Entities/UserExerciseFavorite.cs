namespace HealthPal.Domain.Entities;

public sealed class UserExerciseFavorite
{
    public string UserId { get; set; } = string.Empty;
    public string ExerciseId { get; set; } = string.Empty;
    public DateTime CreatedAtUtc { get; set; }
}
