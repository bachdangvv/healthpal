import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/database/healthpal_database.dart';
import 'package:healthpal/core/database/local_health_store.dart';
import 'package:healthpal/core/sync/sync_state.dart';
import 'package:healthpal/features/health_connect/application/aggregator.dart';
import 'package:healthpal/features/health_connect/application/canonicalizer.dart';
import 'package:healthpal/features/health_connect/application/health_data_point_mapper.dart';
import 'package:healthpal/features/health_connect/application/sync_window.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';
import 'package:healthpal/features/health_connect/domain/sleep_normalizer.dart';

const healthSyncPackage = 'com.github.yourapp.healthsync';

MappedHealthPoint hrPoint({
  required String uuid,
  required DateTime at,
  required double bpm,
  String sourceId = '',
  String sourceName = healthSyncPackage,
}) {
  return MappedHealthPoint(
    type: 'HEART_RATE',
    sourceId: sourceId,
    sourceName: sourceName,
    uuid: uuid,
    dateFrom: at,
    dateTo: at,
    numericValue: bpm,
  );
}

MappedHealthPoint stagePoint({
  required String uuid,
  required String type,
  required DateTime start,
  required DateTime end,
  String sourceId = '',
  String sourceName = healthSyncPackage,
}) {
  return MappedHealthPoint(
    type: type,
    sourceId: sourceId,
    sourceName: sourceName,
    uuid: uuid,
    dateFrom: start,
    dateTo: end,
  );
}

void main() {
  const mapper = HealthDataPointMapper();
  const canonicalizer = HealthRecordCanonicalizer();
  const aggregator = HealthAggregator();

  test(
    'same parent UUID heart-rate samples keep distinct deterministic ids',
    () {
      final t1 = DateTime.utc(2026, 9, 30, 8, 0);
      final t2 = DateTime.utc(2026, 9, 30, 8, 1);
      final first = mapper.mapRange(
        startUtc: DateTime.utc(2026, 9, 30, 7),
        endUtc: DateTime.utc(2026, 9, 30, 9),
        points: [
          hrPoint(uuid: 'parent-hr', at: t1, bpm: 62),
          hrPoint(uuid: 'parent-hr', at: t2, bpm: 64),
        ],
      );
      expect(first.heartRateSamples, hasLength(2));
      expect(
        first.heartRateSamples[0].recordId,
        isNot(first.heartRateSamples[1].recordId),
      );
      expect(first.heartRateSamples[0].source.sourceId, healthSyncPackage);

      final second = mapper.mapRange(
        startUtc: DateTime.utc(2026, 9, 30, 7),
        endUtc: DateTime.utc(2026, 9, 30, 9),
        points: [
          hrPoint(uuid: 'parent-hr', at: t1, bpm: 62),
          hrPoint(uuid: 'parent-hr', at: t2, bpm: 64),
        ],
      );
      expect(
        second.heartRateSamples.map((item) => item.recordId).toSet(),
        first.heartRateSamples.map((item) => item.recordId).toSet(),
      );

      final canonical = canonicalizer.canonicalize(first);
      expect(canonical.batch.heartRateSamples, hasLength(2));
    },
  );

  test(
    'corrected BPM keeps the same HR identity and updates one row',
    () async {
      final t1 = DateTime.utc(2026, 9, 30, 8);
      final first = mapper.mapRange(
        startUtc: DateTime.utc(2026, 9, 30, 7),
        endUtc: DateTime.utc(2026, 9, 30, 9),
        points: [hrPoint(uuid: 'parent-hr', at: t1, bpm: 62)],
      );
      final second = mapper.mapRange(
        startUtc: DateTime.utc(2026, 9, 30, 7),
        endUtc: DateTime.utc(2026, 9, 30, 9),
        points: [hrPoint(uuid: 'parent-hr', at: t1, bpm: 70)],
      );
      expect(
        first.heartRateSamples.single.recordId,
        second.heartRateSamples.single.recordId,
      );

      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final store = LocalHealthStore(db);
      final window = SyncReplacementWindow(
        startUtc: DateTime.utc(2026, 9, 30, 7),
        endUtcExclusive: DateTime.utc(2026, 9, 30, 9),
        localDateStart: DateTime(2026, 9, 30),
        localDateEndExclusive: DateTime(2026, 10, 1),
        timezoneOffsetMinutes: 0,
      );
      Future<void> persist(IngestionBatch batch) async {
        final canonical = canonicalizer.canonicalize(batch);
        await store.replaceCanonicalWindow(
          userId: 'u1',
          window: window,
          canonical: canonical,
          bins: aggregator.hourlyBins(
            canonical.batch,
            preferredSourceId: healthSyncPackage,
          ),
          days: const [],
          state: const SyncState(preferredSourceId: healthSyncPackage),
        );
      }

      await persist(first);
      await persist(second);
      expect(await db.count('heart_rate_samples', 'u1'), 1);
      final row = db.connection.select(
        'SELECT bpm FROM heart_rate_samples WHERE user_id = ?',
        ['u1'],
      ).single;
      expect(row['bpm'], 70);
    },
  );

  test('same-parent HR samples persist as two local rows', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final store = LocalHealthStore(db);
    final batch = mapper.mapRange(
      startUtc: DateTime.utc(2026, 9, 30, 7),
      endUtc: DateTime.utc(2026, 9, 30, 9),
      points: [
        hrPoint(uuid: 'parent-hr', at: DateTime.utc(2026, 9, 30, 8), bpm: 62),
        hrPoint(
          uuid: 'parent-hr',
          at: DateTime.utc(2026, 9, 30, 8, 1),
          bpm: 64,
        ),
      ],
    );
    final canonical = canonicalizer.canonicalize(batch);
    await store.upsertCanonical(
      userId: 'u1',
      canonical: canonical,
      bins: aggregator.hourlyBins(
        canonical.batch,
        preferredSourceId: healthSyncPackage,
      ),
      days: const [],
      state: const SyncState(preferredSourceId: healthSyncPackage),
    );
    expect(await db.count('heart_rate_samples', 'u1'), 2);
  });

  test(
    'same parent sleep stages keep three identities and re-import idempotently',
    () async {
      final parent = 'sleep-parent';
      final points = [
        stagePoint(
          uuid: parent,
          type: 'SLEEP_LIGHT',
          start: DateTime.utc(2026, 9, 29, 16),
          end: DateTime.utc(2026, 9, 29, 18),
        ),
        stagePoint(
          uuid: parent,
          type: 'SLEEP_DEEP',
          start: DateTime.utc(2026, 9, 29, 18),
          end: DateTime.utc(2026, 9, 29, 20),
        ),
        stagePoint(
          uuid: parent,
          type: 'SLEEP_REM',
          start: DateTime.utc(2026, 9, 29, 20),
          end: DateTime.utc(2026, 9, 29, 22),
        ),
        MappedHealthPoint(
          type: 'SLEEP_SESSION',
          sourceId: '',
          sourceName: healthSyncPackage,
          uuid: parent,
          dateFrom: DateTime.utc(2026, 9, 29, 16),
          dateTo: DateTime.utc(2026, 9, 29, 22),
        ),
      ];
      final first = mapper.mapRange(
        startUtc: DateTime.utc(2026, 9, 29, 12),
        endUtc: DateTime.utc(2026, 9, 30, 8),
        points: points,
      );
      expect(first.sleepSessions, hasLength(1));
      expect(first.sleepSessions.single.stages, hasLength(3));
      expect(
        first.sleepSessions.single.stages
            .map((stage) => stage.recordId)
            .toSet(),
        hasLength(3),
      );

      final second = mapper.mapRange(
        startUtc: DateTime.utc(2026, 9, 29, 12),
        endUtc: DateTime.utc(2026, 9, 30, 8),
        points: points,
      );
      expect(
        second.sleepSessions.single.stages.map((stage) => stage.recordId),
        first.sleepSessions.single.stages.map((stage) => stage.recordId),
      );

      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final store = LocalHealthStore(db);
      final canonical = canonicalizer.canonicalize(first);
      await store.upsertCanonical(
        userId: 'u1',
        canonical: canonical,
        bins: const [],
        days: const [],
        state: const SyncState(),
      );
      await store.upsertCanonical(
        userId: 'u1',
        canonical: canonicalizer.canonicalize(second),
        bins: const [],
        days: const [],
        state: const SyncState(),
      );
      expect(await db.count('sleep_sessions', 'u1'), 1);
      expect(await db.count('sleep_stages', 'u1'), 3);
    },
  );

  test('empty source_id plus Health Sync package attaches stages', () {
    final batch = mapper.mapRange(
      startUtc: DateTime.utc(2026, 9, 29, 12),
      endUtc: DateTime.utc(2026, 9, 30, 8),
      points: [
        MappedHealthPoint(
          type: 'SLEEP_SESSION',
          sourceId: '',
          sourceName: healthSyncPackage,
          uuid: 'session',
          dateFrom: DateTime.utc(2026, 9, 29, 16),
          dateTo: DateTime.utc(2026, 9, 29, 18),
        ),
        stagePoint(
          uuid: 'stage-parent',
          type: 'SLEEP_LIGHT',
          start: DateTime.utc(2026, 9, 29, 16),
          end: DateTime.utc(2026, 9, 29, 18),
        ),
      ],
    );
    expect(batch.sleepSessions.single.source.sourceId, healthSyncPackage);
    expect(batch.sleepSessions.single.stages, hasLength(1));
  });

  test(
    'stages from another source do not attach even when intervals overlap',
    () {
      final batch = mapper.mapRange(
        startUtc: DateTime.utc(2026, 9, 29, 12),
        endUtc: DateTime.utc(2026, 9, 30, 8),
        points: [
          MappedHealthPoint(
            type: 'SLEEP_SESSION',
            sourceId: '',
            sourceName: healthSyncPackage,
            uuid: 'session',
            dateFrom: DateTime.utc(2026, 9, 29, 16),
            dateTo: DateTime.utc(2026, 9, 29, 18),
          ),
          stagePoint(
            uuid: 'phone-stage',
            type: 'SLEEP_LIGHT',
            start: DateTime.utc(2026, 9, 29, 16),
            end: DateTime.utc(2026, 9, 29, 18),
            sourceName: 'com.phone.sleep',
          ),
        ],
      );
      expect(batch.sleepSessions.single.stages, isEmpty);
    },
  );

  test('generic ASLEEP overlapping LIGHT/DEEP/REM does not double-count', () {
    final batch = mapper.mapRange(
      startUtc: DateTime.utc(2026, 9, 29, 12),
      endUtc: DateTime.utc(2026, 9, 30, 8),
      points: [
        MappedHealthPoint(
          type: 'SLEEP_SESSION',
          sourceId: '',
          sourceName: healthSyncPackage,
          uuid: 'session',
          dateFrom: DateTime.utc(2026, 9, 29, 16),
          dateTo: DateTime.utc(2026, 9, 29, 18),
        ),
        stagePoint(
          uuid: 'asleep',
          type: 'SLEEP_ASLEEP',
          start: DateTime.utc(2026, 9, 29, 16),
          end: DateTime.utc(2026, 9, 29, 18),
        ),
        stagePoint(
          uuid: 'light',
          type: 'SLEEP_LIGHT',
          start: DateTime.utc(2026, 9, 29, 16),
          end: DateTime.utc(2026, 9, 29, 17),
        ),
        stagePoint(
          uuid: 'deep',
          type: 'SLEEP_DEEP',
          start: DateTime.utc(2026, 9, 29, 17),
          end: DateTime.utc(2026, 9, 29, 18),
        ),
      ],
    );
    const normalizer = SleepStageNormalizer();
    final minutes = normalizer
        .normalize(batch.sleepSessions.single)
        .asleepMinutes;
    expect(minutes, 120);
    expect(minutes, isNot(120 + 60 + 60));
  });

  test('unattached stages from two package names stay separate sessions', () {
    final batch = mapper.mapRange(
      startUtc: DateTime.utc(2026, 9, 29, 12),
      endUtc: DateTime.utc(2026, 9, 30, 8),
      points: [
        stagePoint(
          uuid: 'h',
          type: 'SLEEP_LIGHT',
          start: DateTime.utc(2026, 9, 29, 16),
          end: DateTime.utc(2026, 9, 29, 17),
        ),
        stagePoint(
          uuid: 'p',
          type: 'SLEEP_DEEP',
          start: DateTime.utc(2026, 9, 29, 16),
          end: DateTime.utc(2026, 9, 29, 17),
          sourceName: 'com.phone.sleep',
        ),
      ],
    );
    expect(batch.sleepSessions, hasLength(2));
    expect(
      batch.sleepSessions.map((session) => session.source.sourceId).toSet(),
      {healthSyncPackage, 'com.phone.sleep'},
    );
  });
}
