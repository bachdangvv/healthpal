import '../domain/training_models.dart';

class TrainingReadinessRuleEngine {
  const TrainingReadinessRuleEngine();

  TrainingReadinessResult evaluate(TrainingReadinessInput input) {
    if (input.stress == null || input.sleepMinutes == null) {
      return TrainingReadinessResult(
        status: TrainingReadinessStatus.insufficientData,
        input: input,
      );
    }

    final sleep = input.sleepMinutes!;
    TrainingReadinessStatus base;
    if (input.stress == StressLevel.high && sleep < 300) {
      base = TrainingReadinessStatus.rest;
    } else if (input.stress == StressLevel.high || sleep < 360) {
      base = TrainingReadinessStatus.recovery;
    } else if (input.stress == StressLevel.medium || sleep < 420) {
      base = TrainingReadinessStatus.moderate;
    } else {
      base = TrainingReadinessStatus.ready;
    }

    final lowMovement = _hasLowMovement(input);
    if (!lowMovement || base == TrainingReadinessStatus.rest) {
      return TrainingReadinessResult(status: base, input: input);
    }

    final adjusted = switch (base) {
      TrainingReadinessStatus.ready => TrainingReadinessStatus.moderate,
      TrainingReadinessStatus.moderate => TrainingReadinessStatus.recovery,
      _ => base,
    };
    return TrainingReadinessResult(
      status: adjusted,
      input: input,
      movementAdjusted: adjusted != base,
    );
  }

  bool _hasLowMovement(TrainingReadinessInput input) {
    final lowSteps = input.steps != null && input.steps! < 3000;
    final lowCalories =
        input.activeCalories != null && input.activeCalories! < 150;
    return lowSteps || lowCalories;
  }
}
