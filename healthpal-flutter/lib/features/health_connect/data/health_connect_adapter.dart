import '../domain/health_records.dart';

abstract interface class HealthConnectAdapter {
  Future<HealthConnectCapabilities> getCapabilities();

  Future<PermissionSnapshot> getPermissions();

  Future<PermissionSnapshot> requestPermissions(
    Set<HealthPermission> permissions,
  );

  Future<PermissionSnapshot> requestBackgroundRead();

  Future<IngestionBatch> readRange(DateTime startUtc, DateTime endUtc);

  Future<void> openSettings();
}
