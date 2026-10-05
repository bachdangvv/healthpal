namespace HealthPal.Domain;

public enum FatigueAssessmentStatus
{
    SignalDetected,
    NoClearSignal,
    InsufficientData,
    SuppressedDuringExercise
}

public enum AssessmentCreatedBy
{
    Foreground,
    Background
}

public enum SyncBatchStatus
{
    Applied
}
