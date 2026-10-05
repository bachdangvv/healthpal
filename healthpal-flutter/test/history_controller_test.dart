import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/history/application/history_controller.dart';
import 'package:healthpal/features/history/data/health_history_repository.dart';
import 'package:healthpal/features/history/domain/daily_health_summary.dart';

void main() {
  test('loads history, changes period and selected metric', () async {
    final repository = _FakeHistoryRepository();
    final controller = HistoryController(repository: repository);
    addTearDown(controller.dispose);

    await controller.load();
    expect(repository.periods, [HistoryPeriod.sevenDays]);
    expect(controller.summaries, hasLength(7));
    expect(controller.metric, HistoryMetric.fatigue);

    controller.setMetric(HistoryMetric.hrv);
    expect(controller.metric, HistoryMetric.hrv);

    await controller.setPeriod(HistoryPeriod.thirtyDays);
    expect(repository.periods, [
      HistoryPeriod.sevenDays,
      HistoryPeriod.thirtyDays,
    ]);
    expect(controller.summaries, hasLength(30));
  });

  test('exposes retryable repository errors without stale data', () async {
    final repository = _FakeHistoryRepository()..shouldFail = true;
    final controller = HistoryController(repository: repository);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.error, isNotNull);
    expect(controller.summaries, isEmpty);
    expect(controller.isLoading, isFalse);

    repository.shouldFail = false;
    await controller.retry();
    expect(controller.error, isNull);
    expect(controller.summaries, hasLength(7));
  });
}

class _FakeHistoryRepository implements HealthHistoryRepository {
  final periods = <HistoryPeriod>[];
  bool shouldFail = false;

  @override
  Future<List<DailyHealthSummary>> fetch(HistoryPeriod period) async {
    periods.add(period);
    if (shouldFail) throw StateError('demo failure');
    return List.generate(period.days, (index) {
      return DailyHealthSummary(
        date: DateTime(2026, 9, 23).subtract(Duration(days: index)),
        sleepMinutes: 420,
        steps: 8000,
        restingHeartRate: 65,
        hrv: 48,
        activeCalories: 420,
      );
    });
  }
}
