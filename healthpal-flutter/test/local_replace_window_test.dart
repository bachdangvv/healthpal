import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/database/healthpal_database.dart';
import 'package:healthpal/core/database/local_health_store.dart';
import 'package:healthpal/core/sync/sync_state.dart';
import 'package:healthpal/features/assessment/domain/fatigue_assessment.dart';
import 'package:healthpal/features/health_connect/application/aggregator.dart';
import 'package:healthpal/features/health_connect/application/canonicalizer.dart';
import 'package:healthpal/features/health_connect/application/sync_window.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';

const source = SourceInfo(sourceId: 'src', sourceName: 'Health Sync');

class _ThrowingUpsertStore extends LocalHealthStore {
  _ThrowingUpsertStore(super.db);

  @override
  Future<void> upsertCanonical({
    required String userId,
    required CanonicalIngestion canonical,
    required List<HourlyBin> bins,
    required List<DailyAggregate> days,
    required SyncState state,
    bool transactional = true,
  }) async {
    throw StateError('injected upsert failure');
  }
}

HeartRateSample hr(String id, DateTime at, double bpm) => HeartRateSample(
  recordId: id,
  startUtc: at,
  endUtc: at,
  zoneOffsetMinutes: 0,
  bpm: bpm,
  source: source,
);

IngestionBatch batchOf(List<HeartRateSample> samples) => IngestionBatch(
  startUtc: DateTime.utc(2026, 9, 29),
  endUtc: DateTime.utc(2026, 9, 30, 12),
  heartRateSamples: samples,
);

SyncReplacementWindow window() => SyncReplacementWindow(
  startUtc: DateTime.utc(2026, 9, 29),
  endUtcExclusive: DateTime.utc(2026, 10, 1),
  localDateStart: DateTime(2026, 9, 29),
  localDateEndExclusive: DateTime(2026, 10, 1),
  timezoneOffsetMinutes: 0,
);

Future<void> persist(
  LocalHealthStore store,
  String userId,
  IngestionBatch batch, {
  List<HourlyBin>? bins,
  List<DailyAggregate>? days,
}) async {
  final canonical = const HealthRecordCanonicalizer().canonicalize(batch);
  await store.replaceCanonicalWindow(
    userId: userId,
    window: window(),
    canonical: canonical,
    bins:
        bins ??
        [
          HourlyBin(
            hourUtc: DateTime.utc(2026, 9, 30, 7),
            zoneOffsetMinutes: 0,
            steps: 50,
            sourceId: source.sourceId,
            coverageComplete: true,
          ),
        ],
    days:
        days ??
        [
          DailyAggregate(
            localDate: DateTime(2026, 9, 30),
            steps: 50,
            coverageFlags: const {'steps': true},
          ),
        ],
    state: SyncState(preferredSourceId: source.sourceId),
  );
}

void main() {
  test('vanished records inside the window are deleted', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final store = LocalHealthStore(db);
    await persist(
      store,
      'u1',
      batchOf([
        hr('keep', DateTime.utc(2026, 9, 30, 8), 62),
        hr('gone', DateTime.utc(2026, 9, 30, 9), 64),
      ]),
    );
    expect(await db.count('heart_rate_samples', 'u1'), 2);
    await persist(
      store,
      'u1',
      batchOf([hr('keep', DateTime.utc(2026, 9, 30, 8), 62)]),
    );
    expect(await db.count('heart_rate_samples', 'u1'), 1);
    final ids = db.connection
        .select('SELECT record_id FROM heart_rate_samples WHERE user_id = ?', [
          'u1',
        ])
        .map((row) => row['record_id'] as String)
        .toList();
    expect(ids, ['keep']);
  });

  test(
    'empty second batch prunes hourly and daily rows in the window',
    () async {
      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final store = LocalHealthStore(db);
      await persist(
        store,
        'u1',
        batchOf([hr('hr1', DateTime.utc(2026, 9, 30, 8), 62)]),
      );
      expect(await db.count('hourly_health_bins', 'u1'), 1);
      expect(await db.count('daily_health_summaries', 'u1'), 1);
      await persist(
        store,
        'u1',
        batchOf(const []),
        bins: const [],
        days: const [],
      );
      expect(await db.count('heart_rate_samples', 'u1'), 0);
      expect(await db.count('hourly_health_bins', 'u1'), 0);
      expect(await db.count('daily_health_summaries', 'u1'), 0);
    },
  );

  test('rows outside the window and other users are kept', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final store = LocalHealthStore(db);
    await store.upsertCanonical(
      userId: 'u1',
      canonical: const HealthRecordCanonicalizer().canonicalize(
        IngestionBatch(
          startUtc: DateTime.utc(2026, 9, 20),
          endUtc: DateTime.utc(2026, 9, 21),
          heartRateSamples: [
            HeartRateSample(
              recordId: 'old',
              startUtc: DateTime.utc(2026, 9, 20, 8),
              endUtc: DateTime.utc(2026, 9, 20, 8),
              zoneOffsetMinutes: 0,
              bpm: 55,
              source: source,
            ),
          ],
        ),
      ),
      bins: [
        HourlyBin(
          hourUtc: DateTime.utc(2026, 9, 20, 7),
          zoneOffsetMinutes: 0,
          steps: 9,
          sourceId: source.sourceId,
          coverageComplete: true,
        ),
      ],
      days: [
        DailyAggregate(
          localDate: DateTime(2026, 9, 20),
          steps: 9,
          coverageFlags: const {'steps': true},
        ),
      ],
      state: SyncState(preferredSourceId: source.sourceId),
    );
    await persist(
      store,
      'u2',
      batchOf([hr('b', DateTime.utc(2026, 9, 30, 8), 70)]),
    );
    await persist(
      store,
      'u1',
      batchOf([hr('new', DateTime.utc(2026, 9, 30, 8), 62)]),
    );
    expect(await db.count('heart_rate_samples', 'u1'), 2);
    expect(await db.count('heart_rate_samples', 'u2'), 1);
    expect(await db.count('hourly_health_bins', 'u1'), 2);
    expect(await db.count('daily_health_summaries', 'u1'), 2);
  });

  test('injected upsert failure rolls back the window delete', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final store = LocalHealthStore(db);
    await persist(
      store,
      'u1',
      batchOf([hr('keep', DateTime.utc(2026, 9, 30, 8), 62)]),
    );
    await store.saveAssessment(
      'u1',
      FatigueAssessment(
        id: 'a1',
        evaluatedAtUtc: DateTime.utc(2026, 9, 30, 8),
        localDate: DateTime(2026, 9, 30),
        modelVersion: 'healthpal_fatigue_v4',
        threshold: 0.18,
        status: FatigueAssessmentStatus.insufficientData,
        coverageHours: 0,
        featureVectorHash: 'hash',
        createdBy: AssessmentCreatedBy.foreground,
      ),
    );
    final throwing = _ThrowingUpsertStore(db);
    await expectLater(
      persist(
        throwing,
        'u1',
        batchOf(const []),
        bins: const [],
        days: const [],
      ),
      throwsStateError,
    );
    expect(await db.count('heart_rate_samples', 'u1'), 1);
    expect(await db.count('hourly_health_bins', 'u1'), 1);
    expect(await db.count('daily_health_summaries', 'u1'), 1);
    expect(await db.count('fatigue_assessments', 'u1'), 1);
  });

  test(
    'sleep-only correction rebuilds the daily summary instead of dropping it',
    () async {
      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final store = LocalHealthStore(db);
      await persist(
        store,
        'u1',
        batchOf([hr('stale', DateTime.utc(2026, 9, 30, 8), 80)]),
        bins: [
          HourlyBin(
            hourUtc: DateTime.utc(2026, 9, 30, 7),
            zoneOffsetMinutes: 0,
            steps: 999,
            hrMean: 80,
            sourceId: source.sourceId,
            coverageComplete: true,
          ),
        ],
        days: [
          DailyAggregate(
            localDate: DateTime(2026, 9, 30),
            steps: 999,
            averageHeartRate: 80,
            coverageFlags: const {'hasHeartRate': true, 'hasSleep': false},
          ),
        ],
      );
      final sleepBatch = IngestionBatch(
        startUtc: DateTime.utc(2026, 9, 29),
        endUtc: DateTime.utc(2026, 9, 30, 12),
        sleepSessions: [
          SleepSession(
            recordId: 'sleep-1',
            startUtc: DateTime.utc(2026, 9, 29, 15),
            endUtc: DateTime.utc(2026, 9, 29, 22),
            zoneOffsetMinutes: 0,
            healthDay: DateTime(2026, 9, 30),
            stages: [
              SleepStage(
                recordId: 'st-1',
                startUtc: DateTime.utc(2026, 9, 29, 15),
                endUtc: DateTime.utc(2026, 9, 29, 22),
                type: SleepStageType.light,
                source: source,
              ),
            ],
            source: source,
          ),
        ],
      );
      const aggregator = HealthAggregator();
      final canonical = const HealthRecordCanonicalizer().canonicalize(
        sleepBatch,
      );
      final days = aggregator.dailySummaries(
        bins: const [],
        batch: canonical.batch,
        preferredSourceId: source.sourceId,
        timezone: 'UTC',
      );
      await store.replaceCanonicalWindow(
        userId: 'u1',
        window: window(),
        canonical: canonical,
        bins: const [],
        days: days,
        state: SyncState(preferredSourceId: source.sourceId),
      );
      expect(await db.count('sleep_sessions', 'u1'), 1);
      expect(await db.count('daily_health_summaries', 'u1'), 1);
      final row = await store.dailySummaryRow('u1', DateTime(2026, 9, 30));
      expect(row, isNotNull);
      expect(row!['sleep_minutes'], 420);
      expect(row['steps'], isNull);
      expect(row['average_heart_rate'], isNull);
    },
  );
}
