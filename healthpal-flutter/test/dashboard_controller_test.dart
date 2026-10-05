import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/dashboard/application/dashboard_controller.dart';
import 'package:healthpal/features/dashboard/data/health_connect_repository.dart';
import 'package:healthpal/features/dashboard/domain/dashboard_models.dart';

class _FakeHealthConnectRepository implements HealthConnectRepository {
  _FakeHealthConnectRepository(this.snapshot);

  HealthConnectSnapshot snapshot;
  int fetchCount = 0;
  int requestCount = 0;
  int settingsCount = 0;
  int syncCount = 0;
  bool? lastSyncUserInitiated;

  @override
  Future<HealthConnectSnapshot> fetchSnapshot() async {
    fetchCount++;
    return snapshot;
  }

  @override
  Future<HealthConnectSnapshot> requestReadPermissions() async {
    requestCount++;
    return snapshot;
  }

  @override
  Future<HealthConnectSnapshot> requestBackgroundRead() async => snapshot;

  @override
  Future<void> openHealthConnectSettings() async {
    settingsCount++;
  }

  @override
  Future<HealthConnectSnapshot> syncFromHealthConnect({
    bool userInitiated = false,
  }) async {
    syncCount++;
    lastSyncUserInitiated = userInitiated;
    return snapshot;
  }
}

void main() {
  final now = DateTime.now();

  test('snapshot maps Health Connect states without inventing data', () {
    const noData = HealthConnectSnapshot(
      availability: HealthConnectAvailability.available,
      access: HealthConnectAccess.granted,
      missingPermissions: [],
    );
    expect(noData.status, DashboardDataStatus.noData);
    expect(noData.summary, isNull);

    const missing = HealthConnectSnapshot(
      availability: HealthConnectAvailability.available,
      access: HealthConnectAccess.missingPermissions,
      missingPermissions: [HealthMetricPermission.hrv],
    );
    expect(missing.status, DashboardDataStatus.missingPermissions);
    expect(missing.missingPermissions.single.label, 'HRV');

    final stale = HealthConnectSnapshot(
      availability: HealthConnectAvailability.available,
      access: HealthConnectAccess.granted,
      missingPermissions: const [],
      summary: TodayHealthSummary(collectedAt: now, steps: 0),
      lastSyncedAt: now.subtract(const Duration(hours: 7)),
    );
    expect(stale.status, DashboardDataStatus.needsSync);
    expect(stale.summary!.sleepMinutes, isNull);

    final connected = HealthConnectSnapshot(
      availability: HealthConnectAvailability.available,
      access: HealthConnectAccess.granted,
      missingPermissions: const [],
      summary: TodayHealthSummary(
        collectedAt: now,
        steps: 7420,
        sleepMinutes: 402,
        averageHeartRate: 72,
        restingHeartRate: 68,
        hrv: 47,
        activeCalories: 380,
      ),
      lastSyncedAt: now,
    );
    expect(connected.status, DashboardDataStatus.connected);
    expect(connected.summary!.steps, 7420);
    expect(connected.summary!.hrv, 47);
  });

  test(
    'controller loads, requests permissions and prevents duplicate work',
    () async {
      final repository = _FakeHealthConnectRepository(
        const HealthConnectSnapshot(
          availability: HealthConnectAvailability.unavailable,
          access: HealthConnectAccess.denied,
          missingPermissions: [],
        ),
      );
      final controller = DashboardController(repository: repository);
      addTearDown(controller.dispose);

      await Future.wait([controller.load(), controller.load()]);
      expect(repository.fetchCount, 1);
      expect(controller.snapshot!.status, DashboardDataStatus.unavailable);

      await controller.requestPermissions();
      expect(repository.requestCount, 1);
      await controller.openSettings();
      expect(repository.settingsCount, 1);
      await controller.refresh(userInitiated: true);
      expect(repository.syncCount, 1);
      expect(repository.lastSyncUserInitiated, isTrue);
    },
  );
}
