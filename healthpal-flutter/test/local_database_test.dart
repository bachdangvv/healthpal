import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/database/healthpal_database.dart';
import 'package:healthpal/core/database/local_health_store.dart';
import 'package:healthpal/core/sync/sync_state.dart';
import 'package:healthpal/core/time/app_clock.dart';
import 'package:healthpal/features/health_connect/application/aggregator.dart';
import 'package:healthpal/features/health_connect/application/canonicalizer.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';
import 'package:healthpal/features/history/data/local_health_history_repository.dart';
import 'package:healthpal/features/history/domain/daily_health_summary.dart';

void main() {
  test('re-importing the same records does not grow row counts', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final store = LocalHealthStore(db);
    const canonicalizer = HealthRecordCanonicalizer();
    const aggregator = HealthAggregator();
    const source = SourceInfo(
      sourceId: 'healthsync.huawei',
      sourceName: 'Health Sync',
    );
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 30, 8),
      endUtc: DateTime.utc(2026, 9, 30, 10),
      stepIntervals: [
        StepInterval(
          recordId: 's1',
          startUtc: DateTime.utc(2026, 9, 30, 8),
          endUtc: DateTime.utc(2026, 9, 30, 9),
          zoneOffsetMinutes: 0,
          count: 400,
          source: source,
        ),
      ],
      heartRateSamples: [
        HeartRateSample(
          recordId: 'h1',
          startUtc: DateTime.utc(2026, 9, 30, 8, 10),
          endUtc: DateTime.utc(2026, 9, 30, 8, 10),
          zoneOffsetMinutes: 0,
          bpm: 70,
          source: source,
        ),
      ],
    );
    final canonical = canonicalizer.canonicalize(batch);
    final bins = aggregator.hourlyBins(
      canonical.batch,
      preferredSourceId: source.sourceId,
    );
    final days = aggregator.dailySummaries(
      bins: bins,
      batch: canonical.batch,
      preferredSourceId: source.sourceId,
      timezone: 'UTC',
    );
    final state = SyncState(
      lastSuccessfulSyncAtUtc: DateTime.utc(2026, 9, 30, 10),
      latestDataAtUtc: DateTime.utc(2026, 9, 30, 9),
      preferredSourceId: source.sourceId,
    );
    await store.upsertCanonical(
      userId: 'u1',
      canonical: canonical,
      bins: bins,
      days: days,
      state: state,
    );
    await store.upsertCanonical(
      userId: 'u1',
      canonical: canonical,
      bins: bins,
      days: days,
      state: state,
    );
    expect(await db.count('step_intervals', 'u1'), 1);
    expect(await db.count('heart_rate_samples', 'u1'), 1);
    await db.deleteUserPartition('u1');
    expect(await db.count('step_intervals', 'u1'), 0);
    expect(await db.count('heart_rate_samples', 'u1'), 0);
  });

  test('history returns fixed date slots with null gaps', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    db.connection.execute(
      '''
INSERT INTO daily_health_summaries (
  user_id, local_date, timezone, steps, exercise_count, exercise_duration_minutes,
  coverage_flags_json, updated_at_utc
) VALUES (?, ?, ?, ?, 0, 0, '{}', ?)
''',
      [
        'u1',
        '2026-09-28',
        'local',
        1200,
        DateTime.utc(2026, 9, 28).toIso8601String(),
      ],
    );
    final repo = LocalHealthHistoryRepository(
      database: db,
      userId: 'u1',
      clock: FixedAppClock(DateTime(2026, 9, 30, 12)),
    );
    final days = await repo.fetch(HistoryPeriod.sevenDays);
    expect(days, hasLength(7));
    expect(days.first.date, DateTime(2026, 9, 30));
    expect(days.last.date, DateTime(2026, 9, 24));
    expect(days.map((day) => day.date).toSet(), hasLength(7));
    final filled = days.singleWhere((day) => day.date == DateTime(2026, 9, 28));
    expect(filled.steps, 1200);
    expect(days.where((day) => day.steps == null), hasLength(6));
  });

  test('failed upsert rolls back the whole transaction', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final store = LocalHealthStore(db);
    const source = SourceInfo(
      sourceId: 'healthsync.huawei',
      sourceName: 'Health Sync',
    );
    const canonicalizer = HealthRecordCanonicalizer();
    const aggregator = HealthAggregator();
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 30, 8),
      endUtc: DateTime.utc(2026, 9, 30, 10),
      heartRateSamples: [
        HeartRateSample(
          recordId: 'h1',
          startUtc: DateTime.utc(2026, 9, 30, 8, 10),
          endUtc: DateTime.utc(2026, 9, 30, 8, 10),
          zoneOffsetMinutes: 0,
          bpm: 70,
          source: source,
        ),
      ],
      stepIntervals: [
        StepInterval(
          recordId: 's-bad',
          startUtc: DateTime.utc(2026, 9, 30, 8),
          endUtc: DateTime.utc(2026, 9, 30, 9),
          zoneOffsetMinutes: 0,
          count: -1,
          source: source,
        ),
      ],
    );
    final canonical = canonicalizer.canonicalize(batch);
    expect(
      () => store.upsertCanonical(
        userId: 'u1',
        canonical: canonical,
        bins: aggregator.hourlyBins(
          canonical.batch,
          preferredSourceId: source.sourceId,
        ),
        days: const [],
        state: const SyncState(),
      ),
      throwsA(isA<Object>()),
    );
    expect(await db.count('heart_rate_samples', 'u1'), 0);
    expect(await db.count('step_intervals', 'u1'), 0);
  });

  test('two users keep the same upstream record id isolated', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final store = LocalHealthStore(db);
    const source = SourceInfo(
      sourceId: 'healthsync.huawei',
      sourceName: 'Health Sync',
    );
    const canonicalizer = HealthRecordCanonicalizer();
    const aggregator = HealthAggregator();
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 30, 8),
      endUtc: DateTime.utc(2026, 9, 30, 10),
      stepIntervals: [
        StepInterval(
          recordId: 'shared',
          startUtc: DateTime.utc(2026, 9, 30, 8),
          endUtc: DateTime.utc(2026, 9, 30, 9),
          zoneOffsetMinutes: 0,
          count: 400,
          source: source,
        ),
      ],
    );
    final canonical = canonicalizer.canonicalize(batch);
    final bins = aggregator.hourlyBins(
      canonical.batch,
      preferredSourceId: source.sourceId,
    );
    for (final userId in ['u1', 'u2']) {
      await store.upsertCanonical(
        userId: userId,
        canonical: canonical,
        bins: bins,
        days: const [],
        state: const SyncState(),
      );
    }
    expect(await db.count('step_intervals', 'u1'), 1);
    expect(await db.count('step_intervals', 'u2'), 1);
  });
}
