import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../../features/assessment/domain/fatigue_assessment.dart';
import '../../features/health_connect/application/aggregator.dart';
import '../../features/health_connect/application/sync_window.dart';
import '../../features/health_connect/domain/health_records.dart';
import '../api/dto/api_dtos.dart';
import '../config/app_config.dart';

class SyncBatchFactory {
  const SyncBatchFactory();

  SyncBatchDto build({
    required String deviceId,
    required List<HourlyBin> bins,
    required List<DailyAggregate> days,
    required List<ExerciseSession> exercises,
    required List<FatigueAssessment> assessments,
    required DateTime generatedAtUtc,
    required SyncReplacementWindow replacementWindow,
  }) {
    final windowDto = ReplacementWindowDto(
      startUtc: replacementWindow.startUtc,
      endUtcExclusive: replacementWindow.endUtcExclusive,
      localDateStart: replacementWindow.localDateStart,
      localDateEndExclusive: replacementWindow.localDateEndExclusive,
    );
    final dto = SyncBatchDto(
      schemaVersion: AppConfig.syncSchemaVersion,
      deviceId: deviceId,
      idempotencyKey: '',
      generatedAtUtc: generatedAtUtc.toUtc(),
      replacementWindow: windowDto,
      hourlyBins: [
        for (final bin in bins)
          HourlyHealthBinDto(
            hourUtc: bin.hourUtc,
            zoneOffsetMinutes: bin.zoneOffsetMinutes,
            hrMean: bin.hrMean,
            hrMin: bin.hrMin,
            hrMax: bin.hrMax,
            hrSampleCount: bin.hrSampleCount,
            steps: bin.steps,
            activeCalories: bin.activeCalories,
            sourceId: bin.sourceId,
          ),
      ],
      dailySummaries: [
        for (final day in days)
          DailyHealthSummaryDto(
            localDate: day.localDate,
            timezone: 'device',
            sleepMinutes: day.sleepMinutes,
            steps: day.steps,
            averageHeartRate: day.averageHeartRate,
            minHeartRate: day.minHeartRate,
            maxHeartRate: day.maxHeartRate,
            restingHeartRate: day.restingHeartRate,
            activeCalories: day.activeCalories,
            exerciseCount: day.exerciseCount,
            exerciseDurationMinutes: day.exerciseDurationMinutes,
            coverageFlags: day.coverageFlags,
          ),
      ],
      exerciseSessions: [
        for (final session in exercises)
          ExerciseSessionDto(
            externalRecordId: session.recordId,
            type: session.type,
            startUtc: session.startUtc,
            endUtc: session.endUtc,
            zoneOffsetMinutes: session.zoneOffsetMinutes,
            durationMinutes: session.durationMinutes,
            calories: session.calories,
            sourceId: session.source.sourceId,
          ),
      ],
      fatigueAssessments: [
        for (final assessment in assessments)
          FatigueAssessmentDto(assessment: assessment),
      ],
    );
    final canonical = jsonEncode({
      'schemaVersion': dto.schemaVersion,
      'deviceId': dto.deviceId,
      'hourlyBins': dto.hourlyBins.map((item) => item.toJson()).toList(),
      'dailySummaries': dto.dailySummaries
          .map((item) => item.toJson())
          .toList(),
      'exerciseSessions': dto.exerciseSessions
          .map((item) => item.toJson())
          .toList(),
      'fatigueAssessments': dto.fatigueAssessments
          .map((item) => item.toJson())
          .toList(),
      'replacementWindow': windowDto.toJson(),
    });
    final key = sha256.convert(utf8.encode(canonical)).toString();
    return SyncBatchDto(
      schemaVersion: dto.schemaVersion,
      deviceId: dto.deviceId,
      idempotencyKey: key,
      generatedAtUtc: dto.generatedAtUtc,
      hourlyBins: dto.hourlyBins,
      dailySummaries: dto.dailySummaries,
      exerciseSessions: dto.exerciseSessions,
      fatigueAssessments: dto.fatigueAssessments,
      replacementWindow: windowDto,
    );
  }
}
