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
import 'package:healthpal/features/assessment/domain/fatigue_assessment.dart';
import 'package:healthpal/features/auth/domain/auth_user.dart';
import 'package:healthpal/features/health_connect/data/health_connect_adapter.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';
import 'package:healthpal/features/history/domain/daily_health_summary.dart';
import 'package:healthpal/src/rust/types.dart' as rust;

const source = SourceInfo(
  sourceId: 'healthsync.huawei',
  sourceName: 'Health Sync',
);

final fixtureClock = FixedAppClock(DateTime.utc(2026, 9, 30, 8));

void main() {
  test(
    'authenticated user pipeline persists canonical rows, assessment and outbox',
    () async {
      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final adapter = _FakeAdapter(_goldenBatch());
      final settings = DeviceSettingsStore(db);
      await settings.write(
        'user-a',
        const DeviceSyncSettings(healthConnectSync: true, autoSync: true),
      );
      final engine = _FakeEngine();
      final factory = UserHealthRuntimeFactory(
        database: db,
        client: ApiClient(tokenStore: MemoryTokenStore()),
        installation: MemoryInstallationStore('device-1'),
        adapter: adapter,
        engine: engine,
        canFlush: (_) async => false,
        clock: fixtureClock,
      );
      final runtime = factory.create(
        const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'),
      );

      final state = await runtime.coordinator.syncNow();
      expect(state.lastError, isNull);
      expect(state.lastSuccessfulSyncAtUtc, isNotNull);
      expect(adapter.reads, 1);
      expect(engine.lastRequest, isNotNull);
      expect(engine.lastRequest!.dataWatermarkUtc, isNotNull);
      expect(
        engine.lastRequest!.dataWatermarkUtc,
        engine.lastRequest!.evaluationTimeUtc,
      );
      expect(state.sourceWatermarkUtc, engine.lastRequest!.evaluationTimeUtc);
      expect(state.latestDataAtUtc, isNotNull);

      expect(await db.count('heart_rate_samples', 'user-a'), greaterThan(0));
      expect(await db.count('step_intervals', 'user-a'), greaterThan(0));
      expect(await db.count('sleep_sessions', 'user-a'), 1);
      expect(await db.count('hourly_health_bins', 'user-a'), greaterThan(0));
      expect(
        await db.count('daily_health_summaries', 'user-a'),
        greaterThan(0),
      );
      final dailyRows = await runtime.store.dailySummaryRows(
        'user-a',
        start: DateTime(2026, 9, 28),
        end: DateTime(2026, 9, 30),
      );
      expect(
        dailyRows.any((row) => (row['sleep_minutes'] as int? ?? 0) > 0),
        isTrue,
      );
      expect(await db.count('fatigue_assessments', 'user-a'), 1);
      expect(await db.count('outbox_events', 'user-a'), 1);
      expect(runtime.store.replaceCanonicalWindowCount, 1);

      final assessment = await runtime.store.latestAssessment('user-a');
      expect(assessment?.status, FatigueAssessmentStatus.signalDetected);
      expect(assessment?.calibratedProbability, 0.35);
      expect(assessment?.createdBy, AssessmentCreatedBy.foreground);

      final snapshot = await runtime.dashboard.fetchSnapshot();
      expect(snapshot.fatigue?.calibratedProbability, 0.35);
      expect(snapshot.summary?.steps, isNotNull);

      final history = await runtime.history.fetch(HistoryPeriod.sevenDays);
      expect(history, hasLength(7));
      expect(history.any((day) => day.steps != null), isTrue);
      expect(history.any((day) => day.steps == null), isTrue);

      await settings.write(
        'user-b',
        const DeviceSyncSettings(healthConnectSync: true),
      );
      final other = factory.create(
        const AuthUser(id: 'user-b', name: 'B', email: 'b@example.com'),
      );
      final otherHistory = await other.history.fetch(HistoryPeriod.sevenDays);
      expect(otherHistory.every((day) => day.steps == null), isTrue);
      expect(await db.count('fatigue_assessments', 'user-b'), 0);
    },
  );

  test(
    'second sync without newer samples keeps no_new_data protection',
    () async {
      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final adapter = _FakeAdapter(_goldenBatch());
      final engine = _FakeEngine();
      await DeviceSettingsStore(
        db,
      ).write('user-a', const DeviceSyncSettings(healthConnectSync: true));
      final runtime = UserHealthRuntimeFactory(
        database: db,
        client: ApiClient(tokenStore: MemoryTokenStore()),
        installation: MemoryInstallationStore('device-1'),
        adapter: adapter,
        engine: engine,
        canFlush: (_) async => false,
        clock: fixtureClock,
      ).create(const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'));

      await runtime.coordinator.syncNow();
      expect(engine.lastRequest!.previousAssessmentWatermarkUtc, isNull);
      await runtime.coordinator.syncNow();
      expect(engine.lastRequest!.previousAssessmentWatermarkUtc, isNotNull);
      expect(
        engine.lastResult!.missingReasons,
        contains('no_new_data_since_previous'),
      );
    },
  );

  test(
    'granting read permission enables sync and immediately imports health data',
    () async {
      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final adapter = _FakeAdapter(_goldenBatch());
      final settings = DeviceSettingsStore(db);
      final runtime = UserHealthRuntimeFactory(
        database: db,
        client: ApiClient(tokenStore: MemoryTokenStore()),
        installation: MemoryInstallationStore('device-1'),
        adapter: adapter,
        engine: _FakeEngine(),
        canFlush: (_) async => false,
        clock: fixtureClock,
      ).create(const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'));

      expect((await settings.read('user-a')).healthConnectSync, isFalse);
      final snapshot = await runtime.dashboard.requestReadPermissions();

      expect((await settings.read('user-a')).healthConnectSync, isTrue);
      expect(adapter.reads, 1);
      expect(snapshot.summary?.steps, isNotNull);
    },
  );

  test(
    'manual health sync repairs an already-authorized disabled state',
    () async {
      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final adapter = _FakeAdapter(_goldenBatch());
      final settings = DeviceSettingsStore(db);
      final runtime = UserHealthRuntimeFactory(
        database: db,
        client: ApiClient(tokenStore: MemoryTokenStore()),
        installation: MemoryInstallationStore('device-1'),
        adapter: adapter,
        engine: _FakeEngine(),
        canFlush: (_) async => false,
        clock: fixtureClock,
      ).create(const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'));

      final snapshot = await runtime.dashboard.syncFromHealthConnect(
        userInitiated: true,
      );

      expect((await settings.read('user-a')).healthConnectSync, isTrue);
      expect(adapter.reads, 1);
      expect(snapshot.summary?.steps, isNotNull);
    },
  );

  test('missing V4 permissions do not read Health Connect', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final adapter = _FakeAdapter(
      _goldenBatch(),
      missing: {HealthPermission.heartRate},
    );
    await DeviceSettingsStore(
      db,
    ).write('user-a', const DeviceSyncSettings(healthConnectSync: true));
    final runtime = UserHealthRuntimeFactory(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore()),
      installation: MemoryInstallationStore(),
      adapter: adapter,
      engine: _FakeEngine(),
      canFlush: (_) async => false,
      clock: fixtureClock,
    ).create(const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'));

    final state = await runtime.coordinator.syncNow();
    expect(state.lastError, 'missing_permissions');
    expect(adapter.reads, 0);
    expect(await db.count('heart_rate_samples', 'user-a'), 0);
  });

  test('dashboard clock on 1 Oct does not read the 30 Sep summary', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    await DeviceSettingsStore(
      db,
    ).write('user-a', const DeviceSyncSettings(healthConnectSync: true));
    final seeded = UserHealthRuntimeFactory(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore()),
      installation: MemoryInstallationStore('device-1'),
      adapter: _FakeAdapter(_goldenBatch()),
      engine: _FakeEngine(),
      canFlush: (_) async => false,
      clock: fixtureClock,
    ).create(const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'));
    await seeded.coordinator.syncNow();
    expect((await seeded.dashboard.fetchSnapshot()).summary?.steps, isNotNull);

    final october = UserHealthRuntimeFactory(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore()),
      installation: MemoryInstallationStore('device-1'),
      adapter: _FakeAdapter(_goldenBatch()),
      engine: _FakeEngine(),
      canFlush: (_) async => false,
      clock: FixedAppClock(DateTime.utc(2026, 10, 1, 8)),
    ).create(const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'));
    expect((await october.dashboard.fetchSnapshot()).summary?.steps, isNull);
    final history = await october.history.fetch(HistoryPeriod.sevenDays);
    expect(history, hasLength(7));
    expect(history.first.date, DateTime(2026, 10, 1));
  });

  test('two fixed clocks in one process stay independent', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    await DeviceSettingsStore(
      db,
    ).write('user-a', const DeviceSyncSettings(healthConnectSync: true));
    await UserHealthRuntimeFactory(
          database: db,
          client: ApiClient(tokenStore: MemoryTokenStore()),
          installation: MemoryInstallationStore('device-1'),
          adapter: _FakeAdapter(_goldenBatch()),
          engine: _FakeEngine(),
          canFlush: (_) async => false,
          clock: fixtureClock,
        )
        .create(const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'))
        .coordinator
        .syncNow();

    final sept = UserHealthRuntimeFactory(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore()),
      installation: MemoryInstallationStore('device-1'),
      adapter: _FakeAdapter(_goldenBatch()),
      engine: _FakeEngine(),
      canFlush: (_) async => false,
      clock: fixtureClock,
    ).create(const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'));
    final oct = UserHealthRuntimeFactory(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore()),
      installation: MemoryInstallationStore('device-1'),
      adapter: _FakeAdapter(_goldenBatch()),
      engine: _FakeEngine(),
      canFlush: (_) async => false,
      clock: FixedAppClock(DateTime.utc(2026, 10, 1, 8)),
    ).create(const AuthUser(id: 'user-a', name: 'A', email: 'a@example.com'));

    expect((await sept.dashboard.fetchSnapshot()).summary?.steps, isNotNull);
    expect((await oct.dashboard.fetchSnapshot()).summary?.steps, isNull);
    expect(
      (await sept.history.fetch(HistoryPeriod.sevenDays)).first.date,
      DateTime(2026, 9, 30),
    );
    expect((await oct.history.fetch(HistoryPeriod.thirtyDays)).length, 30);
  });
}

IngestionBatch _goldenBatch() {
  final start = DateTime.utc(2026, 9, 30, 2);
  final end = DateTime.utc(2026, 9, 30, 8);
  return IngestionBatch(
    startUtc: start,
    endUtc: end,
    heartRateSamples: [
      for (var i = 0; i < 12; i++)
        HeartRateSample(
          recordId: 'hr$i',
          startUtc: start.add(Duration(minutes: 20 * i)),
          endUtc: start.add(Duration(minutes: 20 * i)),
          zoneOffsetMinutes: 0,
          bpm: 62 + i.toDouble(),
          source: source,
        ),
    ],
    stepIntervals: [
      StepInterval(
        recordId: 'st1',
        startUtc: DateTime.utc(2026, 9, 30, 7),
        endUtc: DateTime.utc(2026, 9, 30, 8),
        zoneOffsetMinutes: 0,
        count: 1800,
        source: source,
      ),
    ],
    restingHeartRateRecords: [
      RestingHeartRateRecord(
        recordId: 'rhr',
        recordedAtUtc: DateTime.utc(2026, 9, 29, 23),
        zoneOffsetMinutes: 0,
        localDate: DateTime.utc(2026, 9, 29),
        bpm: 58,
        source: source,
      ),
    ],
    sleepSessions: [
      SleepSession(
        recordId: 'sleep',
        startUtc: DateTime.utc(2026, 9, 29, 16),
        endUtc: DateTime.utc(2026, 9, 29, 23),
        zoneOffsetMinutes: 0,
        healthDay: DateTime.utc(2026, 9, 30),
        stages: [
          SleepStage(
            recordId: 'l',
            startUtc: DateTime.utc(2026, 9, 29, 16),
            endUtc: DateTime.utc(2026, 9, 29, 20),
            type: SleepStageType.light,
            source: source,
          ),
          SleepStage(
            recordId: 'd',
            startUtc: DateTime.utc(2026, 9, 29, 20),
            endUtc: DateTime.utc(2026, 9, 29, 22),
            type: SleepStageType.deep,
            source: source,
          ),
          SleepStage(
            recordId: 'r',
            startUtc: DateTime.utc(2026, 9, 29, 22),
            endUtc: DateTime.utc(2026, 9, 29, 23),
            type: SleepStageType.rem,
            source: source,
          ),
        ],
        source: source,
      ),
    ],
    exerciseSessions: [
      ExerciseSession(
        recordId: 'ex',
        startUtc: DateTime.utc(2026, 9, 30, 1),
        endUtc: DateTime.utc(2026, 9, 30, 1, 30),
        zoneOffsetMinutes: 0,
        type: 'walking',
        durationMinutes: 30,
        calories: 90,
        source: source,
      ),
    ],
    activeCaloriesIntervals: [
      ActiveCaloriesInterval(
        recordId: 'cal',
        startUtc: DateTime.utc(2026, 9, 30, 7),
        endUtc: DateTime.utc(2026, 9, 30, 8),
        zoneOffsetMinutes: 0,
        kilocalories: 120,
        source: source,
      ),
    ],
  );
}

class _FakeAdapter implements HealthConnectAdapter {
  _FakeAdapter(this.batch, {this.missing = const {}});

  final IngestionBatch batch;
  final Set<HealthPermission> missing;
  int reads = 0;
  DateTime? lastStart;
  DateTime? lastEnd;

  @override
  Future<HealthConnectCapabilities> getCapabilities() async =>
      const HealthConnectCapabilities(
        sdkAvailable: true,
        backgroundReadSupported: true,
        backgroundReadGranted: true,
      );

  @override
  Future<PermissionSnapshot> getPermissions() async {
    final granted = HealthPermission.values.toSet().difference(missing);
    return PermissionSnapshot(granted: granted, missing: missing);
  }

  @override
  Future<PermissionSnapshot> requestPermissions(
    Set<HealthPermission> permissions,
  ) => getPermissions();

  @override
  Future<PermissionSnapshot> requestBackgroundRead() => getPermissions();

  @override
  Future<IngestionBatch> readRange(DateTime startUtc, DateTime endUtc) async {
    reads += 1;
    lastStart = startUtc;
    lastEnd = endUtc;
    return batch;
  }

  @override
  Future<void> openSettings() async {}
}

class _FakeEngine implements FatigueEngine {
  rust.AssessmentRequest? lastRequest;
  rust.AssessmentResult? lastResult;

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
    lastRequest = request;
    if (request.previousAssessmentWatermarkUtc != null) {
      lastResult = rust.AssessmentResult(
        status: rust.AssessmentStatus.insufficientData,
        features: const [],
        missingReasons: const ['no_new_data_since_previous'],
        threshold: AppConfig.fatigueDecisionThreshold,
        coverageHours: 6,
        validBinCount: 6,
        latestSampleAtUtc: DateTime.utc(2026, 9, 30, 8),
        dataFreshnessMinutes: 5,
        modelVersion: AppConfig.fatigueModelVersion,
        featureVectorHash: 'fixture-hash',
      );
      return lastResult!;
    }
    lastResult = rust.AssessmentResult(
      status: rust.AssessmentStatus.signalDetected,
      features: const [],
      missingReasons: const [],
      baseProbability: 0.4,
      calibratedProbability: 0.35,
      threshold: AppConfig.fatigueDecisionThreshold,
      coverageHours: 6,
      validBinCount: 6,
      latestSampleAtUtc: DateTime.utc(2026, 9, 30, 8),
      dataFreshnessMinutes: 5,
      modelVersion: AppConfig.fatigueModelVersion,
      featureVectorHash: 'fixture-hash',
    );
    return lastResult!;
  }
}
