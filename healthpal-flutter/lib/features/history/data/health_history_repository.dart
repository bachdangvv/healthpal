import '../domain/daily_health_summary.dart';

abstract interface class HealthHistoryRepository {
  Future<List<DailyHealthSummary>> fetch(HistoryPeriod period);
}
