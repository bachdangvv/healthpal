import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';
import 'package:healthpal/features/health_connect/domain/sleep_normalizer.dart';

const huawei = SourceInfo(
  sourceId: 'healthsync.huawei',
  sourceName: 'Health Sync',
);
const phone = SourceInfo(sourceId: 'phone.sleep', sourceName: 'Phone');

void main() {
  const normalizer = SleepStageNormalizer();

  SleepSession session({
    required List<SleepStage> stages,
    DateTime? start,
    DateTime? end,
    SourceInfo source = huawei,
    int? aggregate,
  }) {
    return SleepSession(
      recordId: 'sleep',
      startUtc: start ?? DateTime.utc(2026, 9, 29, 16),
      endUtc: end ?? DateTime.utc(2026, 9, 29, 18),
      zoneOffsetMinutes: 420,
      healthDay: DateTime(2026, 9, 30),
      stages: stages,
      asleepMinutesAggregate: aggregate,
      source: source,
    );
  }

  test('detailed LIGHT/DEEP/REM/AWAKE uses union of asleep intervals', () {
    final result = normalizer.normalize(
      session(
        stages: [
          SleepStage(
            recordId: 'l',
            startUtc: DateTime.utc(2026, 9, 29, 16),
            endUtc: DateTime.utc(2026, 9, 29, 16, 50),
            type: SleepStageType.light,
            source: huawei,
          ),
          SleepStage(
            recordId: 'd',
            startUtc: DateTime.utc(2026, 9, 29, 16, 50),
            endUtc: DateTime.utc(2026, 9, 29, 17, 20),
            type: SleepStageType.deep,
            source: huawei,
          ),
          SleepStage(
            recordId: 'a',
            startUtc: DateTime.utc(2026, 9, 29, 17, 20),
            endUtc: DateTime.utc(2026, 9, 29, 17, 30),
            type: SleepStageType.awake,
            source: huawei,
          ),
          SleepStage(
            recordId: 'r',
            startUtc: DateTime.utc(2026, 9, 29, 17, 30),
            endUtc: DateTime.utc(2026, 9, 29, 18),
            type: SleepStageType.rem,
            source: huawei,
          ),
        ],
      ),
    );
    expect(result.asleepMinutes, 110);
    expect(result.asleepMinutes, lessThanOrEqualTo(120));
  });

  test('generic ASLEEP plus detailed stages does not double-count', () {
    final result = normalizer.normalize(
      session(
        aggregate: 120,
        stages: [
          SleepStage(
            recordId: 'asleep',
            startUtc: DateTime.utc(2026, 9, 29, 16),
            endUtc: DateTime.utc(2026, 9, 29, 18),
            type: SleepStageType.asleep,
            source: huawei,
          ),
          SleepStage(
            recordId: 'l',
            startUtc: DateTime.utc(2026, 9, 29, 16, 10),
            endUtc: DateTime.utc(2026, 9, 29, 16, 40),
            type: SleepStageType.light,
            source: huawei,
          ),
          SleepStage(
            recordId: 'd',
            startUtc: DateTime.utc(2026, 9, 29, 16, 40),
            endUtc: DateTime.utc(2026, 9, 29, 17, 10),
            type: SleepStageType.deep,
            source: huawei,
          ),
        ],
      ),
    );
    expect(result.asleepMinutes, 120);
    expect(result.asleepMinutes, isNot(120 + 30 + 30));
  });

  test('empty source ids do not attach to each other', () {
    final attached = normalizer.stagesForSession(
      session: session(
        stages: const [],
        source: const SourceInfo(sourceId: '', sourceName: ''),
      ),
      stages: [
        SleepStage(
          recordId: 'empty',
          startUtc: DateTime.utc(2026, 9, 29, 16, 5),
          endUtc: DateTime.utc(2026, 9, 29, 17),
          type: SleepStageType.light,
          source: const SourceInfo(sourceId: '', sourceName: ''),
        ),
      ],
    );
    expect(attached, isEmpty);
  });

  test('stages from another source are not attached', () {
    final attached = normalizer.stagesForSession(
      session: session(stages: const []),
      stages: [
        SleepStage(
          recordId: 'other',
          startUtc: DateTime.utc(2026, 9, 29, 16, 5),
          endUtc: DateTime.utc(2026, 9, 29, 17),
          type: SleepStageType.light,
          source: phone,
        ),
        SleepStage(
          recordId: 'same',
          startUtc: DateTime.utc(2026, 9, 29, 16, 5),
          endUtc: DateTime.utc(2026, 9, 29, 17),
          type: SleepStageType.light,
          source: huawei,
        ),
      ],
    );
    expect(attached, hasLength(1));
    expect(attached.single.recordId, 'same');
  });

  test('stages are clamped to the session and never exceed duration', () {
    final result = normalizer.normalize(
      session(
        stages: [
          SleepStage(
            recordId: 'over',
            startUtc: DateTime.utc(2026, 9, 29, 15, 30),
            endUtc: DateTime.utc(2026, 9, 29, 18, 45),
            type: SleepStageType.light,
            source: huawei,
          ),
        ],
      ),
    );
    expect(result.asleepMinutes, 120);
  });

  test('unattached stages from two sources become two sessions', () {
    final sessions = normalizer.sessionsFromUnattachedStages([
      SleepStage(
        recordId: 'h',
        startUtc: DateTime.utc(2026, 9, 29, 16),
        endUtc: DateTime.utc(2026, 9, 29, 17),
        type: SleepStageType.light,
        source: huawei,
      ),
      SleepStage(
        recordId: 'p',
        startUtc: DateTime.utc(2026, 9, 29, 16),
        endUtc: DateTime.utc(2026, 9, 29, 17),
        type: SleepStageType.deep,
        source: phone,
      ),
    ]);
    expect(sessions, hasLength(2));
    expect(sessions.map((session) => session.source.sourceId).toSet(), {
      'healthsync.huawei',
      'phone.sleep',
    });
  });

  test('duplicate Health Sync stage records are collapsed', () {
    final result = normalizer.normalize(
      session(
        stages: [
          SleepStage(
            recordId: 'dup',
            startUtc: DateTime.utc(2026, 9, 29, 16),
            endUtc: DateTime.utc(2026, 9, 29, 17),
            type: SleepStageType.light,
            source: huawei,
          ),
          SleepStage(
            recordId: 'dup',
            startUtc: DateTime.utc(2026, 9, 29, 16),
            endUtc: DateTime.utc(2026, 9, 29, 17),
            type: SleepStageType.light,
            source: huawei,
          ),
        ],
      ),
    );
    expect(result.asleepMinutes, 60);
    expect(result.stages, hasLength(1));
  });
}
