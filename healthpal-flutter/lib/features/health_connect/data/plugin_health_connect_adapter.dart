import 'dart:io';

import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../application/health_data_point_mapper.dart';
import '../domain/health_connect_failure.dart';
import '../domain/health_records.dart';
import 'health_connect_adapter.dart';

class PluginHealthConnectAdapter implements HealthConnectAdapter {
  PluginHealthConnectAdapter({Health? health}) : _health = health ?? Health();

  static const _settingsChannel = MethodChannel('healthpal/health_connect');

  static const _requiredTypes = <HealthPermission, HealthDataType>{
    HealthPermission.steps: HealthDataType.STEPS,
    HealthPermission.sleep: HealthDataType.SLEEP_ASLEEP,
    HealthPermission.heartRate: HealthDataType.HEART_RATE,
    HealthPermission.restingHeartRate: HealthDataType.RESTING_HEART_RATE,
    HealthPermission.activeCalories: HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthPermission.exercise: HealthDataType.WORKOUT,
    HealthPermission.heartRateVariability:
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
  };

  static const _readTypes = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
  ];

  final Health _health;
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<HealthConnectCapabilities> getCapabilities() async {
    if (!Platform.isAndroid) {
      return const HealthConnectCapabilities(
        sdkAvailable: false,
        backgroundReadSupported: false,
      );
    }
    await _configure();
    final available = await _health.isHealthConnectAvailable();
    if (!available) {
      return const HealthConnectCapabilities(
        sdkAvailable: false,
        backgroundReadSupported: false,
        backgroundReadGranted: false,
      );
    }
    var supported = false;
    var granted = false;
    try {
      supported = await _health.isHealthDataInBackgroundAvailable();
      granted = supported && await _health.isHealthDataInBackgroundAuthorized();
    } catch (_) {
      supported = false;
      granted = false;
    }
    return HealthConnectCapabilities(
      sdkAvailable: true,
      backgroundReadSupported: supported,
      backgroundReadGranted: granted,
    );
  }

  @override
  Future<PermissionSnapshot> getPermissions() async {
    await _configure();
    if (!Platform.isAndroid || !await _health.isHealthConnectAvailable()) {
      throw const HealthConnectFailure(HealthConnectFailureCode.unavailable);
    }
    final granted = <HealthPermission>{};
    final missing = <HealthPermission>{};
    for (final entry in _requiredTypes.entries) {
      final ok = await _health.hasPermissions(
        [entry.value],
        permissions: const [HealthDataAccess.READ],
      );
      if (ok == true) {
        granted.add(entry.key);
      } else {
        missing.add(entry.key);
      }
    }
    try {
      final background = await _health.isHealthDataInBackgroundAuthorized();
      if (background == true) {
        granted.add(HealthPermission.healthDataInBackground);
      } else {
        missing.add(HealthPermission.healthDataInBackground);
      }
    } catch (_) {
      missing.add(HealthPermission.healthDataInBackground);
    }
    return PermissionSnapshot(granted: granted, missing: missing);
  }

  @override
  Future<PermissionSnapshot> requestPermissions(
    Set<HealthPermission> permissions,
  ) async {
    await _configure();
    if (Platform.isAndroid) {
      await _settingsChannel.invokeMethod<bool>('requestActivityRecognition');
    }
    final types = permissions
        .where(
          (permission) => permission != HealthPermission.healthDataInBackground,
        )
        .map((permission) => _requiredTypes[permission])
        .whereType<HealthDataType>()
        .toList();
    if (types.isNotEmpty) {
      await _health.requestAuthorization(
        types,
        permissions: List<HealthDataAccess>.filled(
          types.length,
          HealthDataAccess.READ,
        ),
      );
    }
    if (permissions.contains(HealthPermission.healthDataInBackground)) {
      await _health.requestHealthDataInBackgroundAuthorization();
    }
    return getPermissions();
  }

  @override
  Future<PermissionSnapshot> requestBackgroundRead() {
    return requestPermissions({HealthPermission.healthDataInBackground});
  }

  @override
  Future<IngestionBatch> readRange(DateTime startUtc, DateTime endUtc) async {
    await _configure();
    final points = await _health.getHealthDataFromTypes(
      types: _readTypes,
      startTime: startUtc.toUtc(),
      endTime: endUtc.toUtc(),
    );
    return const HealthDataPointMapper().mapRange(
      startUtc: startUtc,
      endUtc: endUtc,
      points: [
        for (final point in points)
          MappedHealthPoint(
            type: point.type.name,
            sourceId: point.sourceId,
            sourceName: point.sourceName,
            uuid: point.uuid,
            dateFrom: point.dateFrom,
            dateTo: point.dateTo,
            numericValue: _numeric(point),
            workoutActivityName: point.value is WorkoutHealthValue
                ? (point.value as WorkoutHealthValue).workoutActivityType.name
                : null,
            workoutCalories: point.value is WorkoutHealthValue
                ? (point.value as WorkoutHealthValue).totalEnergyBurned
                      ?.toDouble()
                : null,
          ),
      ],
    );
  }

  @override
  Future<void> openSettings() async {
    if (!Platform.isAndroid) {
      throw const HealthConnectFailure(HealthConnectFailureCode.unsupported);
    }
    try {
      await _settingsChannel.invokeMethod<void>('openSettings');
    } catch (error) {
      throw HealthConnectFailure(
        HealthConnectFailureCode.unavailable,
        message: error.toString(),
      );
    }
  }

  double? _numeric(HealthDataPoint point) {
    final value = point.value;
    if (value is NumericHealthValue) return value.numericValue.toDouble();
    return null;
  }
}
