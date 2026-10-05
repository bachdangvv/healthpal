import '../../../core/config/app_config.dart';
import '../../../core/database/device_settings_store.dart';
import '../../../core/database/local_health_store.dart';
import '../../../core/sync/health_sync_coordinator.dart';
import '../../../core/sync/outbox_repository.dart';
import '../../../core/time/app_clock.dart';
import '../../health_connect/data/health_connect_gateway.dart';
import '../../health_connect/domain/health_connect_failure.dart';
import '../../health_connect/domain/health_records.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/dashboard_models.dart';
import 'health_connect_repository.dart';

class LocalDashboardRepository implements HealthConnectRepository {
  LocalDashboardRepository({
    required this.userId,
    required this.store,
    required this.coordinator,
    required this.gateway,
    required this.outbox,
    required this.settings,
    this.clock = const SystemAppClock(),
  });

  final String userId;
  final LocalHealthStore store;
  final HealthSyncCoordinator coordinator;
  final HealthConnectGateway gateway;
  final SyncOutboxRepository outbox;
  final DeviceSettingsStore settings;
  final AppClock clock;

  @override
  Future<HealthConnectSnapshot> fetchSnapshot() async {
    try {
      final capabilities = await gateway.getCapabilities();
      if (!capabilities.sdkAvailable) {
        return HealthConnectSnapshot(
          availability: HealthConnectAvailability.unavailable,
          access: HealthConnectAccess.denied,
          missingPermissions: const [],
          backgroundReadSupported: capabilities.backgroundReadSupported,
          backgroundReadGranted: capabilities.backgroundReadGranted,
        );
      }
      final permissions = await gateway.getPermissions();
      final missingRequired = permissions.missing.intersection(
        PermissionSnapshot.v4Required,
      );
      final missingMetrics = [
        for (final permission in missingRequired) _metric(permission),
      ].whereType<HealthMetricPermission>().toList();
      final now = clock.now();
      final today = DateTime(now.year, now.month, now.day);
      final row = await store.dailySummaryRow(userId, today);
      final assessment = await store.latestAssessment(userId, day: today);
      final sync = await store.readSyncState(userId);
      final summary = row == null
          ? null
          : TodayHealthSummary(
              steps: row['steps'] as int?,
              sleepMinutes: row['sleep_minutes'] as int?,
              averageHeartRate: (row['average_heart_rate'] as num?)?.toDouble(),
              restingHeartRate: (row['resting_heart_rate'] as num?)?.toDouble(),
              activeCalories: (row['active_calories'] as num?)?.toDouble(),
              collectedAt:
                  sync.latestDataAtUtc ??
                  DateTime(today.year, today.month, today.day),
            );
      return HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: missingMetrics.isEmpty
            ? HealthConnectAccess.granted
            : HealthConnectAccess.missingPermissions,
        missingPermissions: missingMetrics,
        summary: summary != null && summary.hasAnyData ? summary : null,
        lastSyncedAt: sync.lastSuccessfulSyncAtUtc,
        latestDataAt: sync.latestDataAtUtc,
        fatigue: assessment,
        showExperimentalFatigue: AppConfig.experimentalFatigueAssessment,
        backgroundReadSupported: capabilities.backgroundReadSupported,
        backgroundReadGranted: capabilities.backgroundReadGranted,
        pendingOutboxCount: await outbox.pendingCount(userId),
      );
    } on HealthConnectFailure catch (error) {
      return HealthConnectSnapshot(
        availability: HealthConnectAvailability.unavailable,
        access: HealthConnectAccess.denied,
        missingPermissions: const [],
        errorMessage: error.toString(),
      );
    }
  }

  @override
  Future<HealthConnectSnapshot> requestReadPermissions() async {
    PermissionSnapshot permissions;
    try {
      permissions = await gateway.requestPermissions({
        ...PermissionSnapshot.v4Required,
        ...PermissionSnapshot.analyticsRequired,
        ...PermissionSnapshot.optionalReads,
      });
    } on HealthConnectFailure {
      return fetchSnapshot();
    }
    var local = await settings.read(userId);
    if (permissions.missing
        .intersection(PermissionSnapshot.v4Required)
        .isEmpty) {
      local = await _enableHealthConnectSync(local);
    }
    if (local.healthConnectSync) {
      await coordinator.syncNow();
    }
    return fetchSnapshot();
  }

  @override
  Future<HealthConnectSnapshot> requestBackgroundRead() async {
    try {
      await gateway.requestBackgroundRead();
    } on HealthConnectFailure {
      return fetchSnapshot();
    }
    return fetchSnapshot();
  }

  @override
  Future<void> openHealthConnectSettings() => gateway.openSettings();

  @override
  Future<HealthConnectSnapshot> syncFromHealthConnect({
    bool userInitiated = false,
  }) async {
    var local = await settings.read(userId);
    if (userInitiated && !local.healthConnectSync) {
      final permissions = await gateway.getPermissions();
      if (permissions.missing
          .intersection(PermissionSnapshot.v4Required)
          .isEmpty) {
        local = await _enableHealthConnectSync(local);
      }
    }
    if (local.healthConnectSync) {
      await coordinator.syncNow();
    }
    return fetchSnapshot();
  }

  Future<DeviceSyncSettings> _enableHealthConnectSync(
    DeviceSyncSettings current,
  ) async {
    if (current.healthConnectSync) return current;
    final enabled = DeviceSyncSettings(
      healthConnectSync: true,
      autoSync: current.autoSync,
      wifiOnly: current.wifiOnly,
    );
    await settings.write(userId, enabled);
    try {
      await coordinator.reconcileScheduler();
    } catch (_) {
      // Foreground sync must still work if background scheduling is unavailable.
    }
    return enabled;
  }

  HealthConnectStatus statusFrom(HealthConnectSnapshot snapshot) {
    if (snapshot.availability != HealthConnectAvailability.available) {
      return HealthConnectStatus.unavailable;
    }
    if (snapshot.access == HealthConnectAccess.missingPermissions ||
        snapshot.missingPermissions.isNotEmpty) {
      return HealthConnectStatus.missingPermissions;
    }
    if (snapshot.backgroundReadGranted) {
      return snapshot.status == DashboardDataStatus.connected
          ? HealthConnectStatus.connectedFresh
          : HealthConnectStatus.connectedStale;
    }
    return HealthConnectStatus.foregroundOnly;
  }

  HealthMetricPermission? _metric(HealthPermission permission) {
    return switch (permission) {
      HealthPermission.steps => HealthMetricPermission.steps,
      HealthPermission.sleep => HealthMetricPermission.sleep,
      HealthPermission.heartRate => HealthMetricPermission.heartRate,
      HealthPermission.restingHeartRate =>
        HealthMetricPermission.restingHeartRate,
      HealthPermission.activeCalories => HealthMetricPermission.activeCalories,
      HealthPermission.heartRateVariability => HealthMetricPermission.hrv,
      HealthPermission.exercise ||
      HealthPermission.healthDataInBackground => null,
    };
  }
}
