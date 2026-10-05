import '../domain/health_connect_failure.dart';
import '../domain/health_records.dart';
import 'health_connect_adapter.dart';

class HealthConnectGateway {
  const HealthConnectGateway({required HealthConnectAdapter adapter})
    : _adapter = adapter;

  final HealthConnectAdapter _adapter;

  Future<HealthConnectCapabilities> getCapabilities() =>
      _map(_adapter.getCapabilities);

  Future<PermissionSnapshot> getPermissions() => _map(_adapter.getPermissions);

  Future<PermissionSnapshot> requestPermissions(
    Set<HealthPermission> permissions,
  ) => _map(() => _adapter.requestPermissions(permissions));

  Future<PermissionSnapshot> requestBackgroundRead() =>
      _map(_adapter.requestBackgroundRead);

  Future<IngestionBatch> readRange(DateTime startUtc, DateTime endUtc) =>
      _map(() => _adapter.readRange(startUtc, endUtc));

  Future<void> openSettings() => _map(_adapter.openSettings);

  Future<T> _map<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on HealthConnectFailure {
      rethrow;
    } catch (error) {
      throw HealthConnectFailure(
        HealthConnectFailureCode.unavailable,
        message: error.toString(),
      );
    }
  }
}
