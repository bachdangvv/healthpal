import '../domain/health_records.dart';
import '../domain/sleep_normalizer.dart';
import 'record_identity.dart';

/// Plugin-independent Health Connect point. [PluginHealthConnectAdapter]
/// copies plugin fields here so identity rules can be unit-tested.
class MappedHealthPoint {
  const MappedHealthPoint({
    required this.type,
    required this.sourceId,
    required this.sourceName,
    required this.uuid,
    required this.dateFrom,
    required this.dateTo,
    this.numericValue,
    this.workoutActivityName,
    this.workoutCalories,
  });

  final String type;
  final String sourceId;
  final String sourceName;
  final String uuid;
  final DateTime dateFrom;
  final DateTime dateTo;
  final double? numericValue;
  final String? workoutActivityName;
  final double? workoutCalories;
}

class HealthDataPointMapper {
  const HealthDataPointMapper();

  IngestionBatch mapRange({
    required DateTime startUtc,
    required DateTime endUtc,
    required List<MappedHealthPoint> points,
  }) {
    final heart = <HeartRateSample>[];
    final steps = <StepInterval>[];
    final rhr = <RestingHeartRateRecord>[];
    final sleepSessions = <SleepSession>[];
    final stages = <SleepStage>[];
    final exercise = <ExerciseSession>[];
    final calories = <ActiveCaloriesInterval>[];

    for (final point in points) {
      final source = SourceInfo(
        sourceId: effectiveSourceId(
          sourceId: point.sourceId,
          sourceName: point.sourceName,
        ),
        sourceName: point.sourceName,
      );
      final offset = point.dateFrom.isUtc
          ? 0
          : point.dateFrom.timeZoneOffset.inMinutes;
      final start = point.dateFrom.toUtc();
      final end = point.dateTo.toUtc();
      final parentId = point.uuid.trim();
      switch (point.type) {
        case 'HEART_RATE':
          final value = point.numericValue;
          if (value == null) continue;
          heart.add(
            HeartRateSample(
              recordId: childRecordId(
                parentRecordId: parentId,
                recordType: 'heart_rate',
                sourceId: source.sourceId,
                startUtc: start,
                endUtc: end,
                discriminator: 'sample',
              ),
              startUtc: start,
              endUtc: end,
              zoneOffsetMinutes: offset,
              bpm: value,
              source: source,
            ),
          );
        case 'STEPS':
          final value = point.numericValue;
          if (value == null) continue;
          steps.add(
            StepInterval(
              recordId: _recordLevelId(
                parentId: parentId,
                type: 'steps',
                sourceId: source.sourceId,
                startUtc: start,
                endUtc: end,
                roundedValue: value.round(),
              ),
              startUtc: start,
              endUtc: end,
              zoneOffsetMinutes: offset,
              count: value.round(),
              source: source,
            ),
          );
        case 'RESTING_HEART_RATE':
          final value = point.numericValue;
          if (value == null) continue;
          final local = end.add(Duration(minutes: offset));
          rhr.add(
            RestingHeartRateRecord(
              recordId: _recordLevelId(
                parentId: parentId,
                type: 'rhr',
                sourceId: source.sourceId,
                startUtc: end,
                endUtc: end,
                roundedValue: value.round(),
              ),
              recordedAtUtc: end,
              zoneOffsetMinutes: offset,
              localDate: DateTime(local.year, local.month, local.day),
              bpm: value,
              source: source,
            ),
          );
        case 'SLEEP_SESSION':
          final local = end.add(Duration(minutes: offset));
          sleepSessions.add(
            SleepSession(
              recordId: _recordLevelId(
                parentId: parentId,
                type: 'sleep_session',
                sourceId: source.sourceId,
                startUtc: start,
                endUtc: end,
                roundedValue: 0,
              ),
              startUtc: start,
              endUtc: end,
              zoneOffsetMinutes: offset,
              healthDay: DateTime(local.year, local.month, local.day),
              source: source,
            ),
          );
        case 'SLEEP_ASLEEP':
        case 'SLEEP_LIGHT':
        case 'SLEEP_DEEP':
        case 'SLEEP_REM':
        case 'SLEEP_AWAKE':
          final stageType = switch (point.type) {
            'SLEEP_DEEP' => SleepStageType.deep,
            'SLEEP_LIGHT' => SleepStageType.light,
            'SLEEP_REM' => SleepStageType.rem,
            'SLEEP_AWAKE' => SleepStageType.awake,
            _ => SleepStageType.asleep,
          };
          stages.add(
            SleepStage(
              recordId: childRecordId(
                parentRecordId: parentId,
                recordType: 'sleep_stage',
                sourceId: source.sourceId,
                startUtc: start,
                endUtc: end,
                discriminator: stageType.name,
              ),
              startUtc: start,
              endUtc: end,
              type: stageType,
              source: source,
              modifiedAtUtc: end,
            ),
          );
        case 'ACTIVE_ENERGY_BURNED':
          final value = point.numericValue;
          if (value == null) continue;
          calories.add(
            ActiveCaloriesInterval(
              recordId: _recordLevelId(
                parentId: parentId,
                type: 'calories',
                sourceId: source.sourceId,
                startUtc: start,
                endUtc: end,
                roundedValue: value.round(),
              ),
              startUtc: start,
              endUtc: end,
              zoneOffsetMinutes: offset,
              kilocalories: value,
              source: source,
            ),
          );
        case 'WORKOUT':
          final title = point.workoutActivityName ?? 'workout';
          exercise.add(
            ExerciseSession(
              recordId: _recordLevelId(
                parentId: parentId,
                type: 'exercise',
                sourceId: source.sourceId,
                startUtc: start,
                endUtc: end,
                roundedValue: end.difference(start).inMinutes,
              ),
              startUtc: start,
              endUtc: end,
              zoneOffsetMinutes: offset,
              type: title,
              title: title,
              durationMinutes: end.difference(start).inMinutes,
              calories: point.workoutCalories,
              source: source,
            ),
          );
        default:
          break;
      }
    }

    const normalizer = SleepStageNormalizer();
    final sessions = sleepSessions.isNotEmpty
        ? [
            for (final session in sleepSessions)
              SleepSession(
                recordId: session.recordId,
                startUtc: session.startUtc,
                endUtc: session.endUtc,
                zoneOffsetMinutes: session.zoneOffsetMinutes,
                healthDay: session.healthDay,
                stages: normalizer.stagesForSession(
                  session: session,
                  stages: stages,
                ),
                source: session.source,
                modifiedAtUtc: session.modifiedAtUtc,
              ),
          ]
        : normalizer.sessionsFromUnattachedStages(stages);

    return IngestionBatch(
      startUtc: startUtc.toUtc(),
      endUtc: endUtc.toUtc(),
      heartRateSamples: heart,
      stepIntervals: steps,
      restingHeartRateRecords: rhr,
      sleepSessions: sessions,
      exerciseSessions: exercise,
      activeCaloriesIntervals: calories,
    );
  }

  String _recordLevelId({
    required String parentId,
    required String type,
    required String sourceId,
    required DateTime startUtc,
    required DateTime endUtc,
    required num roundedValue,
  }) {
    if (parentId.isNotEmpty) return parentId;
    return recordHash(
      type: type,
      sourceId: sourceId,
      startUtc: startUtc,
      endUtc: endUtc,
      roundedValue: roundedValue,
    );
  }
}
