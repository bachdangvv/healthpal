using FluentAssertions;
using HealthPal.Application.Contracts;
using HealthPal.Application.Exceptions;
using HealthPal.Application.Validation;
using HealthPal.Domain;

namespace HealthPal.UnitTests;

public sealed class SyncBatchValidatorTests
{
    [Fact]
    public void Rejects_wrong_model_version()
    {
        var batch = Valid();
        batch.FatigueAssessments[0].ModelVersion = "healthpal_fatigue_v5";
        var act = () => SyncBatchValidator.Validate(batch);
        act.Should().Throw<AppValidationException>()
            .Which.Errors.Should().ContainKey("fatigueAssessments[0].modelVersion");
    }

    [Fact]
    public void Rejects_probability_out_of_range()
    {
        var batch = Valid();
        batch.FatigueAssessments[0].CalibratedProbability = 1.2;
        var act = () => SyncBatchValidator.Validate(batch);
        act.Should().Throw<AppValidationException>()
            .Which.Errors.Should().ContainKey("fatigueAssessments[0].calibratedProbability");
    }

    [Fact]
    public void Rejects_negative_counts()
    {
        var batch = Valid();
        batch.HourlyBins[0].Steps = -1;
        batch.DailySummaries[0].ExerciseCount = -2;
        var act = () => SyncBatchValidator.Validate(batch);
        var errors = act.Should().Throw<AppValidationException>().Which.Errors;
        errors.Should().ContainKey("hourlyBins[0].steps");
        errors.Should().ContainKey("dailySummaries[0].exerciseCount");
    }

    [Fact]
    public void Accepts_valid_batch()
    {
        var act = () => SyncBatchValidator.Validate(Valid());
        act.Should().NotThrow();
    }

    [Fact]
    public void Accepts_valid_schema_v2_batch()
    {
        var act = () => SyncBatchValidator.Validate(ValidV2());
        act.Should().NotThrow();
    }

    [Fact]
    public void Rejects_schema_v2_without_window()
    {
        var batch = ValidV2();
        batch.ReplacementWindow = null;
        var act = () => SyncBatchValidator.Validate(batch);
        act.Should().Throw<AppValidationException>()
            .Which.Errors.Should().ContainKey("replacementWindow");
    }

    [Fact]
    public void Rejects_reversed_or_broad_window()
    {
        var reversed = ValidV2();
        reversed.ReplacementWindow!.EndUtcExclusive = reversed.ReplacementWindow.StartUtc;
        var reversedAct = () => SyncBatchValidator.Validate(reversed);
        reversedAct.Should().Throw<AppValidationException>()
            .Which.Errors.Should().ContainKey("replacementWindow.endUtcExclusive");

        var broad = ValidV2();
        broad.ReplacementWindow!.EndUtcExclusive = broad.ReplacementWindow.StartUtc.AddDays(40);
        broad.ReplacementWindow.LocalDateEndExclusive = broad.ReplacementWindow.LocalDateStart.AddDays(40);
        var broadAct = () => SyncBatchValidator.Validate(broad);
        broadAct.Should().Throw<AppValidationException>()
            .Which.Errors.Should().ContainKey("replacementWindow");
    }

    private static SyncBatchDto Valid() =>
        new()
        {
            SchemaVersion = 1,
            DeviceId = "device",
            IdempotencyKey = "key",
            GeneratedAtUtc = new DateTime(2026, 3, 15, 8, 0, 0, DateTimeKind.Utc),
            HourlyBins =
            [
                new HourlyHealthBinDto
                {
                    HourUtc = new DateTime(2026, 3, 15, 1, 0, 0, DateTimeKind.Utc),
                    ZoneOffsetMinutes = 0,
                    HrSampleCount = 0,
                    SourceId = "src"
                }
            ],
            DailySummaries =
            [
                new DailyHealthSummaryDto
                {
                    LocalDate = new DateOnly(2026, 3, 15),
                    Timezone = "UTC"
                }
            ],
            FatigueAssessments =
            [
                new FatigueAssessmentDto
                {
                    Id = "a1",
                    EvaluatedAtUtc = new DateTime(2026, 3, 15, 8, 0, 0, DateTimeKind.Utc),
                    LocalDate = new DateOnly(2026, 3, 15),
                    ModelVersion = HealthPalConstants.FatigueModelVersion,
                    Threshold = 0.18,
                    Status = FatigueAssessmentStatus.InsufficientData,
                    CoverageHours = 0,
                    FeatureVectorHash = "abc",
                    CreatedBy = AssessmentCreatedBy.Foreground
                }
            ]
        };

    private static SyncBatchDto ValidV2()
    {
        var batch = Valid();
        batch.SchemaVersion = HealthPalConstants.SyncSchemaVersionV2;
        batch.ReplacementWindow = new ReplacementWindowDto
        {
            StartUtc = new DateTime(2026, 3, 14, 0, 0, 0, DateTimeKind.Utc),
            EndUtcExclusive = new DateTime(2026, 3, 16, 0, 0, 0, DateTimeKind.Utc),
            LocalDateStart = new DateOnly(2026, 3, 14),
            LocalDateEndExclusive = new DateOnly(2026, 3, 16)
        };
        return batch;
    }
}
