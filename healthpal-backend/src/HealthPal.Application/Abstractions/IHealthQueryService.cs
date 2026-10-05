using HealthPal.Application.Contracts;

namespace HealthPal.Application.Abstractions;

public interface IHealthQueryService
{
    Task<DashboardTodayDto> GetDashboardTodayAsync(
        string userId,
        DateOnly localDate,
        string? timezone,
        CancellationToken cancellationToken);

    Task<FatigueAssessmentDto?> GetLatestAssessmentAsync(string userId, CancellationToken cancellationToken);

    Task<IReadOnlyList<DailyHealthSummaryDto>> GetHistoryAsync(
        string userId,
        DateOnly from,
        DateOnly to,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<ExerciseSessionDto>> GetExercisesAsync(
        string userId,
        DateOnly from,
        DateOnly to,
        CancellationToken cancellationToken);
}
