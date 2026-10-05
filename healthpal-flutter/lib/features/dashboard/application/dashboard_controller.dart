import 'package:flutter/foundation.dart';

import '../data/health_connect_repository.dart';
import '../domain/dashboard_models.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({required this.repository});

  final HealthConnectRepository repository;
  HealthConnectSnapshot? _snapshot;
  bool _loading = false;
  bool _requestingPermissions = false;
  Object? _error;

  HealthConnectSnapshot? get snapshot => _snapshot;
  bool get isLoading => _loading;
  bool get isRequestingPermissions => _requestingPermissions;
  Object? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _snapshot = await repository.fetchSnapshot();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh({bool userInitiated = false}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _snapshot = await repository.syncFromHealthConnect(
        userInitiated: userInitiated,
      );
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> requestPermissions() async {
    if (_requestingPermissions || _loading) return;
    _requestingPermissions = true;
    _error = null;
    notifyListeners();
    try {
      _snapshot = await repository.requestReadPermissions();
    } catch (error) {
      _error = error;
    } finally {
      _requestingPermissions = false;
      notifyListeners();
    }
  }

  Future<void> openSettings() => repository.openHealthConnectSettings();
}
