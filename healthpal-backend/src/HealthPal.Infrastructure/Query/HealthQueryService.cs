using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using HealthPal.Application.Exceptions;
using HealthPal.Domain;
using HealthPal.Domain.Entities;
using HealthPal.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using TimeZoneConverter;

namespace HealthPal.Infrastructure.Query;

public sealed class HealthQueryService : IHealthQueryService
{
    private readonly HealthPalDbContext _db;

    public HealthQueryService(HealthPalDbContext db)
    {
        _db = db;
    }

    public async Task<DashboardTodayDto> GetDashboardTodayAsync(
        string userId,
        DateOnly localDate,
        string? timezone,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(timezone))
        {
            try
            {
                _ = TZConvert.GetTimeZoneInfo(timezone);
            }
            catch (TimeZoneNotFoundException)
            {
                throw new AppValidationException("timezone", "Timezone must be a valid IANA identifier.");
            }
            catch (InvalidTimeZoneException)
            {
                throw new AppValidationException("timezone", "Timezone must be a valid IANA identifier.");
            }
        }

        var summary = await _db.DailyHealthSummaries.AsNoTracking()
            .SingleOrDefaultAsync(s => s.UserId == userId && s.LocalDate == localDate, cancellationToken);

        var latestAssessment = await _db.FatigueAssessments.AsNoTracking()
            .Where(a => a.UserId == userId)
            .OrderByDescending(a => a.EvaluatedAtUtc)
            .ThenByDescending(a => a.Id)
            .FirstOrDefaultAsync(cancellationToken);

        var dayAssessment = await _db.FatigueAssessments.AsNoTracking()
            .Where(a => a.UserId == userId && a.LocalDate == localDate)
            .OrderByDescending(a => a.EvaluatedAtUtc)
            .ThenByDescending(a => a.Id)
            .FirstOrDefaultAsync(cancellationToken);

        var latestHour = await _db.HourlyHealthBins.AsNoTracking()
            .Where(h => h.UserId == userId)
            .MaxAsync(h => (DateTime?)h.HourUtc, cancellationToken);

        var latestSampleFromAssessments = await _db.FatigueAssessments.AsNoTracking()
            .Where(a => a.UserId == userId)
            .MaxAsync(a => a.LatestSampleAtUtc, cancellationToken);

        var serverSynced = await _db.SyncBatches.AsNoTracking()
            .Where(s => s.UserId == userId)
            .MaxAsync(s => (DateTimeOffset?)s.CreatedAt, cancellationToken);

        DateTime? latestSample = latestHour;
        if (latestSampleFromAssessments is { } sample && (latestSample is null || sample > latestSample))
        {
            latestSample = sample;
        }

        return new DashboardTodayDto
        {
            LocalDate = localDate,
            Summary = summary is null ? null : MapDaily(summary, dayAssessment),
            LatestAssessment = latestAssessment is null ? null : MapAssessment(latestAssessment),
            LatestSampleAtUtc = latestSample,
            ServerSyncedAtUtc = serverSynced?.UtcDateTime
        };
    }

    public async Task<FatigueAssessmentDto?> GetLatestAssessmentAsync(string userId, CancellationToken cancellationToken)
    {
        var latest = await _db.FatigueAssessments.AsNoTracking()
            .Where(a => a.UserId == userId)
            .OrderByDescending(a => a.EvaluatedAtUtc)
            .ThenByDescending(a => a.Id)
            .FirstOrDefaultAsync(cancellationToken);
        return latest is null ? null : MapAssessment(latest);
    }

    public async Task<IReadOnlyList<DailyHealthSummaryDto>> GetHistoryAsync(
        string userId,
        DateOnly from,
        DateOnly to,
        CancellationToken cancellationToken)
    {
        ValidateRange(from, to);
        var summaries = await _db.DailyHealthSummaries.AsNoTracking()
            .Where(s => s.UserId == userId && s.LocalDate >= from && s.LocalDate <= to)
            .OrderBy(s => s.LocalDate)
            .ThenBy(s => s.Id)
            .ToListAsync(cancellationToken);

        var assessments = await _db.FatigueAssessments.AsNoTracking()
            .Where(a => a.UserId == userId && a.LocalDate >= from && a.LocalDate <= to)
            .OrderByDescending(a => a.EvaluatedAtUtc)
            .ThenByDescending(a => a.Id)
            .ToListAsync(cancellationToken);

        var latestByDate = assessments
            .GroupBy(a => a.LocalDate)
            .ToDictionary(g => g.Key, g => g.First());

        return summaries
            .Select(summary => MapDaily(summary, latestByDate.GetValueOrDefault(summary.LocalDate)))
            .ToList();
    }

    public async Task<IReadOnlyList<ExerciseSessionDto>> GetExercisesAsync(
        string userId,
        DateOnly from,
        DateOnly to,
        CancellationToken cancellationToken)
    {
        ValidateRange(from, to);
        var fromUtc = from.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc).AddDays(-1);
        var toUtc = to.ToDateTime(TimeOnly.MaxValue, DateTimeKind.Utc).AddDays(1);

        var sessions = await _db.ExerciseSessions.AsNoTracking()
            .Where(e => e.UserId == userId && e.StartUtc >= fromUtc && e.StartUtc <= toUtc)
            .OrderBy(e => e.StartUtc)
            .ThenBy(e => e.ExternalRecordId)
            .ToListAsync(cancellationToken);

        return sessions
            .Where(session =>
            {
                var local = DateTime.SpecifyKind(session.StartUtc, DateTimeKind.Utc).AddMinutes(session.ZoneOffsetMinutes);
                var localDate = DateOnly.FromDateTime(local);
                return localDate >= from && localDate <= to;
            })
            .Select(MapExercise)
            .ToList();
    }

    private static void ValidateRange(DateOnly from, DateOnly to)
    {
        if (to < from)
        {
            throw new AppValidationException("to", "to must be on or after from.");
        }

        if (to.DayNumber - from.DayNumber + 1 > HealthPalConstants.HistoryMaxDays)
        {
            throw new AppValidationException("to", $"Range cannot exceed {HealthPalConstants.HistoryMaxDays} days.");
        }
    }

    private static DailyHealthSummaryDto MapDaily(DailyHealthSummary summary, FatigueAssessment? assessment) =>
        new()
        {
            LocalDate = summary.LocalDate,
            Timezone = summary.Timezone,
            SleepMinutes = summary.SleepMinutes,
            Steps = summary.Steps,
            AverageHeartRate = summary.AverageHeartRate,
            MinHeartRate = summary.MinHeartRate,
            MaxHeartRate = summary.MaxHeartRate,
            RestingHeartRate = summary.RestingHeartRate,
            ActiveCalories = summary.ActiveCalories,
            ExerciseCount = summary.ExerciseCount,
            ExerciseDurationMinutes = summary.ExerciseDurationMinutes,
            CoverageFlags = summary.CoverageFlags,
            Fatigue = assessment is null
                ? null
                : new FatigueDailyValueDto
                {
                    Probability = assessment.CalibratedProbability,
                    Status = assessment.Status,
                    EvaluatedAtUtc = assessment.EvaluatedAtUtc
                }
        };

    private static FatigueAssessmentDto MapAssessment(FatigueAssessment assessment) =>
        new()
        {
            Id = assessment.Id,
            EvaluatedAtUtc = assessment.EvaluatedAtUtc,
            LocalDate = assessment.LocalDate,
            ModelVersion = assessment.ModelVersion,
            BaseProbability = assessment.BaseProbability,
            CalibratedProbability = assessment.CalibratedProbability,
            Threshold = assessment.Threshold,
            Status = assessment.Status,
            CoverageHours = assessment.CoverageHours,
            LatestSampleAtUtc = assessment.LatestSampleAtUtc,
            DataFreshnessMinutes = assessment.DataFreshnessMinutes,
            MissingReasons = assessment.MissingReasons,
            FeatureVectorHash = assessment.FeatureVectorHash,
            CreatedBy = assessment.CreatedBy
        };

    private static ExerciseSessionDto MapExercise(ExerciseSession session) =>
        new()
        {
            ExternalRecordId = session.ExternalRecordId,
            Type = session.Type,
            StartUtc = session.StartUtc,
            EndUtc = session.EndUtc,
            ZoneOffsetMinutes = session.ZoneOffsetMinutes,
            DurationMinutes = session.DurationMinutes,
            Calories = session.Calories,
            SourceId = session.SourceId
        };
}
