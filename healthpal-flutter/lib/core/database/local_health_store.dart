import 'dart:convert';

import '../../features/assessment/domain/fatigue_assessment.dart';
import '../../features/health_connect/application/aggregator.dart';
import '../../features/health_connect/application/canonicalizer.dart';
import '../../features/health_connect/application/record_identity.dart';
import '../../features/health_connect/application/sync_window.dart';
import '../../features/health_connect/domain/health_records.dart';
import '../sync/sync_state.dart';
import 'healthpal_database.dart';

class LocalHealthStore {
  LocalHealthStore(this._db);

  final HealthPalDatabase _db;
  int replaceCanonicalWindowCount = 0;
  int upsertCanonicalCount = 0;

  Future<T> transaction<T>(Future<T> Function() action) async {
    final db = _db.connection;
    db.execute('BEGIN');
    try {
      final result = await action();
      db.execute('COMMIT');
      return result;
    } catch (error) {
      db.execute('ROLLBACK');
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  Future<void> replaceCanonicalWindow({
    required String userId,
    required SyncReplacementWindow window,
    required CanonicalIngestion canonical,
    required List<HourlyBin> bins,
    required List<DailyAggregate> days,
    required SyncState state,
    bool transactional = true,
  }) async {
    replaceCanonicalWindowCount += 1;
    Future<void> body() async {
      _deleteCanonicalWindow(userId, window);
      await upsertCanonical(
        userId: userId,
        canonical: canonical,
        bins: bins,
        days: days,
        state: state,
        transactional: false,
      );
    }

    if (transactional) {
      await transaction(body);
    } else {
      await body();
    }
  }

  void _deleteCanonicalWindow(String userId, SyncReplacementWindow window) {
    final db = _db.connection;
    final start = _iso(window.startUtc);
    final end = _iso(window.endUtcExclusive);
    final dateStart = _date(window.localDateStart);
    final dateEnd = _date(window.localDateEndExclusive);
    db.execute(
      '''
DELETE FROM health_records_raw_index
WHERE user_id = ? AND end_utc > ? AND start_utc < ?
''',
      [userId, start, end],
    );
    db.execute(
      '''
DELETE FROM heart_rate_samples
WHERE user_id = ? AND start_utc >= ? AND start_utc < ?
''',
      [userId, start, end],
    );
    db.execute(
      '''
DELETE FROM step_intervals
WHERE user_id = ? AND end_utc > ? AND start_utc < ?
''',
      [userId, start, end],
    );
    db.execute(
      '''
DELETE FROM active_calories_intervals
WHERE user_id = ? AND end_utc > ? AND start_utc < ?
''',
      [userId, start, end],
    );
    db.execute(
      '''
DELETE FROM exercise_sessions
WHERE user_id = ? AND end_utc > ? AND start_utc < ?
''',
      [userId, start, end],
    );
    db.execute(
      '''
DELETE FROM resting_heart_rate_records
WHERE user_id = ? AND recorded_at_utc >= ? AND recorded_at_utc < ?
''',
      [userId, start, end],
    );
    db.execute(
      '''
DELETE FROM sleep_stages
WHERE user_id = ?
  AND session_record_id IN (
    SELECT record_id FROM sleep_sessions
    WHERE user_id = ? AND end_utc > ? AND start_utc < ?
  )
''',
      [userId, userId, start, end],
    );
    db.execute(
      '''
DELETE FROM sleep_stages
WHERE user_id = ? AND end_utc > ? AND start_utc < ?
''',
      [userId, start, end],
    );
    db.execute(
      '''
DELETE FROM sleep_sessions
WHERE user_id = ? AND end_utc > ? AND start_utc < ?
''',
      [userId, start, end],
    );
    db.execute(
      '''
DELETE FROM hourly_health_bins
WHERE user_id = ? AND hour_utc >= ? AND hour_utc < ?
''',
      [userId, start, end],
    );
    db.execute(
      '''
DELETE FROM daily_health_summaries
WHERE user_id = ? AND local_date >= ? AND local_date < ?
''',
      [userId, dateStart, dateEnd],
    );
  }

  Future<void> upsertCanonical({
    required String userId,
    required CanonicalIngestion canonical,
    required List<HourlyBin> bins,
    required List<DailyAggregate> days,
    required SyncState state,
    bool transactional = true,
  }) async {
    upsertCanonicalCount += 1;
    final db = _db.connection;
    if (transactional) db.execute('BEGIN');
    try {
      for (final sample in canonical.batch.heartRateSamples) {
        _upsertIndex(
          userId: userId,
          recordId: sample.recordId,
          type: 'hr',
          sourceId: sample.source.sourceId,
          startUtc: sample.startUtc,
          endUtc: sample.endUtc,
          roundedValue: sample.bpm.round(),
          modifiedAtUtc: sample.modifiedAtUtc,
        );
        db.execute(
          '''
INSERT INTO heart_rate_samples (user_id, record_id, start_utc, end_utc, zone_offset_minutes, bpm, source_id, source_name, modified_at_utc)
VALUES (?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, record_id) DO UPDATE SET
  start_utc=excluded.start_utc, end_utc=excluded.end_utc,
  zone_offset_minutes=excluded.zone_offset_minutes, bpm=excluded.bpm,
  source_id=excluded.source_id, source_name=excluded.source_name,
  modified_at_utc=excluded.modified_at_utc
''',
          [
            userId,
            sample.recordId,
            _iso(sample.startUtc),
            _iso(sample.endUtc),
            sample.zoneOffsetMinutes,
            sample.bpm,
            sample.source.sourceId,
            sample.source.sourceName,
            _isoOrNull(sample.modifiedAtUtc),
          ],
        );
      }
      for (final interval in canonical.batch.stepIntervals) {
        _upsertIndex(
          userId: userId,
          recordId: interval.recordId,
          type: 'steps',
          sourceId: interval.source.sourceId,
          startUtc: interval.startUtc,
          endUtc: interval.endUtc,
          roundedValue: interval.count,
          modifiedAtUtc: interval.modifiedAtUtc,
        );
        db.execute(
          '''
INSERT INTO step_intervals (user_id, record_id, start_utc, end_utc, zone_offset_minutes, count, source_id, source_name, modified_at_utc)
VALUES (?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, record_id) DO UPDATE SET
  start_utc=excluded.start_utc, end_utc=excluded.end_utc,
  zone_offset_minutes=excluded.zone_offset_minutes, count=excluded.count,
  source_id=excluded.source_id, source_name=excluded.source_name,
  modified_at_utc=excluded.modified_at_utc
''',
          [
            userId,
            interval.recordId,
            _iso(interval.startUtc),
            _iso(interval.endUtc),
            interval.zoneOffsetMinutes,
            interval.count,
            interval.source.sourceId,
            interval.source.sourceName,
            _isoOrNull(interval.modifiedAtUtc),
          ],
        );
      }
      for (final record in canonical.batch.restingHeartRateRecords) {
        _upsertIndex(
          userId: userId,
          recordId: record.recordId,
          type: 'rhr',
          sourceId: record.source.sourceId,
          startUtc: record.recordedAtUtc,
          endUtc: record.recordedAtUtc,
          roundedValue: record.bpm.round(),
          modifiedAtUtc: record.modifiedAtUtc,
        );
        db.execute(
          '''
INSERT INTO resting_heart_rate_records (user_id, record_id, recorded_at_utc, zone_offset_minutes, local_date, bpm, source_id, source_name, modified_at_utc)
VALUES (?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, record_id) DO UPDATE SET
  recorded_at_utc=excluded.recorded_at_utc, zone_offset_minutes=excluded.zone_offset_minutes,
  local_date=excluded.local_date, bpm=excluded.bpm, source_id=excluded.source_id,
  source_name=excluded.source_name, modified_at_utc=excluded.modified_at_utc
''',
          [
            userId,
            record.recordId,
            _iso(record.recordedAtUtc),
            record.zoneOffsetMinutes,
            _date(record.localDate),
            record.bpm,
            record.source.sourceId,
            record.source.sourceName,
            _isoOrNull(record.modifiedAtUtc),
          ],
        );
      }
      for (final session in canonical.batch.sleepSessions) {
        _upsertIndex(
          userId: userId,
          recordId: session.recordId,
          type: 'sleep',
          sourceId: session.source.sourceId,
          startUtc: session.startUtc,
          endUtc: session.endUtc,
          roundedValue: session.sleepMinutes,
          modifiedAtUtc: session.modifiedAtUtc,
        );
        db.execute(
          '''
INSERT INTO sleep_sessions (user_id, record_id, start_utc, end_utc, zone_offset_minutes, health_day, asleep_minutes_aggregate, source_id, source_name, modified_at_utc)
VALUES (?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, record_id) DO UPDATE SET
  start_utc=excluded.start_utc, end_utc=excluded.end_utc,
  zone_offset_minutes=excluded.zone_offset_minutes, health_day=excluded.health_day,
  asleep_minutes_aggregate=excluded.asleep_minutes_aggregate,
  source_id=excluded.source_id, source_name=excluded.source_name,
  modified_at_utc=excluded.modified_at_utc
''',
          [
            userId,
            session.recordId,
            _iso(session.startUtc),
            _iso(session.endUtc),
            session.zoneOffsetMinutes,
            _date(session.healthDay),
            session.asleepMinutesAggregate,
            session.source.sourceId,
            session.source.sourceName,
            _isoOrNull(session.modifiedAtUtc),
          ],
        );
        db.execute(
          'DELETE FROM sleep_stages WHERE user_id = ? AND session_record_id = ?',
          [userId, session.recordId],
        );
        for (final stage in session.stages) {
          final recordId = stage.recordId.isEmpty
              ? recordHash(
                  type: 'sleep_stage',
                  sourceId: (stage.source ?? session.source).sourceId,
                  startUtc: stage.startUtc,
                  endUtc: stage.endUtc,
                  roundedValue: stage.type.index,
                )
              : stage.recordId;
          db.execute(
            '''
INSERT INTO sleep_stages (user_id, session_record_id, record_id, start_utc, end_utc, stage_type, source_id, source_name, modified_at_utc)
VALUES (?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, session_record_id, record_id) DO UPDATE SET
  start_utc=excluded.start_utc, end_utc=excluded.end_utc, stage_type=excluded.stage_type,
  source_id=excluded.source_id, source_name=excluded.source_name,
  modified_at_utc=excluded.modified_at_utc
''',
            [
              userId,
              session.recordId,
              recordId,
              _iso(stage.startUtc),
              _iso(stage.endUtc),
              stage.type.name,
              (stage.source ?? session.source).sourceId,
              (stage.source ?? session.source).sourceName,
              _isoOrNull(stage.modifiedAtUtc),
            ],
          );
        }
      }
      for (final session in canonical.batch.exerciseSessions) {
        _upsertIndex(
          userId: userId,
          recordId: session.recordId,
          type: 'exercise',
          sourceId: session.source.sourceId,
          startUtc: session.startUtc,
          endUtc: session.endUtc,
          roundedValue: session.durationMinutes,
          modifiedAtUtc: session.modifiedAtUtc,
        );
        db.execute(
          '''
INSERT INTO exercise_sessions (user_id, record_id, start_utc, end_utc, zone_offset_minutes, type, title, duration_minutes, calories, source_id, source_name, modified_at_utc)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, record_id) DO UPDATE SET
  start_utc=excluded.start_utc, end_utc=excluded.end_utc,
  zone_offset_minutes=excluded.zone_offset_minutes, type=excluded.type,
  title=excluded.title, duration_minutes=excluded.duration_minutes,
  calories=excluded.calories, source_id=excluded.source_id,
  source_name=excluded.source_name, modified_at_utc=excluded.modified_at_utc
''',
          [
            userId,
            session.recordId,
            _iso(session.startUtc),
            _iso(session.endUtc),
            session.zoneOffsetMinutes,
            session.type,
            session.title,
            session.durationMinutes,
            session.calories,
            session.source.sourceId,
            session.source.sourceName,
            _isoOrNull(session.modifiedAtUtc),
          ],
        );
      }
      for (final interval in canonical.batch.activeCaloriesIntervals) {
        _upsertIndex(
          userId: userId,
          recordId: interval.recordId,
          type: 'calories',
          sourceId: interval.source.sourceId,
          startUtc: interval.startUtc,
          endUtc: interval.endUtc,
          roundedValue: interval.kilocalories.round(),
          modifiedAtUtc: interval.modifiedAtUtc,
        );
        db.execute(
          '''
INSERT INTO active_calories_intervals (user_id, record_id, start_utc, end_utc, zone_offset_minutes, kilocalories, source_id, source_name, modified_at_utc)
VALUES (?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, record_id) DO UPDATE SET
  start_utc=excluded.start_utc, end_utc=excluded.end_utc,
  zone_offset_minutes=excluded.zone_offset_minutes, kilocalories=excluded.kilocalories,
  source_id=excluded.source_id, source_name=excluded.source_name,
  modified_at_utc=excluded.modified_at_utc
''',
          [
            userId,
            interval.recordId,
            _iso(interval.startUtc),
            _iso(interval.endUtc),
            interval.zoneOffsetMinutes,
            interval.kilocalories,
            interval.source.sourceId,
            interval.source.sourceName,
            _isoOrNull(interval.modifiedAtUtc),
          ],
        );
      }
      for (final bin in bins) {
        db.execute(
          '''
INSERT INTO hourly_health_bins (user_id, hour_utc, zone_offset_minutes, hr_mean, hr_min, hr_max, hr_sample_count, steps, active_calories, source_id, coverage_complete, updated_at_utc)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, hour_utc, source_id) DO UPDATE SET
  zone_offset_minutes=excluded.zone_offset_minutes,
  hr_mean=excluded.hr_mean, hr_min=excluded.hr_min, hr_max=excluded.hr_max,
  hr_sample_count=excluded.hr_sample_count, steps=excluded.steps,
  active_calories=excluded.active_calories, coverage_complete=excluded.coverage_complete,
  updated_at_utc=excluded.updated_at_utc
''',
          [
            userId,
            _iso(bin.hourUtc),
            bin.zoneOffsetMinutes,
            bin.hrMean,
            bin.hrMin,
            bin.hrMax,
            bin.hrSampleCount,
            bin.steps,
            bin.activeCalories,
            bin.sourceId,
            bin.coverageComplete ? 1 : 0,
            _iso(DateTime.now().toUtc()),
          ],
        );
      }
      for (final day in days) {
        db.execute(
          '''
INSERT INTO daily_health_summaries (user_id, local_date, timezone, sleep_minutes, steps, average_heart_rate, min_heart_rate, max_heart_rate, resting_heart_rate, active_calories, exercise_count, exercise_duration_minutes, coverage_flags_json, updated_at_utc)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, local_date) DO UPDATE SET
  timezone=excluded.timezone, sleep_minutes=excluded.sleep_minutes, steps=excluded.steps,
  average_heart_rate=excluded.average_heart_rate, min_heart_rate=excluded.min_heart_rate,
  max_heart_rate=excluded.max_heart_rate, resting_heart_rate=excluded.resting_heart_rate,
  active_calories=excluded.active_calories, exercise_count=excluded.exercise_count,
  exercise_duration_minutes=excluded.exercise_duration_minutes,
  coverage_flags_json=excluded.coverage_flags_json, updated_at_utc=excluded.updated_at_utc
''',
          [
            userId,
            _date(day.localDate),
            'device',
            day.sleepMinutes,
            day.steps,
            day.averageHeartRate,
            day.minHeartRate,
            day.maxHeartRate,
            day.restingHeartRate,
            day.activeCalories,
            day.exerciseCount,
            day.exerciseDurationMinutes,
            jsonEncode(day.coverageFlags),
            _iso(DateTime.now().toUtc()),
          ],
        );
      }
      db.execute(
        '''
INSERT INTO sync_states (user_id, last_successful_sync_at_utc, source_watermark_utc, latest_data_at_utc, last_error, last_completed_phase, pending_outbox_count, preferred_source_id)
VALUES (?,?,?,?,?,?,?,?)
ON CONFLICT(user_id) DO UPDATE SET
  last_successful_sync_at_utc=excluded.last_successful_sync_at_utc,
  source_watermark_utc=excluded.source_watermark_utc,
  latest_data_at_utc=excluded.latest_data_at_utc,
  last_error=excluded.last_error,
  last_completed_phase=excluded.last_completed_phase,
  pending_outbox_count=excluded.pending_outbox_count,
  preferred_source_id=excluded.preferred_source_id
''',
        [
          userId,
          _isoOrNull(state.lastSuccessfulSyncAtUtc),
          _isoOrNull(state.sourceWatermarkUtc),
          _isoOrNull(state.latestDataAtUtc),
          state.lastError,
          state.lastCompletedPhase?.name,
          state.pendingOutboxCount,
          state.preferredSourceId,
        ],
      );
      if (transactional) db.execute('COMMIT');
    } catch (error) {
      if (transactional) db.execute('ROLLBACK');
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  Future<void> saveAssessment(
    String userId,
    FatigueAssessment assessment,
  ) async {
    _db.connection.execute(
      '''
INSERT INTO fatigue_assessments (user_id, id, evaluated_at_utc, local_date, model_version, base_probability, calibrated_probability, threshold, status, coverage_hours, latest_sample_at_utc, data_freshness_minutes, missing_reasons_json, feature_vector_hash, created_by, created_at_utc)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, evaluated_at_utc, model_version) DO UPDATE SET
  id=excluded.id, local_date=excluded.local_date,
  base_probability=excluded.base_probability,
  calibrated_probability=excluded.calibrated_probability,
  threshold=excluded.threshold, status=excluded.status,
  coverage_hours=excluded.coverage_hours,
  latest_sample_at_utc=excluded.latest_sample_at_utc,
  data_freshness_minutes=excluded.data_freshness_minutes,
  missing_reasons_json=excluded.missing_reasons_json,
  feature_vector_hash=excluded.feature_vector_hash,
  created_by=excluded.created_by, created_at_utc=excluded.created_at_utc
''',
      [
        userId,
        assessment.id,
        _iso(assessment.evaluatedAtUtc),
        _date(assessment.localDate),
        assessment.modelVersion,
        assessment.baseProbability,
        assessment.calibratedProbability,
        assessment.threshold,
        assessment.status.name,
        assessment.coverageHours,
        _isoOrNull(assessment.latestSampleAtUtc),
        assessment.dataFreshnessMinutes,
        jsonEncode(assessment.missingReasons),
        assessment.featureVectorHash,
        assessment.createdBy.name,
        _iso(DateTime.now().toUtc()),
      ],
    );
  }

  Future<void> recordSyncDiagnostic(String userId, String error) async {
    _db.connection.execute(
      '''
INSERT INTO sync_states (user_id, last_error, last_completed_phase, pending_outbox_count)
VALUES (?, ?, 'checkCapabilities', 0)
ON CONFLICT(user_id) DO UPDATE SET last_error=excluded.last_error
''',
      [userId, error],
    );
  }

  Future<SyncState> readSyncState(String userId) async {
    final rows = _db.connection.select(
      'SELECT * FROM sync_states WHERE user_id = ?',
      [userId],
    );
    if (rows.isEmpty) return const SyncState();
    final row = rows.first;
    return SyncState.fromJson({
      'lastSuccessfulSyncAtUtc': row['last_successful_sync_at_utc'],
      'sourceWatermarkUtc': row['source_watermark_utc'],
      'latestDataAtUtc': row['latest_data_at_utc'],
      'changeToken': row['change_token'],
      'lastError': row['last_error'],
      'lastCompletedPhase': row['last_completed_phase'],
      'pendingOutboxCount': row['pending_outbox_count'],
      'preferredSourceId': row['preferred_source_id'],
    });
  }

  Future<FatigueAssessment?> latestAssessment(
    String userId, {
    DateTime? day,
  }) async {
    final rows = day == null
        ? _db.connection.select(
            'SELECT * FROM fatigue_assessments WHERE user_id = ? ORDER BY evaluated_at_utc DESC LIMIT 1',
            [userId],
          )
        : _db.connection.select(
            '''
SELECT * FROM fatigue_assessments
WHERE user_id = ? AND local_date = ?
ORDER BY evaluated_at_utc DESC LIMIT 1
''',
            [userId, _date(day)],
          );
    if (rows.isEmpty) return null;
    return _assessment(rows.first);
  }

  Future<List<FatigueAssessment>> assessments(String userId) async {
    final rows = _db.connection.select(
      'SELECT * FROM fatigue_assessments WHERE user_id = ? ORDER BY evaluated_at_utc DESC',
      [userId],
    );
    return [for (final row in rows) _assessment(row)];
  }

  Future<Map<String, Object?>?> dailySummaryRow(
    String userId,
    DateTime day,
  ) async {
    final rows = _db.connection.select(
      'SELECT * FROM daily_health_summaries WHERE user_id = ? AND local_date = ?',
      [userId, _date(day)],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> dailySummaryRows(
    String userId, {
    required DateTime start,
    required DateTime end,
  }) {
    return Future.value(
      _db.connection.select(
        '''
SELECT * FROM daily_health_summaries
WHERE user_id = ? AND local_date >= ? AND local_date <= ?
ORDER BY local_date ASC
''',
        [userId, _date(start), _date(end)],
      ),
    );
  }

  Future<List<ExerciseSession>> exercisesForDay(
    String userId,
    DateTime day,
  ) async {
    final rows = _db.connection.select(
      '''
SELECT * FROM exercise_sessions
WHERE user_id = ?
ORDER BY start_utc ASC
''',
      [userId],
    );
    final target = DateTime(day.year, day.month, day.day);
    return [
      for (final row in rows)
        if (_localDate(
              DateTime.parse(row['start_utc'] as String),
              row['zone_offset_minutes'] as int,
            ) ==
            target)
          ExerciseSession(
            recordId: row['record_id'] as String,
            startUtc: DateTime.parse(row['start_utc'] as String),
            endUtc: DateTime.parse(row['end_utc'] as String),
            zoneOffsetMinutes: row['zone_offset_minutes'] as int,
            type: row['type'] as String,
            title: row['title'] as String?,
            durationMinutes: row['duration_minutes'] as int,
            calories: (row['calories'] as num?)?.toDouble(),
            source: SourceInfo(
              sourceId: row['source_id'] as String,
              sourceName: row['source_name'] as String,
            ),
            modifiedAtUtc: row['modified_at_utc'] == null
                ? null
                : DateTime.parse(row['modified_at_utc'] as String),
          ),
    ];
  }

  FatigueAssessment _assessment(Map<String, Object?> row) {
    return FatigueAssessment.fromJson({
      'id': row['id'],
      'evaluatedAtUtc': row['evaluated_at_utc'],
      'localDate': row['local_date'],
      'modelVersion': row['model_version'],
      'baseProbability': row['base_probability'],
      'calibratedProbability': row['calibrated_probability'],
      'threshold': row['threshold'],
      'status': row['status'],
      'coverageHours': row['coverage_hours'],
      'latestSampleAtUtc': row['latest_sample_at_utc'],
      'dataFreshnessMinutes': row['data_freshness_minutes'],
      'missingReasons': jsonDecode(row['missing_reasons_json'] as String),
      'featureVectorHash': row['feature_vector_hash'],
      'createdBy': row['created_by'],
    });
  }

  void _upsertIndex({
    required String userId,
    required String recordId,
    required String type,
    required String sourceId,
    required DateTime startUtc,
    required DateTime endUtc,
    required num roundedValue,
    DateTime? modifiedAtUtc,
  }) {
    final hash = recordHash(
      type: type,
      sourceId: sourceId,
      startUtc: startUtc,
      endUtc: endUtc,
      roundedValue: roundedValue,
    );
    _db.connection.execute(
      '''
INSERT INTO health_records_raw_index (user_id, record_id, record_hash, record_type, source_id, start_utc, end_utc, modified_at_utc)
VALUES (?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, record_id) DO UPDATE SET
  record_hash=excluded.record_hash, record_type=excluded.record_type,
  source_id=excluded.source_id, start_utc=excluded.start_utc, end_utc=excluded.end_utc,
  modified_at_utc=excluded.modified_at_utc
''',
      [
        userId,
        recordId,
        hash,
        type,
        sourceId,
        _iso(startUtc),
        _iso(endUtc),
        _isoOrNull(modifiedAtUtc),
      ],
    );
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();

  String? _isoOrNull(DateTime? value) => value?.toUtc().toIso8601String();

  String _date(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DateTime _localDate(DateTime utc, int zoneOffsetMinutes) {
    final local = utc.toUtc().add(Duration(minutes: zoneOffsetMinutes));
    return DateTime(local.year, local.month, local.day);
  }
}
