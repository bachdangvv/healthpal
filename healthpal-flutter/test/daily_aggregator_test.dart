import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/health_connect/application/aggregator.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';

const source = SourceInfo(sourceId: 'src', sourceName: 'Health Sync');
const aggregator = HealthAggregator();

SleepSession sleepOn({
  required DateTime healthDay,
  required DateTime startUtc,
  required DateTime endUtc,
  int zoneOffsetMinutes = 0,
  String id = 'sleep-1',
}) {
  return SleepSession(
    recordId: id,
    startUtc: startUtc,
    endUtc: endUtc,
    zoneOffsetMinutes: zoneOffsetMinutes,
    healthDay: healthDay,
    stages: [
      SleepStage(
        recordId: '$id-light',
        startUtc: startUtc,
        endUtc: endUtc,
        type: SleepStageType.light,
        source: source,
      ),
    ],
    source: source,
  );
}

RestingHeartRateRecord rhrOn({
  required DateTime localDate,
  required DateTime recordedAtUtc,
  double bpm = 58,
  int zoneOffsetMinutes = 0,
  String id = 'rhr-1',
}) {
  return RestingHeartRateRecord(
    recordId: id,
    recordedAtUtc: recordedAtUtc,
    zoneOffsetMinutes: zoneOffsetMinutes,
    localDate: localDate,
    bpm: bpm,
    source: source,
  );
}

ExerciseSession exerciseAt({
  required DateTime startUtc,
  required int durationMinutes,
  int zoneOffsetMinutes = 0,
  String id = 'ex-1',
}) {
  return ExerciseSession(
    recordId: id,
    startUtc: startUtc,
    endUtc: startUtc.add(Duration(minutes: durationMinutes)),
    zoneOffsetMinutes: zoneOffsetMinutes,
    type: 'walking',
    durationMinutes: durationMinutes,
    source: source,
  );
}

List<DailyAggregate> summaries(IngestionBatch batch) {
  return aggregator.dailySummaries(
    bins: const [],
    batch: batch,
    preferredSourceId: source.sourceId,
    timezone: 'UTC',
  );
}

void main() {
  test('sleep-only day produces one daily summary', () {
    final start = DateTime.utc(2026, 9, 29, 15);
    final end = DateTime.utc(2026, 9, 29, 22);
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 29),
      endUtc: DateTime.utc(2026, 9, 30),
      sleepSessions: [
        sleepOn(healthDay: DateTime(2026, 9, 30), startUtc: start, endUtc: end),
      ],
    );
    final days = summaries(batch);
    expect(days, hasLength(1));
    expect(days.single.localDate, DateTime(2026, 9, 30));
    expect(days.single.sleepMinutes, 420);
    expect(days.single.averageHeartRate, isNull);
    expect(days.single.steps, isNull);
    expect(days.single.coverageFlags['hasSleep'], isTrue);
    expect(days.single.coverageFlags['hasHeartRate'], isFalse);
  });

  test('RHR-only day produces one daily summary', () {
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 30),
      endUtc: DateTime.utc(2026, 10, 1),
      restingHeartRateRecords: [
        rhrOn(
          localDate: DateTime(2026, 9, 30),
          recordedAtUtc: DateTime.utc(2026, 9, 30, 6),
          bpm: 58,
        ),
      ],
    );
    final days = summaries(batch);
    expect(days, hasLength(1));
    expect(days.single.restingHeartRate, 58);
    expect(days.single.averageHeartRate, isNull);
    expect(days.single.coverageFlags['hasRhr'], isTrue);
    expect(days.single.coverageFlags['hasHeartRate'], isFalse);
  });

  test('exercise-only day produces one daily summary', () {
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 30),
      endUtc: DateTime.utc(2026, 10, 1),
      exerciseSessions: [
        exerciseAt(
          startUtc: DateTime.utc(2026, 9, 30, 22),
          durationMinutes: 40,
          zoneOffsetMinutes: 420,
        ),
      ],
    );
    final days = summaries(batch);
    expect(days, hasLength(1));
    expect(days.single.localDate, DateTime(2026, 10, 1));
    expect(days.single.exerciseCount, 1);
    expect(days.single.exerciseDurationMinutes, 40);
  });

  test('sleep RHR and exercise on one date produce one summary', () {
    final day = DateTime(2026, 9, 30);
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 29),
      endUtc: DateTime.utc(2026, 10, 1),
      sleepSessions: [
        sleepOn(
          healthDay: day,
          startUtc: DateTime.utc(2026, 9, 29, 15),
          endUtc: DateTime.utc(2026, 9, 29, 22),
        ),
      ],
      restingHeartRateRecords: [
        rhrOn(localDate: day, recordedAtUtc: DateTime.utc(2026, 9, 30, 6)),
      ],
      exerciseSessions: [
        exerciseAt(startUtc: DateTime.utc(2026, 9, 30, 8), durationMinutes: 25),
      ],
    );
    final days = summaries(batch);
    expect(days, hasLength(1));
    expect(days.single.localDate, day);
    expect(days.single.sleepMinutes, 420);
    expect(days.single.restingHeartRate, 58);
    expect(days.single.exerciseCount, 1);
  });

  test('records on three dates produce three sorted summaries', () {
    final batch = IngestionBatch(
      startUtc: DateTime.utc(2026, 9, 28),
      endUtc: DateTime.utc(2026, 10, 1),
      sleepSessions: [
        sleepOn(
          healthDay: DateTime(2026, 9, 28),
          startUtc: DateTime.utc(2026, 9, 27, 15),
          endUtc: DateTime.utc(2026, 9, 27, 22),
          id: 'sleep-28',
        ),
      ],
      restingHeartRateRecords: [
        rhrOn(
          localDate: DateTime(2026, 9, 29),
          recordedAtUtc: DateTime.utc(2026, 9, 29, 6),
          id: 'rhr-29',
        ),
      ],
      exerciseSessions: [
        exerciseAt(
          startUtc: DateTime.utc(2026, 9, 30, 8),
          durationMinutes: 10,
          id: 'ex-30',
        ),
      ],
    );
    final days = summaries(batch);
    expect(days.map((item) => item.localDate), [
      DateTime(2026, 9, 28),
      DateTime(2026, 9, 29),
      DateTime(2026, 9, 30),
    ]);
  });

  test('completely empty batch produces no daily summaries', () {
    final days = summaries(
      IngestionBatch(
        startUtc: DateTime.utc(2026, 9, 28),
        endUtc: DateTime.utc(2026, 9, 30, 12),
      ),
    );
    expect(days, isEmpty);
  });

  test(
    'sleep-only day with UTC+7 uses the expected local date and completeness boundary',
    () {
      final batch = IngestionBatch(
        startUtc: DateTime.utc(2026, 9, 28),
        endUtc: DateTime.utc(2026, 9, 30),
        sleepSessions: [
          sleepOn(
            healthDay: DateTime(2026, 9, 29),
            startUtc: DateTime.utc(2026, 9, 28, 15),
            endUtc: DateTime.utc(2026, 9, 28, 22),
            zoneOffsetMinutes: 420,
          ),
        ],
      );
      final incomplete = aggregator.dailySummaries(
        bins: const [],
        batch: batch,
        preferredSourceId: source.sourceId,
        timezone: 'Asia/Ho_Chi_Minh',
        completenessWatermarkUtc: DateTime.utc(2026, 9, 29, 16, 59),
      );
      expect(incomplete, hasLength(1));
      expect(incomplete.single.localDate, DateTime(2026, 9, 29));
      expect(incomplete.single.sleepMinutes, 420);
      expect(incomplete.single.steps, isNull);
      expect(incomplete.single.coverageFlags['stepsComplete'], isFalse);

      final complete = aggregator.dailySummaries(
        bins: const [],
        batch: batch,
        preferredSourceId: source.sourceId,
        timezone: 'Asia/Ho_Chi_Minh',
        completenessWatermarkUtc: DateTime.utc(2026, 9, 29, 17),
      );
      expect(complete.single.steps, 0);
      expect(complete.single.coverageFlags['stepsComplete'], isTrue);
    },
  );
}
