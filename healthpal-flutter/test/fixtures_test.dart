import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/api/dto/api_dtos.dart';
import 'package:healthpal/core/config/app_config.dart';
import 'package:healthpal/features/assessment/domain/fatigue_assessment.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';

Map<String, dynamic> _load(String relativePath) {
  final file = File(relativePath);
  expect(file.existsSync(), isTrue, reason: relativePath);
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  test('Health Connect fixtures cover the four required states', () {
    for (final name in [
      'granted',
      'missing_permission',
      'no_data',
      'stale_data',
    ]) {
      final json = _load('test/fixtures/health_connect/$name.json');
      expect(json['state'], name);
      expect(json['availability'], 'available');
      final permissions = PermissionSnapshot.fromJson(
        json['permissions'] as Map<String, dynamic>,
      );
      final batch = IngestionBatch.fromJson(
        json['ingestion'] as Map<String, dynamic>,
      );

      switch (name) {
        case 'granted':
          expect(permissions.missing, isEmpty);
          expect(batch.isEmpty, isFalse);
          expect(
            batch.stepIntervals.any((item) => item.count == 683),
            isTrue,
            reason: 'delayed Health Sync interval must keep measurement time',
          );
        case 'missing_permission':
          expect(
            permissions.missing,
            containsAll([
              HealthPermission.sleep,
              HealthPermission.restingHeartRate,
            ]),
          );
          expect(batch.isEmpty, isTrue);
        case 'no_data':
          expect(permissions.missing, isEmpty);
          expect(batch.isEmpty, isTrue);
        case 'stale_data':
          expect(permissions.missing, isEmpty);
          final latest = DateTime.parse(json['latestDataAtUtc'] as String);
          final synced = DateTime.parse(json['lastSyncedAtUtc'] as String);
          expect(synced.isAfter(latest), isTrue);
          expect(synced.difference(latest).inHours >= 2, isTrue);
      }
    }
  });

  test('golden 48h fixture parses into domain + API DTOs', () {
    final json = _load('test/fixtures/golden/user_48h_health_records.json');
    final batch = IngestionBatch.fromJson(
      json['records'] as Map<String, dynamic>,
    );
    final assessment = FatigueAssessment.fromJson(
      json['assessment'] as Map<String, dynamic>,
    );

    expect(json['user']['id'], 'user-fixture-001');
    expect(batch.heartRateSamples, hasLength(144));
    expect(batch.stepIntervals.length, greaterThanOrEqualTo(48));
    expect(batch.exerciseSessions, hasLength(1));
    expect(batch.sleepSessions.single.healthDay, DateTime(2026, 9, 29));
    expect(batch.sleepSessions.single.sleepMinutes, greaterThanOrEqualTo(420));
    expect(
      batch.restingHeartRateRecords.single.localDate,
      DateTime(2026, 9, 29),
    );
    expect(assessment.modelVersion, AppConfig.fatigueModelVersion);
    expect(assessment.status, FatigueAssessmentStatus.signalDetected);
    expect(assessment.calibratedProbability, isNotNull);

    final dto = FatigueAssessmentDto(assessment: assessment);
    expect(
      FatigueAssessmentDto.fromJson(dto.toJson()).assessment.id,
      assessment.id,
    );
  });
}
