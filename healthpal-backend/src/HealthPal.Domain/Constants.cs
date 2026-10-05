namespace HealthPal.Domain;

public static class HealthPalConstants
{
    public const string FatigueModelVersion = "healthpal_fatigue_v4";
    public const int SyncSchemaVersion = 1;
    public const int SyncSchemaVersionV2 = 2;
    public const int MaxReplacementWindowDays = 32;
    public const int DefaultDailyStepGoal = 8000;
    public const int MinDailyStepGoal = 100;
    public const double MinHeightCm = 50;
    public const double MaxHeightCm = 250;
    public const double MinWeightKg = 20;
    public const double MaxWeightKg = 400;
    public const int HistoryMaxDays = 90;
    public const int MaxHourlyBinsPerBatch = 336;
    public const int MaxDailySummariesPerBatch = 90;
    public const int MaxExerciseSessionsPerBatch = 200;
    public const int MaxFatigueAssessmentsPerBatch = 90;
    public const int MaxSyncPayloadBytes = 2_097_152;
}
