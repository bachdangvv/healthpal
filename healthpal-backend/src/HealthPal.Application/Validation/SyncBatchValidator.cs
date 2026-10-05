using HealthPal.Application.Contracts;
using HealthPal.Application.Exceptions;
using HealthPal.Domain;

namespace HealthPal.Application.Validation;

public static class SyncBatchValidator
{
    public static void Validate(SyncBatchDto batch)
    {
        var errors = new Dictionary<string, List<string>>(StringComparer.Ordinal);

        if (batch.SchemaVersion != HealthPalConstants.SyncSchemaVersion &&
            batch.SchemaVersion != HealthPalConstants.SyncSchemaVersionV2)
        {
            Add(errors, "schemaVersion", "schemaVersion must be 1 or 2.");
        }

        if (string.IsNullOrWhiteSpace(batch.DeviceId))
        {
            Add(errors, "deviceId", "deviceId is required.");
        }
        else if (batch.DeviceId.Length > 128)
        {
            Add(errors, "deviceId", "deviceId is too long.");
        }

        if (string.IsNullOrWhiteSpace(batch.IdempotencyKey))
        {
            Add(errors, "idempotencyKey", "idempotencyKey is required.");
        }
        else if (batch.IdempotencyKey.Length > 128)
        {
            Add(errors, "idempotencyKey", "idempotencyKey is too long.");
        }

        if (batch.GeneratedAtUtc == default)
        {
            Add(errors, "generatedAtUtc", "generatedAtUtc is required.");
        }

        if (batch.HourlyBins.Count > HealthPalConstants.MaxHourlyBinsPerBatch)
        {
            Add(errors, "hourlyBins", $"At most {HealthPalConstants.MaxHourlyBinsPerBatch} hourly bins are allowed.");
        }

        if (batch.DailySummaries.Count > HealthPalConstants.MaxDailySummariesPerBatch)
        {
            Add(errors, "dailySummaries", $"At most {HealthPalConstants.MaxDailySummariesPerBatch} daily summaries are allowed.");
        }

        if (batch.ExerciseSessions.Count > HealthPalConstants.MaxExerciseSessionsPerBatch)
        {
            Add(errors, "exerciseSessions", $"At most {HealthPalConstants.MaxExerciseSessionsPerBatch} exercise sessions are allowed.");
        }

        if (batch.FatigueAssessments.Count > HealthPalConstants.MaxFatigueAssessmentsPerBatch)
        {
            Add(errors, "fatigueAssessments", $"At most {HealthPalConstants.MaxFatigueAssessmentsPerBatch} fatigue assessments are allowed.");
        }

        for (var i = 0; i < batch.HourlyBins.Count; i++)
        {
            ValidateHourly(batch.HourlyBins[i], $"hourlyBins[{i}]", errors);
        }

        for (var i = 0; i < batch.DailySummaries.Count; i++)
        {
            ValidateDaily(batch.DailySummaries[i], $"dailySummaries[{i}]", errors);
        }

        for (var i = 0; i < batch.ExerciseSessions.Count; i++)
        {
            ValidateExercise(batch.ExerciseSessions[i], $"exerciseSessions[{i}]", errors);
        }

        if (batch.SchemaVersion == HealthPalConstants.SyncSchemaVersionV2)
        {
            ValidateReplacementWindow(batch, errors);
        }

        for (var i = 0; i < batch.FatigueAssessments.Count; i++)
        {
            ValidateAssessment(batch.FatigueAssessments[i], $"fatigueAssessments[{i}]", errors);
        }

        if (errors.Count > 0)
        {
            throw new AppValidationException(errors.ToDictionary(static pair => pair.Key, static pair => pair.Value.ToArray(), StringComparer.Ordinal));
        }
    }

    private static void ValidateReplacementWindow(SyncBatchDto batch, Dictionary<string, List<string>> errors)
    {
        if (batch.ReplacementWindow is null)
        {
            Add(errors, "replacementWindow", "replacementWindow is required for schemaVersion 2.");
            return;
        }

        var window = batch.ReplacementWindow;
        var start = DateTime.SpecifyKind(window.StartUtc.ToUniversalTime(), DateTimeKind.Utc);
        var end = DateTime.SpecifyKind(window.EndUtcExclusive.ToUniversalTime(), DateTimeKind.Utc);
        if (end <= start)
        {
            Add(errors, "replacementWindow.endUtcExclusive", "endUtcExclusive must be after startUtc.");
        }
        else if (end - start > TimeSpan.FromDays(HealthPalConstants.MaxReplacementWindowDays))
        {
            Add(errors, "replacementWindow", $"UTC window duration must be at most {HealthPalConstants.MaxReplacementWindowDays} days.");
        }

        if (window.LocalDateEndExclusive <= window.LocalDateStart)
        {
            Add(errors, "replacementWindow.localDateEndExclusive", "localDateEndExclusive must be after localDateStart.");
        }
        else if (window.LocalDateEndExclusive.DayNumber - window.LocalDateStart.DayNumber > HealthPalConstants.MaxReplacementWindowDays)
        {
            Add(errors, "replacementWindow", $"local date window must be at most {HealthPalConstants.MaxReplacementWindowDays} days.");
        }

        for (var i = 0; i < batch.HourlyBins.Count; i++)
        {
            var hour = DateTime.SpecifyKind(batch.HourlyBins[i].HourUtc.ToUniversalTime(), DateTimeKind.Utc);
            if (hour < start || hour >= end)
            {
                Add(errors, $"hourlyBins[{i}].hourUtc", "hourUtc must fall inside the replacement window.");
            }
        }

        for (var i = 0; i < batch.DailySummaries.Count; i++)
        {
            var date = batch.DailySummaries[i].LocalDate;
            if (date < window.LocalDateStart || date >= window.LocalDateEndExclusive)
            {
                Add(errors, $"dailySummaries[{i}].localDate", "localDate must fall inside the replacement window.");
            }
        }

        for (var i = 0; i < batch.ExerciseSessions.Count; i++)
        {
            var session = batch.ExerciseSessions[i];
            var sessionStart = DateTime.SpecifyKind(session.StartUtc.ToUniversalTime(), DateTimeKind.Utc);
            var sessionEnd = DateTime.SpecifyKind(session.EndUtc.ToUniversalTime(), DateTimeKind.Utc);
            if (!(sessionEnd > start && sessionStart < end))
            {
                Add(errors, $"exerciseSessions[{i}]", "exercise session must overlap the replacement window.");
            }
        }
    }

    private static void ValidateHourly(HourlyHealthBinDto bin, string prefix, Dictionary<string, List<string>> errors)
    {
        if (bin.HourUtc == default)
        {
            Add(errors, $"{prefix}.hourUtc", "hourUtc is required.");
        }

        if (string.IsNullOrWhiteSpace(bin.SourceId))
        {
            Add(errors, $"{prefix}.sourceId", "sourceId is required.");
        }

        if (bin.HrSampleCount < 0)
        {
            Add(errors, $"{prefix}.hrSampleCount", "hrSampleCount must be >= 0.");
        }

        if (bin.Steps is < 0)
        {
            Add(errors, $"{prefix}.steps", "steps must be >= 0.");
        }

        if (bin.ActiveCalories is < 0)
        {
            Add(errors, $"{prefix}.activeCalories", "activeCalories must be >= 0.");
        }
    }

    private static void ValidateDaily(DailyHealthSummaryDto summary, string prefix, Dictionary<string, List<string>> errors)
    {
        if (summary.LocalDate == default)
        {
            Add(errors, $"{prefix}.localDate", "localDate is required.");
        }

        if (string.IsNullOrWhiteSpace(summary.Timezone))
        {
            Add(errors, $"{prefix}.timezone", "timezone is required.");
        }

        if (summary.SleepMinutes is < 0)
        {
            Add(errors, $"{prefix}.sleepMinutes", "sleepMinutes must be >= 0.");
        }

        if (summary.Steps is < 0)
        {
            Add(errors, $"{prefix}.steps", "steps must be >= 0.");
        }

        if (summary.ActiveCalories is < 0)
        {
            Add(errors, $"{prefix}.activeCalories", "activeCalories must be >= 0.");
        }

        if (summary.ExerciseCount < 0)
        {
            Add(errors, $"{prefix}.exerciseCount", "exerciseCount must be >= 0.");
        }

        if (summary.ExerciseDurationMinutes < 0)
        {
            Add(errors, $"{prefix}.exerciseDurationMinutes", "exerciseDurationMinutes must be >= 0.");
        }
    }

    private static void ValidateExercise(ExerciseSessionDto session, string prefix, Dictionary<string, List<string>> errors)
    {
        if (string.IsNullOrWhiteSpace(session.ExternalRecordId))
        {
            Add(errors, $"{prefix}.externalRecordId", "externalRecordId is required.");
        }

        if (string.IsNullOrWhiteSpace(session.Type))
        {
            Add(errors, $"{prefix}.type", "type is required.");
        }

        if (string.IsNullOrWhiteSpace(session.SourceId))
        {
            Add(errors, $"{prefix}.sourceId", "sourceId is required.");
        }

        if (session.StartUtc == default || session.EndUtc == default)
        {
            Add(errors, $"{prefix}.startUtc", "startUtc and endUtc are required.");
        }
        else if (session.EndUtc < session.StartUtc)
        {
            Add(errors, $"{prefix}.endUtc", "endUtc must be greater than or equal to startUtc.");
        }

        if (session.DurationMinutes < 0)
        {
            Add(errors, $"{prefix}.durationMinutes", "durationMinutes must be >= 0.");
        }

        if (session.Calories is < 0)
        {
            Add(errors, $"{prefix}.calories", "calories must be >= 0.");
        }
    }

    private static void ValidateAssessment(FatigueAssessmentDto assessment, string prefix, Dictionary<string, List<string>> errors)
    {
        if (string.IsNullOrWhiteSpace(assessment.Id))
        {
            Add(errors, $"{prefix}.id", "id is required.");
        }

        if (assessment.EvaluatedAtUtc == default)
        {
            Add(errors, $"{prefix}.evaluatedAtUtc", "evaluatedAtUtc is required.");
        }

        if (assessment.LocalDate == default)
        {
            Add(errors, $"{prefix}.localDate", "localDate is required.");
        }

        if (!string.Equals(assessment.ModelVersion, HealthPalConstants.FatigueModelVersion, StringComparison.Ordinal))
        {
            Add(errors, $"{prefix}.modelVersion", $"modelVersion must be {HealthPalConstants.FatigueModelVersion}.");
        }

        ValidateProbability(assessment.BaseProbability, $"{prefix}.baseProbability", errors);
        ValidateProbability(assessment.CalibratedProbability, $"{prefix}.calibratedProbability", errors);
        ValidateProbability(assessment.Threshold, $"{prefix}.threshold", errors);

        if (assessment.CoverageHours < 0)
        {
            Add(errors, $"{prefix}.coverageHours", "coverageHours must be >= 0.");
        }

        if (assessment.DataFreshnessMinutes is < 0)
        {
            Add(errors, $"{prefix}.dataFreshnessMinutes", "dataFreshnessMinutes must be >= 0.");
        }

        if (string.IsNullOrWhiteSpace(assessment.FeatureVectorHash))
        {
            Add(errors, $"{prefix}.featureVectorHash", "featureVectorHash is required.");
        }

        if (!Enum.IsDefined(assessment.Status))
        {
            Add(errors, $"{prefix}.status", "status is not a supported value.");
        }

        if (!Enum.IsDefined(assessment.CreatedBy))
        {
            Add(errors, $"{prefix}.createdBy", "createdBy is not a supported value.");
        }
    }

    private static void ValidateProbability(double? value, string field, Dictionary<string, List<string>> errors)
    {
        if (value is { } probability && (probability < 0 || probability > 1 || double.IsNaN(probability) || double.IsInfinity(probability)))
        {
            Add(errors, field, "Probability must be between 0 and 1.");
        }
    }

    private static void Add(Dictionary<string, List<string>> errors, string field, string message)
    {
        if (!errors.TryGetValue(field, out var list))
        {
            list = [];
            errors[field] = list;
        }

        list.Add(message);
    }
}
