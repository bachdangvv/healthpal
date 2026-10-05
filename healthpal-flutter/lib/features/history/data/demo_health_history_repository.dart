import '../../assessment/domain/fatigue_assessment.dart';
import '../domain/daily_health_summary.dart';
import 'health_history_repository.dart';

class DemoHealthHistoryRepository implements HealthHistoryRepository {
  DemoHealthHistoryRepository({
    DateTime? anchorDate,
    this.latency = const Duration(milliseconds: 350),
  }) : _anchorDate = _dateOnly(anchorDate ?? DateTime.now());

  final DateTime _anchorDate;
  final Duration latency;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  Future<List<DailyHealthSummary>> fetch(HistoryPeriod period) async {
    await Future<void>.delayed(latency);
    final allDays = List<DailyHealthSummary>.generate(30, (index) {
      final date = _anchorDate.subtract(Duration(days: 29 - index));
      final probability = 0.08 + ((index * 0.037) % 0.4);
      final detected = probability >= 0.18170608515558545;
      return DailyHealthSummary(
        date: date,
        fatigue: FatigueDailyValue(
          probability: probability,
          threshold: 0.18170608515558545,
          status: detected
              ? FatigueAssessmentStatus.signalDetected
              : FatigueAssessmentStatus.noClearSignal,
          evaluatedAtUtc: DateTime.utc(date.year, date.month, date.day, 10),
        ),
        sleepMinutes: 345 + ((index * 23) % 165),
        steps: 4200 + ((index * 1237) % 8600),
        averageHeartRate: 68 + ((index * 1.4) % 12),
        minHeartRate: 54 + ((index * 0.8) % 8),
        maxHeartRate: 92 + ((index * 1.1) % 18),
        restingHeartRate: index % 8 == 0 ? null : 60 + ((index * 3) % 15),
        exerciseCount: index % 3 == 0 ? 1 : 0,
        exerciseDurationMinutes: index % 3 == 0 ? 25 + (index % 40) : 0,
        hrv: index % 6 == 0 ? null : 36 + ((index * 5) % 27),
        activeCalories: (230 + ((index * 47) % 430)).toDouble(),
      );
    });

    return allDays.reversed.take(period.days).toList(growable: false);
  }
}
