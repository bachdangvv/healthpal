import '../../../core/database/healthpal_database.dart';
import '../../../core/time/app_clock.dart';
import '../../assessment/domain/fatigue_assessment.dart';
import '../domain/daily_health_summary.dart';
import 'health_history_repository.dart';

class LocalHealthHistoryRepository implements HealthHistoryRepository {
  LocalHealthHistoryRepository({
    required HealthPalDatabase database,
    required this.userId,
    AppClock clock = const SystemAppClock(),
  }) : _db = database,
       _clock = clock;

  final HealthPalDatabase _db;
  final String userId;
  final AppClock _clock;

  @override
  Future<List<DailyHealthSummary>> fetch(HistoryPeriod period) async {
    final now = _clock.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: period.days - 1));
    final rows = _db.connection.select(
      '''
SELECT * FROM daily_health_summaries
WHERE user_id = ? AND local_date >= ? AND local_date <= ?
ORDER BY local_date DESC
''',
      [userId, _date(start), _date(today)],
    );
    final assessments = _db.connection.select(
      '''
SELECT * FROM fatigue_assessments
WHERE user_id = ?
ORDER BY evaluated_at_utc DESC
''',
      [userId],
    );
    final byDate = <String, Map<String, Object?>>{
      for (final row in rows) row['local_date'] as String: row,
    };

    FatigueDailyValue? fatigueFor(String localDate) {
      for (final row in assessments) {
        if (row['local_date'] == localDate) {
          return FatigueDailyValue(
            probability: (row['calibrated_probability'] as num?)?.toDouble(),
            threshold: (row['threshold'] as num).toDouble(),
            status: FatigueAssessmentStatus.values.byName(
              row['status'] as String,
            ),
            evaluatedAtUtc: DateTime.parse(row['evaluated_at_utc'] as String),
          );
        }
      }
      return null;
    }

    return [
      for (var offset = 0; offset < period.days; offset++)
        _summary(today.subtract(Duration(days: offset)), byDate, fatigueFor),
    ];
  }

  DailyHealthSummary _summary(
    DateTime date,
    Map<String, Map<String, Object?>> byDate,
    FatigueDailyValue? Function(String localDate) fatigueFor,
  ) {
    final key = _date(date);
    final row = byDate[key];
    if (row == null) {
      return DailyHealthSummary(date: date, fatigue: fatigueFor(key));
    }
    return DailyHealthSummary(
      date: date,
      fatigue: fatigueFor(key),
      sleepMinutes: row['sleep_minutes'] as int?,
      steps: row['steps'] as int?,
      averageHeartRate: (row['average_heart_rate'] as num?)?.toDouble(),
      minHeartRate: (row['min_heart_rate'] as num?)?.toDouble(),
      maxHeartRate: (row['max_heart_rate'] as num?)?.toDouble(),
      restingHeartRate: (row['resting_heart_rate'] as num?)?.round(),
      exerciseCount: row['exercise_count'] as int? ?? 0,
      exerciseDurationMinutes: row['exercise_duration_minutes'] as int? ?? 0,
      activeCalories: (row['active_calories'] as num?)?.toDouble(),
    );
  }

  String _date(DateTime value) {
    final local = DateTime(value.year, value.month, value.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
