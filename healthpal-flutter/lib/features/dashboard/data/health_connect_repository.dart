import '../domain/dashboard_models.dart';

abstract interface class HealthConnectRepository {
  Future<HealthConnectSnapshot> fetchSnapshot();

  Future<HealthConnectSnapshot> requestReadPermissions();

  Future<HealthConnectSnapshot> requestBackgroundRead();

  Future<void> openHealthConnectSettings();

  Future<HealthConnectSnapshot> syncFromHealthConnect({
    bool userInitiated = false,
  });
}

/// Convenience operations keep UI code independent from the Android adapter.
extension HealthConnectRepositoryOperations on HealthConnectRepository {
  Future<HealthConnectAvailability> checkAvailability() async =>
      (await fetchSnapshot()).availability;

  Future<Set<HealthMetricPermission>> getGrantedPermissions() async {
    final snapshot = await fetchSnapshot();
    final missing = snapshot.missingPermissions.toSet();
    return HealthMetricPermission.values
        .where((permission) => !missing.contains(permission))
        .toSet();
  }

  Future<TodayHealthSummary?> fetchTodaySummary() async =>
      (await fetchSnapshot()).summary;

  Future<HealthConnectSnapshot> syncToday({bool userInitiated = false}) =>
      syncFromHealthConnect(userInitiated: userInitiated);
}
