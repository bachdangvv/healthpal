using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using HealthPal.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace HealthPal.Infrastructure.Training;

public sealed class TrainingService : ITrainingService
{
    private readonly HealthPalDbContext _db;

    public TrainingService(HealthPalDbContext db)
    {
        _db = db;
    }

    public async Task<TrainingReadinessDto> GetReadinessAsync(
        string userId,
        DateOnly localDate,
        CancellationToken cancellationToken)
    {
        var summary = await _db.DailyHealthSummaries.AsNoTracking()
            .SingleOrDefaultAsync(x => x.UserId == userId && x.LocalDate == localDate, cancellationToken);
        var assessment = await _db.FatigueAssessments.AsNoTracking()
            .Where(x => x.UserId == userId && x.LocalDate == localDate)
            .OrderByDescending(x => x.EvaluatedAtUtc)
            .ThenByDescending(x => x.Id)
            .FirstOrDefaultAsync(cancellationToken);

        var stress = ToStress(assessment?.CalibratedProbability, assessment?.Status);
        var sleep = summary?.SleepMinutes;
        var steps = summary?.Steps;
        var calories = summary?.ActiveCalories;
        var status = "insufficientData";
        var movementAdjusted = false;

        if (stress is not null && sleep is not null)
        {
            status = stress == "high" && sleep < 300
                ? "rest"
                : stress == "high" || sleep < 360
                    ? "recovery"
                    : stress == "medium" || sleep < 420
                        ? "moderate"
                        : "ready";

            var lowMovement = (steps is not null && steps < 3000) ||
                              (calories is not null && calories < 150);
            if (lowMovement && status != "rest")
            {
                var adjusted = status switch
                {
                    "ready" => "moderate",
                    "moderate" => "recovery",
                    _ => status
                };
                movementAdjusted = adjusted != status;
                status = adjusted;
            }
        }

        return new TrainingReadinessDto
        {
            LocalDate = localDate,
            Stress = stress,
            SleepMinutes = sleep,
            Steps = steps,
            ActiveCalories = calories,
            CollectedAtUtc = assessment?.LatestSampleAtUtc ?? assessment?.EvaluatedAtUtc ?? localDate.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc),
            Status = status,
            Suggestion = Suggestion(status),
            MovementAdjusted = movementAdjusted
        };
    }

    public async Task<IReadOnlyList<ExerciseCatalogItemDto>> GetExercisesAsync(
        string userId,
        string? muscleGroup,
        string? query,
        CancellationToken cancellationToken)
    {
        var exercises = _db.ExerciseCatalogItems.AsNoTracking().Where(x => x.IsActive);
        if (!string.IsNullOrWhiteSpace(muscleGroup) && !string.Equals(muscleGroup, "all", StringComparison.OrdinalIgnoreCase))
            exercises = exercises.Where(x => x.MuscleGroup == muscleGroup.ToLower());
        if (!string.IsNullOrWhiteSpace(query))
            exercises = exercises.Where(x => x.Name.ToLower().Contains(query.ToLower()) || (x.EnglishName != null && x.EnglishName.ToLower().Contains(query.ToLower())));

        var favoriteIds = (await _db.UserExerciseFavorites.AsNoTracking()
            .Where(x => x.UserId == userId)
            .Select(x => x.ExerciseId)
            .ToListAsync(cancellationToken)).ToHashSet();

        return await exercises.OrderBy(x => x.Name).Select(x => new ExerciseCatalogItemDto
        {
            Id = x.Id,
            Name = x.Name,
            EnglishName = x.EnglishName,
            MuscleGroup = x.MuscleGroup,
            ExerciseType = x.ExerciseType,
            Equipment = x.Equipment,
            Instructions = x.Instructions,
            Favorite = favoriteIds.Contains(x.Id)
        }).ToListAsync(cancellationToken);
    }

    public async Task SetFavoriteAsync(string userId, string exerciseId, bool favorite, CancellationToken cancellationToken)
    {
        var exists = await _db.ExerciseCatalogItems.AnyAsync(x => x.Id == exerciseId && x.IsActive, cancellationToken);
        if (!exists) throw new KeyNotFoundException("Exercise was not found.");

        var current = await _db.UserExerciseFavorites.FindAsync([userId, exerciseId], cancellationToken);
        if (favorite && current is null)
            _db.UserExerciseFavorites.Add(new() { UserId = userId, ExerciseId = exerciseId, CreatedAtUtc = DateTime.UtcNow });
        else if (!favorite && current is not null)
            _db.UserExerciseFavorites.Remove(current);
        await _db.SaveChangesAsync(cancellationToken);
    }

    private static string? ToStress(double? probability, HealthPal.Domain.FatigueAssessmentStatus? status)
    {
        if (probability is null && status is null) return null;
        if (probability >= 0.7 || status == HealthPal.Domain.FatigueAssessmentStatus.SignalDetected) return "high";
        if (probability >= 0.4) return "medium";
        return "low";
    }

    private static string Suggestion(string status) => status switch
    {
        "ready" => "Có thể tập theo kế hoạch bình thường.",
        "moderate" => "Giảm cường độ hoặc volume, ưu tiên buổi tập vừa.",
        "recovery" => "Ưu tiên đi bộ, mobility, stretching hoặc cardio nhẹ.",
        "rest" => "Ưu tiên nghỉ ngơi và phục hồi hôm nay.",
        _ => "Chưa đưa ra kết luận khi còn thiếu dữ liệu cốt lõi."
    };
}
