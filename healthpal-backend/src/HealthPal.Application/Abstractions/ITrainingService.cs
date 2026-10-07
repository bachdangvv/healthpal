using HealthPal.Application.Contracts;

namespace HealthPal.Application.Abstractions;

public interface ITrainingService
{
    Task<TrainingReadinessDto> GetReadinessAsync(
        string userId,
        DateOnly localDate,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ExerciseCatalogItemDto>> GetExercisesAsync(
        string userId,
        string? muscleGroup,
        string? query,
        CancellationToken cancellationToken);

    Task SetFavoriteAsync(
        string userId,
        string exerciseId,
        bool favorite,
        CancellationToken cancellationToken);
}
