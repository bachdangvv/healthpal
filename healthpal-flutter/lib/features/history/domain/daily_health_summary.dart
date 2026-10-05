import '../../assessment/domain/fatigue_assessment.dart';

enum HistoryPeriod {
  sevenDays(7),
  thirtyDays(30);

  const HistoryPeriod(this.days);
  final int days;
}

enum HistoryMetric {
  fatigue,
  sleep,
  steps,
  heartRate,
  restingHeartRate,
  exerciseDuration,
  activeCalories,
  hrv,
}

class DailyHealthSummary {
  const DailyHealthSummary({
    required this.date,
    this.fatigue,
    this.sleepMinutes,
    this.steps,
    this.averageHeartRate,
    this.minHeartRate,
    this.maxHeartRate,
    this.restingHeartRate,
    this.exerciseCount = 0,
    this.exerciseDurationMinutes = 0,
    this.activeCalories,
    this.hrv,
  });

  final DateTime date;
  final FatigueDailyValue? fatigue;
  final int? sleepMinutes;
  final int? steps;
  final double? averageHeartRate;
  final double? minHeartRate;
  final double? maxHeartRate;
  final int? restingHeartRate;
  final int exerciseCount;
  final int exerciseDurationMinutes;
  final double? activeCalories;
  final int? hrv;

  double? valueFor(HistoryMetric metric) {
    return switch (metric) {
      HistoryMetric.fatigue => switch (fatigue?.status) {
        FatigueAssessmentStatus.signalDetected => 1,
        FatigueAssessmentStatus.noClearSignal => 0,
        _ => null,
      },
      HistoryMetric.sleep => sleepMinutes == null ? null : sleepMinutes! / 60,
      HistoryMetric.steps => steps?.toDouble(),
      HistoryMetric.heartRate => averageHeartRate,
      HistoryMetric.restingHeartRate => restingHeartRate?.toDouble(),
      HistoryMetric.exerciseDuration => exerciseDurationMinutes.toDouble(),
      HistoryMetric.activeCalories => activeCalories,
      HistoryMetric.hrv => hrv?.toDouble(),
    };
  }
}
