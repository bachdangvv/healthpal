import '../../../src/rust/types.dart' as rust;
import '../../health_connect/application/canonicalizer.dart';
import '../../health_connect/domain/health_records.dart';
import '../../health_connect/domain/sleep_normalizer.dart';

class AssessmentRequestFactory {
  const AssessmentRequestFactory();

  rust.AssessmentRequest fromCanonical({
    required CanonicalIngestion canonical,
    required DateTime evaluationTimeUtc,
    required int timezoneOffsetMinutes,
    required PermissionSnapshot permissions,
    DateTime? dataWatermarkUtc,
    DateTime? previousAssessmentWatermarkUtc,
  }) {
    const normalizer = SleepStageNormalizer();
    return rust.AssessmentRequest(
      evaluationTimeUtc: evaluationTimeUtc.toUtc(),
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      heartRateSamples: [
        for (final sample in canonical.batch.heartRateSamples)
          rust.HeartRateSample(
            timestampUtc: sample.startUtc,
            bpm: sample.bpm,
            recordId: sample.recordId,
            sourceId: sample.source.sourceId,
          ),
      ],
      stepIntervals: [
        for (final interval in canonical.batch.stepIntervals)
          rust.StepInterval(
            startUtc: interval.startUtc,
            endUtc: interval.endUtc,
            count: interval.count.toDouble(),
            recordId: interval.recordId,
            sourceId: interval.source.sourceId,
          ),
      ],
      restingHrRecords: [
        for (final record in canonical.batch.restingHeartRateRecords)
          rust.RestingHrRecord(
            recordedAtUtc: record.recordedAtUtc,
            bpm: record.bpm,
            localDate: _date(record.localDate),
            recordId: record.recordId,
            sourceId: record.source.sourceId,
          ),
      ],
      sleepSessions: [
        for (final session in canonical.batch.sleepSessions)
          rust.SleepSession(
            recordId: session.recordId,
            startUtc: session.startUtc,
            endUtc: session.endUtc,
            healthDay: _date(session.healthDay),
            stages: [
              for (final stage in normalizer.normalize(session).stages)
                rust.SleepStage(
                  startUtc: stage.startUtc,
                  endUtc: stage.endUtc,
                  stageType: stage.type.name,
                  recordId: stage.recordId,
                  sourceId: stage.source?.sourceId ?? session.source.sourceId,
                ),
            ],
            asleepMinutesAggregate: session.asleepMinutesAggregate?.toDouble(),
            sourceId: session.source.sourceId,
            modifiedAtUtc: session.modifiedAtUtc,
          ),
      ],
      exerciseSessions: [
        for (final session in canonical.batch.exerciseSessions)
          rust.ExerciseSession(
            startUtc: session.startUtc,
            endUtc: session.endUtc,
            exerciseType: session.type,
            recordId: session.recordId,
          ),
      ],
      dataWatermarkUtc: dataWatermarkUtc,
      previousAssessmentWatermarkUtc: previousAssessmentWatermarkUtc,
      preferredSourceId: canonical.preferredSourceId,
      heartRatePermission: permissions.granted.contains(
        HealthPermission.heartRate,
      ),
      stepsPermission: permissions.granted.contains(HealthPermission.steps),
      sleepPermission: permissions.granted.contains(HealthPermission.sleep),
      restingHrPermission: permissions.granted.contains(
        HealthPermission.restingHeartRate,
      ),
    );
  }

  String _date(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
