import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/health_connect/application/aggregator.dart';
import 'package:healthpal/features/health_connect/application/canonicalizer.dart';
import 'package:healthpal/features/health_connect/application/sync_orchestrator.dart';
import 'package:healthpal/features/health_connect/application/sync_window.dart';
import 'package:healthpal/features/health_connect/data/health_connect_adapter.dart';
import 'package:healthpal/features/health_connect/data/health_connect_gateway.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';

const sourceA = SourceInfo(
  sourceId: 'healthsync.huawei',
  sourceName: 'Health Sync',
);
const sourceB = SourceInfo(sourceId: 'phone.steps', sourceName: 'Phone');

void main() {
  const canonicalizer = HealthRecordCanonicalizer();
  const aggregator = HealthAggregator();

  test('dedupes UUID and hash duplicates without double counting', () {
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 29),
      endUtc: DateTime.utc(2026, 9, 30),
      stepIntervals: [
        StepInterval(
          recordId: 's1',
          startUtc: DateTime.utc(2026, 9, 29, 1),
          endUtc: DateTime.utc(2026, 9, 29, 2),
          zoneOffsetMinutes: 420,
          count: 100,
          source: sourceA,
        ),
        StepInterval(
          recordId: 's1',
          startUtc: DateTime.utc(2026, 9, 29, 1),
          endUtc: DateTime.utc(2026, 9, 29, 2),
          zoneOffsetMinutes: 420,
          count: 100,
          source: sourceA,
        ),
        StepInterval(
          recordId: 's2',
          startUtc: DateTime.utc(2026, 9, 29, 1),
          endUtc: DateTime.utc(2026, 9, 29, 2),
          zoneOffsetMinutes: 420,
          count: 100,
          source: sourceA,
        ),
      ],
    );
    final result = canonicalizer.canonicalize(batch);
    expect(result.batch.stepIntervals, hasLength(1));
    expect(result.droppedDuplicates, 2);
  });

  test('rejects implausible HR without logging the value', () {
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 30, 8),
      endUtc: DateTime.utc(2026, 9, 30, 10),
      heartRateSamples: [
        HeartRateSample(
          recordId: 'ok',
          startUtc: DateTime.utc(2026, 9, 30, 9),
          endUtc: DateTime.utc(2026, 9, 30, 9),
          zoneOffsetMinutes: 0,
          bpm: 72,
          source: sourceA,
        ),
        HeartRateSample(
          recordId: 'low',
          startUtc: DateTime.utc(2026, 9, 30, 9, 1),
          endUtc: DateTime.utc(2026, 9, 30, 9, 1),
          zoneOffsetMinutes: 0,
          bpm: 12,
          source: sourceA,
        ),
        HeartRateSample(
          recordId: 'high',
          startUtc: DateTime.utc(2026, 9, 30, 9, 2),
          endUtc: DateTime.utc(2026, 9, 30, 9, 2),
          zoneOffsetMinutes: 0,
          bpm: 280,
          source: sourceA,
        ),
      ],
    );
    final result = canonicalizer.canonicalize(batch);
    expect(result.rejectedHeartRate, 2);
    expect(result.batch.heartRateSamples, hasLength(1));
  });

  test('splits step intervals across hour boundaries and preserves totals', () {
    final interval = StepInterval(
      recordId: 'cross',
      startUtc: DateTime.utc(2026, 9, 30, 9, 50),
      endUtc: DateTime.utc(2026, 9, 30, 10, 10),
      zoneOffsetMinutes: 0,
      count: 683,
      source: sourceA,
    );
    final slices = aggregator.splitStepsAcrossHours(interval);
    expect(slices.fold<int>(0, (sum, slice) => sum + slice.count), 683);
    expect(slices, hasLength(2));
  });

  test('sleep crossing midnight uses local end date as healthDay', () {
    final session = SleepSession(
      recordId: 'sleep1',
      startUtc: DateTime.utc(2026, 9, 28, 15),
      endUtc: DateTime.utc(2026, 9, 28, 23, 30),
      zoneOffsetMinutes: 420,
      healthDay: DateTime(2026, 9, 29),
      stages: [
        SleepStage(
          startUtc: DateTime.utc(2026, 9, 28, 15, 20),
          endUtc: DateTime.utc(2026, 9, 28, 23, 30),
          type: SleepStageType.light,
        ),
      ],
      source: sourceA,
    );
    expect(session.healthDay, DateTime(2026, 9, 29));
    expect(session.sleepMinutes, 490);
    expect(
      canonicalSleepForDay(
        sessions: [session],
        healthDay: DateTime(2026, 9, 29),
        preferredSourceId: sourceA.sourceId,
      )?.recordId,
      'sleep1',
    );
  });

  test('overlapping sources use only the preferred source for steps', () {
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 30, 1),
      endUtc: DateTime.utc(2026, 9, 30, 3),
      stepIntervals: [
        StepInterval(
          recordId: 'a',
          startUtc: DateTime.utc(2026, 9, 30, 1),
          endUtc: DateTime.utc(2026, 9, 30, 2),
          zoneOffsetMinutes: 0,
          count: 100,
          source: sourceA,
        ),
        StepInterval(
          recordId: 'b',
          startUtc: DateTime.utc(2026, 9, 30, 1),
          endUtc: DateTime.utc(2026, 9, 30, 2),
          zoneOffsetMinutes: 0,
          count: 80,
          source: sourceB,
        ),
      ],
    );
    final bins = aggregator.hourlyBins(
      batch,
      preferredSourceId: sourceA.sourceId,
    );
    expect(bins.single.steps, 100);
  });

  test(
    'missing steps stay null until completeness watermark passes the bin',
    () {
      final batch = IngestionBatch(
        startUtc: DateTime.utc(2026, 9, 30),
        endUtc: DateTime.utc(2026, 9, 30, 2),
        heartRateSamples: [
          HeartRateSample(
            recordId: 'hr',
            startUtc: DateTime.utc(2026, 9, 30, 0, 10),
            endUtc: DateTime.utc(2026, 9, 30, 0, 10),
            zoneOffsetMinutes: 0,
            bpm: 70,
            source: sourceA,
          ),
        ],
      );
      final bins = aggregator.hourlyBins(
        batch,
        preferredSourceId: sourceA.sourceId,
        completenessWatermarkUtc: DateTime.utc(2026, 9, 30, 0, 30),
      );
      expect(bins.single.steps, isNull);
      expect(bins.single.coverageComplete, isFalse);
    },
  );

  test('orchestrator single-flights concurrent triggers', () async {
    final adapter = _SlowAdapter();
    final orchestrator = SyncOrchestrator(
      gateway: HealthConnectGateway(adapter: adapter),
    );
    final now = DateTime.utc(2026, 9, 30, 10);
    final first = orchestrator.syncNow(nowUtc: now, firstSync: true);
    final second = orchestrator.syncNow(nowUtc: now, firstSync: true);
    await Future.wait([first, second]);
    expect(adapter.reads, 1);
  });

  test('missing required permissions skip Health Connect reads', () async {
    final adapter = _SlowAdapter()
      ..granted = {
        HealthPermission.steps,
        HealthPermission.sleep,
        HealthPermission.restingHeartRate,
      };
    final orchestrator = SyncOrchestrator(
      gateway: HealthConnectGateway(adapter: adapter),
    );
    final state = await orchestrator.syncNow(
      nowUtc: DateTime.utc(2026, 9, 30, 10),
      firstSync: true,
    );
    expect(state.lastError, 'missing_permissions');
    expect(adapter.reads, 0);
  });

  test(
    'orchestrator keeps overlapping raw records but bounds aggregates',
    () async {
      final window = SyncReplacementWindow(
        startUtc: DateTime.utc(2026, 9, 27, 17),
        endUtcExclusive: DateTime.utc(2026, 9, 30, 8, 30),
        localDateStart: DateTime(2026, 9, 28),
        localDateEndExclusive: DateTime(2026, 10, 1),
        timezoneOffsetMinutes: 420,
      );
      final batch = IngestionBatch(
        startUtc: window.startUtc,
        endUtc: window.endUtcExclusive,
        stepIntervals: [
          StepInterval(
            recordId: 'steps-cross-start',
            startUtc: DateTime.utc(2026, 9, 27, 16, 30),
            endUtc: DateTime.utc(2026, 9, 27, 17, 30),
            zoneOffsetMinutes: 420,
            count: 600,
            source: sourceA,
          ),
        ],
        exerciseSessions: [
          ExerciseSession(
            recordId: 'exercise-cross-start',
            startUtc: DateTime.utc(2026, 9, 27, 16, 45),
            endUtc: DateTime.utc(2026, 9, 27, 17, 15),
            zoneOffsetMinutes: 420,
            type: 'workout',
            durationMinutes: 30,
            source: sourceA,
          ),
        ],
        activeCaloriesIntervals: [
          ActiveCaloriesInterval(
            recordId: 'calories-cross-end',
            startUtc: DateTime.utc(2026, 9, 30, 8, 15),
            endUtc: DateTime.utc(2026, 9, 30, 9, 15),
            zoneOffsetMinutes: 420,
            kilocalories: 120,
            source: sourceA,
          ),
        ],
      );
      final adapter = _BatchAdapter(batch);
      List<HourlyBin>? persistedBins;
      List<DailyAggregate>? persistedDays;
      CanonicalIngestion? persistedCanonical;
      final orchestrator = SyncOrchestrator(
        gateway: HealthConnectGateway(adapter: adapter),
        onPersist:
            ({
              required canonical,
              required bins,
              required days,
              required state,
              required window,
            }) async {
              persistedCanonical = canonical;
              persistedBins = bins;
              persistedDays = days;
            },
      );

      final state = await orchestrator.syncNow(
        nowUtc: window.endUtcExclusive,
        firstSync: false,
        timezoneOffsetMinutes: 420,
        replacementWindow: window,
      );

      expect(state.lastError, isNull);
      expect(persistedCanonical!.batch.stepIntervals, hasLength(1));
      expect(persistedCanonical!.batch.exerciseSessions, hasLength(1));
      expect(persistedCanonical!.batch.activeCaloriesIntervals, hasLength(1));
      expect(persistedBins, isNotEmpty);
      expect(
        persistedBins!.every((bin) => window.containsUtc(bin.hourUtc)),
        isTrue,
      );
      expect(
        persistedBins!.map((bin) => bin.hourUtc),
        containsAll(<DateTime>[
          DateTime.utc(2026, 9, 27, 17),
          DateTime.utc(2026, 9, 30, 8),
        ]),
      );
      expect(persistedDays, isNotEmpty);
      expect(
        persistedDays!.every((day) => window.containsLocalDate(day.localDate)),
        isTrue,
      );
      expect(
        persistedDays!.map((day) => day.localDate),
        isNot(contains(DateTime(2026, 9, 27))),
      );
    },
  );
}

class _SlowAdapter implements HealthConnectAdapter {
  int reads = 0;
  Set<HealthPermission> granted = HealthPermission.values.toSet();

  @override
  Future<HealthConnectCapabilities> getCapabilities() async =>
      const HealthConnectCapabilities(
        sdkAvailable: true,
        backgroundReadSupported: false,
      );

  @override
  Future<PermissionSnapshot> getPermissions() async {
    final missing = HealthPermission.values.toSet().difference(granted);
    return PermissionSnapshot(granted: granted, missing: missing);
  }

  @override
  Future<void> openSettings() async {}

  @override
  Future<IngestionBatch> readRange(DateTime startUtc, DateTime endUtc) async {
    reads += 1;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return IngestionBatch(startUtc: startUtc, endUtc: endUtc);
  }

  @override
  Future<PermissionSnapshot> requestPermissions(
    Set<HealthPermission> permissions,
  ) async => getPermissions();

  @override
  Future<PermissionSnapshot> requestBackgroundRead() async => getPermissions();
}

class _BatchAdapter implements HealthConnectAdapter {
  _BatchAdapter(this.batch);

  final IngestionBatch batch;

  @override
  Future<HealthConnectCapabilities> getCapabilities() async =>
      const HealthConnectCapabilities(
        sdkAvailable: true,
        backgroundReadSupported: false,
      );

  @override
  Future<PermissionSnapshot> getPermissions() async => PermissionSnapshot(
    granted: HealthPermission.values.toSet(),
    missing: const {},
  );

  @override
  Future<void> openSettings() async {}

  @override
  Future<IngestionBatch> readRange(DateTime startUtc, DateTime endUtc) async =>
      batch;

  @override
  Future<PermissionSnapshot> requestPermissions(
    Set<HealthPermission> permissions,
  ) async => getPermissions();

  @override
  Future<PermissionSnapshot> requestBackgroundRead() async => getPermissions();
}
