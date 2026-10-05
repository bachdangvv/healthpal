import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/history/data/demo_health_history_repository.dart';
import 'package:healthpal/features/history/domain/daily_health_summary.dart';

void main() {
  group('DemoHealthHistoryRepository', () {
    late DemoHealthHistoryRepository repository;

    setUp(() {
      repository = DemoHealthHistoryRepository(
        anchorDate: DateTime(2026, 9, 23, 22, 30),
        latency: Duration.zero,
      );
    });

    test('returns seven newest days in descending order', () async {
      final result = await repository.fetch(HistoryPeriod.sevenDays);

      expect(result, hasLength(7));
      expect(result.first.date, DateTime(2026, 9, 23));
      expect(result.last.date, DateTime(2026, 9, 17));
      for (var index = 1; index < result.length; index++) {
        expect(result[index - 1].date.isAfter(result[index].date), isTrue);
      }
    });

    test('returns thirty days and preserves optional missing values', () async {
      final result = await repository.fetch(HistoryPeriod.thirtyDays);

      expect(result, hasLength(30));
      expect(result.any((day) => day.hrv == null), isTrue);
      expect(result.any((day) => day.restingHeartRate == null), isTrue);
      expect(result.every((day) => (day.steps ?? 0) > 0), isTrue);
      expect(result.every((day) => (day.sleepMinutes ?? 0) > 0), isTrue);
    });
  });
}
