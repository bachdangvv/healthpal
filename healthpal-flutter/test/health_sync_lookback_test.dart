import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/api/api_client.dart';
import 'package:healthpal/core/auth/installation_store.dart';
import 'package:healthpal/core/auth/secure_token_store.dart';
import 'package:healthpal/core/config/app_config.dart';
import 'package:healthpal/core/database/device_settings_store.dart';
import 'package:healthpal/core/database/healthpal_database.dart';
import 'package:healthpal/core/time/app_clock.dart';
import 'package:healthpal/core/user_health_runtime.dart';
import 'package:healthpal/features/assessment/application/fatigue_engine.dart';
import 'package:healthpal/features/auth/domain/auth_user.dart';
import 'package:healthpal/features/health_connect/data/health_connect_adapter.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';
import 'package:healthpal/src/rust/types.dart' as rust;

void main() {
  const user = AuthUser(id: 'user-a', name: 'A', email: 'a@example.com');

  Future<UserHealthRuntime> runtimeOf(
    HealthPalDatabase db,
    _RecordingAdapter adapter,
  ) async {
    await DeviceSettingsStore(db).write(
      user.id,
      const DeviceSyncSettings(healthConnectSync: true, autoSync: true),
    );
    return UserHealthRuntimeFactory(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore()),
      installation: MemoryInstallationStore('device-1'),
      adapter: adapter,
      engine: _LookbackEngine(),
      canFlush: (_) async => false,
      clock: FixedAppClock(DateTime.utc(2026, 9, 30, 8)),
    ).create(user);
  }

  test(
    'missing watermark uses a 30-day lookback from local midnight',
    () async {
      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final adapter = _RecordingAdapter();
      final runtime = await runtimeOf(db, adapter);
      await runtime.coordinator.syncNow();
      expect(adapter.reads, 1);
      expect(adapter.lastStart, DateTime.utc(2026, 8, 31));
      expect(adapter.lastEnd, DateTime.utc(2026, 9, 30, 8));
      expect(
        adapter.lastEnd!.difference(adapter.lastStart!),
        greaterThanOrEqualTo(const Duration(days: 30)),
      );
    },
  );

  test('manual refresh after a watermark floors to local midnight', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final adapter = _RecordingAdapter();
    final runtime = await runtimeOf(db, adapter);
    await runtime.coordinator.syncNow();
    await runtime.coordinator.syncNow();
    expect(adapter.reads, 2);
    expect(adapter.lastStart, DateTime.utc(2026, 9, 28));
    expect(adapter.lastEnd, DateTime.utc(2026, 9, 30, 8));
    expect(
      adapter.lastEnd!.difference(adapter.lastStart!),
      greaterThanOrEqualTo(const Duration(hours: 48)),
    );
    expect(adapter.lastStart!.hour, 0);
  });

  test('fullResync reads 30 days even when a watermark exists', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final adapter = _RecordingAdapter();
    final runtime = await runtimeOf(db, adapter);
    await runtime.coordinator.syncNow();
    await runtime.coordinator.syncNow(fullResync: true);
    expect(adapter.lastStart, DateTime.utc(2026, 8, 31));
    expect(
      adapter.lastEnd!.difference(adapter.lastStart!),
      greaterThanOrEqualTo(const Duration(days: 30)),
    );
  });

  test('two concurrent syncNow calls share a single adapter read', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final adapter = _RecordingAdapter()
      ..delay = const Duration(milliseconds: 40);
    final runtime = await runtimeOf(db, adapter);
    await Future.wait([
      runtime.coordinator.syncNow(),
      runtime.coordinator.syncNow(),
    ]);
    expect(adapter.reads, 1);
  });
}

class _RecordingAdapter implements HealthConnectAdapter {
  int reads = 0;
  DateTime? lastStart;
  DateTime? lastEnd;
  Duration delay = Duration.zero;

  @override
  Future<HealthConnectCapabilities> getCapabilities() async =>
      const HealthConnectCapabilities(
        sdkAvailable: true,
        backgroundReadSupported: true,
        backgroundReadGranted: true,
      );

  @override
  Future<PermissionSnapshot> getPermissions() async => PermissionSnapshot(
    granted: HealthPermission.values.toSet(),
    missing: const {},
  );

  @override
  Future<PermissionSnapshot> requestPermissions(
    Set<HealthPermission> permissions,
  ) => getPermissions();

  @override
  Future<PermissionSnapshot> requestBackgroundRead() => getPermissions();

  @override
  Future<IngestionBatch> readRange(DateTime startUtc, DateTime endUtc) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    reads += 1;
    lastStart = startUtc;
    lastEnd = endUtc;
    return IngestionBatch(startUtc: startUtc, endUtc: endUtc);
  }

  @override
  Future<void> openSettings() async {}
}

class _LookbackEngine implements FatigueEngine {
  @override
  Future<void> ensureInitialized() async {}

  @override
  rust.ModelInfo modelInfo() => rust.ModelInfo(
    modelName: 'healthpal_fatigue',
    modelVersion: AppConfig.fatigueModelVersion,
    featureOrder: const ['placeholder'],
    windowHours: 6,
    threshold: AppConfig.fatigueDecisionThreshold,
    calibrationSlope: 0.7806493861342522,
    calibrationIntercept: -1.2659313281484506,
    lowActivityThreshold: 20,
    onnxArtifact: 'healthpal_fatigue_v4.onnx',
  );

  @override
  rust.AssessmentResult assess(rust.AssessmentRequest request) {
    return rust.AssessmentResult(
      status: rust.AssessmentStatus.insufficientData,
      features: const [],
      missingReasons: const ['missing_hr_coverage'],
      threshold: AppConfig.fatigueDecisionThreshold,
      coverageHours: 0,
      validBinCount: 0,
      modelVersion: AppConfig.fatigueModelVersion,
      featureVectorHash: 'lookback',
    );
  }
}
