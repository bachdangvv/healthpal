import 'package:flutter/foundation.dart';

import '../data/health_history_repository.dart';
import '../domain/daily_health_summary.dart';

class HistoryController extends ChangeNotifier {
  HistoryController({required this.repository});

  final HealthHistoryRepository repository;
  HistoryPeriod _period = HistoryPeriod.sevenDays;
  HistoryMetric _metric = HistoryMetric.fatigue;
  List<DailyHealthSummary> _summaries = const [];
  bool _isLoading = false;
  bool _isDisposed = false;
  Object? _error;
  int _requestId = 0;

  HistoryPeriod get period => _period;
  HistoryMetric get metric => _metric;
  List<DailyHealthSummary> get summaries => _summaries;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  Future<void> load() => _fetch();

  Future<void> setPeriod(HistoryPeriod period) async {
    if (_period == period && _summaries.isNotEmpty) return;
    _period = period;
    await _fetch();
  }

  void setMetric(HistoryMetric metric) {
    if (_metric == metric || _isDisposed) return;
    _metric = metric;
    notifyListeners();
  }

  Future<void> retry() => _fetch();

  Future<void> _fetch() async {
    if (_isDisposed) return;
    final requestId = ++_requestId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await repository.fetch(_period);
      if (_isDisposed || requestId != _requestId) return;
      _summaries = List.unmodifiable(result);
    } catch (error) {
      if (_isDisposed || requestId != _requestId) return;
      _error = error;
      _summaries = const [];
    } finally {
      if (!_isDisposed && requestId == _requestId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _requestId++;
    super.dispose();
  }
}
