import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/api/dto/api_dtos.dart';
import 'package:healthpal/core/config/app_config.dart';
import 'package:healthpal/core/sync/sync_state.dart';
import 'package:healthpal/features/assessment/domain/fatigue_assessment.dart';
import 'package:healthpal/features/history/domain/daily_health_summary.dart'
    as history;
import 'package:healthpal/features/training/domain/training_models.dart'
    as training;

void main() {
  test('fatigue domain is independent of training readiness types', () {
    final assessment = FatigueAssessment(
      id: 'a1',
      evaluatedAtUtc: DateTime.utc(2026, 9, 30, 10),
      localDate: DateTime(2026, 9, 30),
      modelVersion: AppConfig.fatigueModelVersion,
      baseProbability: 0.2,
      calibratedProbability: 0.15,
      threshold: AppConfig.fatigueDecisionThreshold,
      status: FatigueAssessmentStatus.noClearSignal,
      coverageHours: 5,
      featureVectorHash: 'hash',
      createdBy: AssessmentCreatedBy.background,
    );
    expect(assessment.statusLabel, 'Chưa thấy tín hiệu mệt mỏi');
    expect(assessment.toJson()['modelVersion'], 'healthpal_fatigue_v4');
  });

  test('fatigue status labels expose no probability or severity scale', () {
    final detected = FatigueAssessment(
      id: 'a2',
      evaluatedAtUtc: DateTime.utc(2026, 9, 30, 10),
      localDate: DateTime(2026, 9, 30),
      modelVersion: AppConfig.fatigueModelVersion,
      calibratedProbability: 0.24,
      threshold: AppConfig.fatigueDecisionThreshold,
      status: FatigueAssessmentStatus.signalDetected,
      coverageHours: 6,
      featureVectorHash: 'hash-2',
      createdBy: AssessmentCreatedBy.foreground,
    );
    expect(detected.statusLabel, 'Có dấu hiệu mệt mỏi');
  });

  test('history DailyHealthSummary does not import training domain', () {
    final summary = history.DailyHealthSummary(
      date: DateTime(2026, 9, 30),
      sleepMinutes: 420,
      steps: 8000,
      restingHeartRate: 60,
      hrv: 40,
      activeCalories: 300,
    );
    expect(summary.valueFor(history.HistoryMetric.steps), 8000);
  });

  test('training owns its legacy StressLevel without history imports', () {
    expect(training.StressLevel.high.rank, 3);
    final input = training.TrainingReadinessInput(
      stress: training.StressLevel.low,
      sleepMinutes: 450,
      steps: 6000,
      activeCalories: 200,
      collectedAt: DateTime.utc(2026, 9, 30),
    );
    expect(input.stress?.rank, 1);
  });

  test(
    'schema v1 outbox JSON still deserializes without a replacement window',
    () {
      final restored = SyncBatchDto.fromJson({
        'schemaVersion': 1,
        'deviceId': 'android-1',
        'idempotencyKey': 'idem-1',
        'generatedAtUtc': '2026-09-30T10:00:00.000Z',
        'hourlyBins': <Map<String, dynamic>>[],
        'dailySummaries': [
          {
            'localDate': '2026-09-30',
            'timezone': 'Asia/Ho_Chi_Minh',
            'steps': 0,
            'coverageFlags': {'stepsComplete': true, 'sleepComplete': false},
          },
        ],
        'exerciseSessions': <Map<String, dynamic>>[],
        'fatigueAssessments': <Map<String, dynamic>>[],
      });
      expect(restored.schemaVersion, 1);
      expect(restored.replacementWindow, isNull);
      expect(restored.dailySummaries.single.steps, 0);
      expect(restored.dailySummaries.single.sleepMinutes, isNull);
    },
  );

  test('schema v2 round-trips replacement window', () {
    final batch = SyncBatchDto(
      schemaVersion: AppConfig.syncSchemaVersion,
      deviceId: 'android-1',
      idempotencyKey: 'idem-2',
      generatedAtUtc: DateTime.utc(2026, 9, 30, 10),
      replacementWindow: ReplacementWindowDto(
        startUtc: DateTime.utc(2026, 9, 28),
        endUtcExclusive: DateTime.utc(2026, 9, 30, 10),
        localDateStart: DateTime(2026, 9, 28),
        localDateEndExclusive: DateTime(2026, 10, 1),
      ),
    );
    final restored = SyncBatchDto.fromJson(batch.toJson());
    expect(restored.schemaVersion, 2);
    expect(restored.replacementWindow?.startUtc, DateTime.utc(2026, 9, 28));
    expect(
      restored.replacementWindow?.endUtcExclusive,
      DateTime.utc(2026, 9, 30, 10),
    );
    expect(restored.toJson()['replacementWindow'], isA<Map<String, dynamic>>());
  });

  test('SyncState distinguishes last sync from latest physiology time', () {
    final state = SyncState(
      lastSuccessfulSyncAtUtc: DateTime.utc(2026, 9, 30, 10),
      latestDataAtUtc: DateTime.utc(2026, 9, 30, 4),
      pendingOutboxCount: 2,
      lastCompletedPhase: SyncPhase.enqueueOutbox,
    );
    expect(state.hasPendingUpload, isTrue);
    expect(
      state.lastSuccessfulSyncAtUtc!.isAfter(state.latestDataAtUtc!),
      isTrue,
    );
  });
}
