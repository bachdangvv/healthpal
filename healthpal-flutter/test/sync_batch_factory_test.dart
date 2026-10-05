import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/config/app_config.dart';
import 'package:healthpal/core/sync/sync_batch_factory.dart';
import 'package:healthpal/features/health_connect/application/aggregator.dart';
import 'package:healthpal/features/health_connect/application/sync_window.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';

SyncReplacementWindow window({required DateTime start, required DateTime end}) {
  return SyncReplacementWindow(
    startUtc: start,
    endUtcExclusive: end,
    localDateStart: DateTime(start.year, start.month, start.day),
    localDateEndExclusive: DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1)),
    timezoneOffsetMinutes: 0,
  );
}

void main() {
  const factory = SyncBatchFactory();

  test(
    'empty rows plus a window still emit schema v2 and an idempotency key',
    () {
      final batch = factory.build(
        deviceId: 'device-1',
        bins: const [],
        days: const [],
        exercises: const [],
        assessments: const [],
        generatedAtUtc: DateTime.utc(2026, 9, 30, 8),
        replacementWindow: window(
          start: DateTime.utc(2026, 9, 28),
          end: DateTime.utc(2026, 9, 30, 8),
        ),
      );
      expect(batch.schemaVersion, AppConfig.syncSchemaVersion);
      expect(batch.schemaVersion, 2);
      expect(batch.idempotencyKey, isNotEmpty);
      expect(batch.replacementWindow, isNotNull);
      expect(batch.hourlyBins, isEmpty);
    },
  );

  test(
    'sleep RHR and exercise only days reach the v2 sync DTO via aggregator',
    () {
      const source = SourceInfo(sourceId: 'src', sourceName: 'Health Sync');
      final ingestion = IngestionBatch(
        startUtc: DateTime.utc(2026, 9, 29),
        endUtc: DateTime.utc(2026, 10, 1),
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
        restingHeartRateRecords: [
          RestingHeartRateRecord(
            recordId: 'rhr-1',
            recordedAtUtc: DateTime.utc(2026, 9, 30, 6),
            zoneOffsetMinutes: 0,
            localDate: DateTime(2026, 9, 30),
            bpm: 58,
            source: source,
          ),
        ],
        exerciseSessions: [
          ExerciseSession(
            recordId: 'ex-1',
            startUtc: DateTime.utc(2026, 9, 30, 8),
            endUtc: DateTime.utc(2026, 9, 30, 8, 40),
            zoneOffsetMinutes: 0,
            type: 'walking',
            durationMinutes: 40,
            source: source,
          ),
        ],
      );
      final days = const HealthAggregator().dailySummaries(
        bins: const [],
        batch: ingestion,
        preferredSourceId: source.sourceId,
        timezone: 'UTC',
      );
      final replacement = SyncReplacementWindow.forSync(
        cutoffUtc: DateTime.utc(2026, 9, 30, 12),
        timezoneOffsetMinutes: 0,
        previousWatermarkUtc: DateTime.utc(2026, 9, 30, 12),
        firstSync: false,
      );
      final batch = factory.build(
        deviceId: 'device-1',
        bins: const [],
        days: days,
        exercises: ingestion.exerciseSessions,
        assessments: const [],
        generatedAtUtc: DateTime.utc(2026, 9, 30, 12),
        replacementWindow: replacement,
      );
      expect(batch.schemaVersion, 2);
      expect(batch.dailySummaries, hasLength(1));
      expect(batch.dailySummaries.single.localDate, DateTime(2026, 9, 30));
      expect(batch.dailySummaries.single.sleepMinutes, 420);
      expect(batch.dailySummaries.single.restingHeartRate, 58);
      expect(batch.dailySummaries.single.exerciseCount, 1);
      expect(batch.replacementWindow, isNotNull);
      expect(
        batch.replacementWindow!.endUtcExclusive.difference(
          batch.replacementWindow!.startUtc,
        ),
        lessThanOrEqualTo(const Duration(days: 32)),
      );
    },
  );

  test(
    '60-day stale watermark emits a schema v2 window under the 32-day limit',
    () {
      // Outbox still dead-letters HTTP 400; the client must not emit an
      // oversized replacement window in the first place.
      final window = SyncReplacementWindow.forSync(
        cutoffUtc: DateTime.utc(2026, 10, 1, 8),
        timezoneOffsetMinutes: 420,
        previousWatermarkUtc: DateTime.utc(2026, 8, 2, 8),
        firstSync: false,
      );
      final batch = factory.build(
        deviceId: 'device-1',
        bins: const [],
        days: const [],
        exercises: const [],
        assessments: const [],
        generatedAtUtc: DateTime.utc(2026, 10, 1, 8),
        replacementWindow: window,
      );
      expect(batch.schemaVersion, 2);
      expect(batch.idempotencyKey, isNotEmpty);
      expect(batch.replacementWindow, isNotNull);
      expect(
        batch.replacementWindow!.endUtcExclusive.difference(
          batch.replacementWindow!.startUtc,
        ),
        lessThanOrEqualTo(const Duration(days: 32)),
      );
      expect(batch.replacementWindow!.startUtc, window.startUtc);
      expect(batch.replacementWindow!.localDateStart, DateTime(2026, 9, 1));
    },
  );

  test('changing the replacement window changes the idempotency key', () {
    final first = factory.build(
      deviceId: 'device-1',
      bins: const [],
      days: const [],
      exercises: const [],
      assessments: const [],
      generatedAtUtc: DateTime.utc(2026, 9, 30, 8),
      replacementWindow: window(
        start: DateTime.utc(2026, 9, 28),
        end: DateTime.utc(2026, 9, 30, 8),
      ),
    );
    final second = factory.build(
      deviceId: 'device-1',
      bins: const [],
      days: const [],
      exercises: const [],
      assessments: const [],
      generatedAtUtc: DateTime.utc(2026, 9, 30, 8),
      replacementWindow: window(
        start: DateTime.utc(2026, 9, 27),
        end: DateTime.utc(2026, 9, 30, 8),
      ),
    );
    expect(first.idempotencyKey, isNot(second.idempotencyKey));
  });
}
