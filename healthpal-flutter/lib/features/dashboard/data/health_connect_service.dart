import 'dart:io';

import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../domain/dashboard_models.dart';
import 'health_connect_repository.dart';

class HealthConnectService implements HealthConnectRepository {
  HealthConnectService({Health? health}) : _health = health ?? Health();

  static const _settingsChannel = MethodChannel('healthpal/health_connect');
  static const _types = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  final Health _health;
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<HealthConnectSnapshot> fetchSnapshot() async {
    if (!Platform.isAndroid) {
      return const HealthConnectSnapshot(
        availability: HealthConnectAvailability.unsupported,
        access: HealthConnectAccess.denied,
        missingPermissions: [],
      );
    }
    try {
      await _configure();
      if (!await _health.isHealthConnectAvailable()) {
        return const HealthConnectSnapshot(
          availability: HealthConnectAvailability.unavailable,
          access: HealthConnectAccess.denied,
          missingPermissions: [],
        );
      }
      final missing = await _missingPermissions();
      if (missing.isNotEmpty) {
        return HealthConnectSnapshot(
          availability: HealthConnectAvailability.available,
          access: HealthConnectAccess.missingPermissions,
          missingPermissions: missing,
        );
      }
      final summary = await _readToday();
      return HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: const [],
        summary: summary,
        lastSyncedAt: DateTime.now(),
      );
    } catch (_) {
      return const HealthConnectSnapshot(
        availability: HealthConnectAvailability.unavailable,
        access: HealthConnectAccess.denied,
        missingPermissions: [],
        errorMessage: 'Không thể kết nối Health Connect trên thiết bị này.',
      );
    }
  }

  Future<List<HealthMetricPermission>> _missingPermissions() async {
    const mapping = <HealthMetricPermission, HealthDataType>{
      HealthMetricPermission.steps: HealthDataType.STEPS,
      HealthMetricPermission.sleep: HealthDataType.SLEEP_ASLEEP,
      HealthMetricPermission.heartRate: HealthDataType.HEART_RATE,
      HealthMetricPermission.restingHeartRate:
          HealthDataType.RESTING_HEART_RATE,
      HealthMetricPermission.hrv: HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      HealthMetricPermission.activeCalories:
          HealthDataType.ACTIVE_ENERGY_BURNED,
    };
    final missing = <HealthMetricPermission>[];
    for (final entry in mapping.entries) {
      final granted = await _health.hasPermissions(
        [entry.value],
        permissions: const [HealthDataAccess.READ],
      );
      if (granted != true) missing.add(entry.key);
    }
    return missing;
  }

  @override
  Future<HealthConnectSnapshot> requestReadPermissions() async {
    try {
      await _configure();
      final available = await _health.isHealthConnectAvailable();
      if (!available) return await fetchSnapshot();
      if (Platform.isAndroid) {
        await _settingsChannel.invokeMethod<bool>('requestActivityRecognition');
      }
      await _health.requestAuthorization(
        _types,
        permissions: List<HealthDataAccess>.filled(
          _types.length,
          HealthDataAccess.READ,
        ),
      );
    } catch (_) {
      // fetchSnapshot converts the current platform state to a user-facing status.
    }
    return fetchSnapshot();
  }

  @override
  Future<HealthConnectSnapshot> requestBackgroundRead() async {
    try {
      await _configure();
      await _health.requestHealthDataInBackgroundAuthorization();
    } catch (_) {
      // fetchSnapshot reports the current background-read state.
    }
    return fetchSnapshot();
  }

  Future<TodayHealthSummary?> _readToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final points = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: start,
      endTime: now,
    );
    final values = <HealthDataType, List<double>>{};
    for (final point in points) {
      final value = point.value;
      if (value is NumericHealthValue) {
        values
            .putIfAbsent(point.type, () => [])
            .add(value.numericValue.toDouble());
      }
    }
    double? average(HealthDataType type) {
      final list = values[type];
      if (list == null || list.isEmpty) return null;
      return list.reduce((a, b) => a + b) / list.length;
    }

    double? total(HealthDataType type) {
      final list = values[type];
      if (list == null || list.isEmpty) return null;
      return list.fold<double>(0, (sum, value) => sum + value);
    }

    final summary = TodayHealthSummary(
      steps: total(HealthDataType.STEPS)?.round(),
      sleepMinutes: total(HealthDataType.SLEEP_ASLEEP)?.round(),
      averageHeartRate: average(HealthDataType.HEART_RATE),
      latestHeartRate: values[HealthDataType.HEART_RATE]?.last,
      restingHeartRate: average(HealthDataType.RESTING_HEART_RATE),
      hrv: average(HealthDataType.HEART_RATE_VARIABILITY_RMSSD),
      activeCalories: total(HealthDataType.ACTIVE_ENERGY_BURNED),
      collectedAt: now,
    );
    return summary.hasAnyData ? summary : null;
  }

  @override
  Future<void> openHealthConnectSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _settingsChannel.invokeMethod<void>('openSettings');
    } catch (_) {
      // The permission dialog remains available as the fallback action.
    }
  }

  @override
  Future<HealthConnectSnapshot> syncFromHealthConnect({
    bool userInitiated = false,
  }) => fetchSnapshot();
}
