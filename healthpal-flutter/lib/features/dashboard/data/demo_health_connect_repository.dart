import '../domain/dashboard_models.dart';
import 'health_connect_repository.dart';

class DemoHealthConnectRepository implements HealthConnectRepository {
  const DemoHealthConnectRepository({this.snapshot = _defaultSnapshot});

  final HealthConnectSnapshot snapshot;

  @override
  Future<HealthConnectSnapshot> fetchSnapshot() async => snapshot;

  @override
  Future<HealthConnectSnapshot> requestReadPermissions() async => snapshot;

  @override
  Future<HealthConnectSnapshot> requestBackgroundRead() async => snapshot;

  @override
  Future<void> openHealthConnectSettings() async {}

  @override
  Future<HealthConnectSnapshot> syncFromHealthConnect({
    bool userInitiated = false,
  }) => fetchSnapshot();

  static const HealthConnectSnapshot _defaultSnapshot = HealthConnectSnapshot(
    availability: HealthConnectAvailability.unavailable,
    access: HealthConnectAccess.denied,
    missingPermissions: [],
  );
}
