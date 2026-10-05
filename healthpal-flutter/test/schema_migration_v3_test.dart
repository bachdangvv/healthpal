import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/database/healthpal_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema v2 migrates to v3, invalidates HC data, keeps auth/device', () {
    final dir = Directory.systemTemp.createTempSync('healthpal-v2');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final path = p.join(dir.path, 'healthpal.sqlite');
    final raw = sqlite3.open(path);
    for (final stmt in _v2Ddl) {
      raw.execute(stmt);
    }
    raw.execute('INSERT INTO schema_meta(version) VALUES (2)');
    raw.execute('''
INSERT INTO heart_rate_samples (
  user_id, record_id, start_utc, end_utc, zone_offset_minutes, bpm, source_id, source_name
) VALUES ('u1', 'parent-hr', '2026-09-30T08:00:00.000Z', '2026-09-30T08:00:00.000Z', 0, 62, '', 'Health Sync')
''');
    raw.execute('''
INSERT INTO sleep_sessions (
  user_id, record_id, start_utc, end_utc, zone_offset_minutes, health_day, source_id, source_name
) VALUES ('u1', 'sleep', '2026-09-29T16:00:00.000Z', '2026-09-29T22:00:00.000Z', 0, '2026-09-30', '', 'Health Sync')
''');
    raw.execute('''
INSERT INTO sleep_stages (
  user_id, session_record_id, record_id, start_utc, end_utc, stage_type, source_id, source_name
) VALUES ('u1', 'sleep', 'sleep', '2026-09-29T16:00:00.000Z', '2026-09-29T18:00:00.000Z', 'light', '', 'Health Sync')
''');
    raw.execute('''
INSERT INTO hourly_health_bins (
  user_id, hour_utc, zone_offset_minutes, hr_sample_count, source_id, coverage_complete, updated_at_utc
) VALUES ('u1', '2026-09-30T08:00:00.000Z', 0, 1, '', 0, '2026-09-30T09:00:00.000Z')
''');
    raw.execute('''
INSERT INTO daily_health_summaries (
  user_id, local_date, timezone, steps, exercise_count, exercise_duration_minutes, coverage_flags_json, updated_at_utc
) VALUES ('u1', '2026-09-30', 'local', 100, 0, 0, '{}', '2026-09-30T09:00:00.000Z')
''');
    raw.execute('''
INSERT INTO fatigue_assessments (
  user_id, id, evaluated_at_utc, local_date, model_version, threshold, status, coverage_hours,
  missing_reasons_json, feature_vector_hash, created_by, created_at_utc
) VALUES (
  'u1', 'a1', '2026-09-30T09:00:00.000Z', '2026-09-30', 'healthpal_fatigue_v4', 0.18,
  'insufficientData', 0, '[]', 'hash', 'foreground', '2026-09-30T09:00:00.000Z'
)
''');
    raw.execute('''
INSERT INTO sync_states (
  user_id, last_successful_sync_at_utc, source_watermark_utc, latest_data_at_utc, last_error,
  last_completed_phase, pending_outbox_count, preferred_source_id
) VALUES ('u1', '2026-09-30T09:00:00.000Z', '2026-09-30T09:00:00.000Z', '2026-09-30T08:00:00.000Z',
  'old', 'refreshUi', 1, '')
''');
    raw.execute('''
INSERT INTO outbox_events (
  id, user_id, idempotency_key, schema_version, payload_json, payload_hash, created_at_utc, attempt_count, dead_lettered
) VALUES ('o1', 'u1', 'pending-key', 1, '{}', 'hash', '2026-09-30T09:00:00.000Z', 1, 0)
''');
    raw.execute('''
INSERT INTO outbox_events (
  id, user_id, idempotency_key, schema_version, payload_json, payload_hash, created_at_utc, attempt_count, dead_lettered, sent_at_utc
) VALUES ('o2', 'u1', 'sent-key', 1, '{}', 'hash2', '2026-09-30T08:00:00.000Z', 1, 0, '2026-09-30T08:30:00.000Z')
''');
    raw.execute('''
INSERT INTO device_settings (user_id, health_connect_sync, auto_sync, wifi_only, updated_at_utc)
VALUES ('u1', 1, 1, 0, '2026-09-30T09:00:00.000Z')
''');
    raw.execute('''
INSERT INTO cached_profiles (user_id, payload_json, cached_at_utc)
VALUES ('u1', '{"displayName":"Minh"}', '2026-09-30T09:00:00.000Z')
''');
    raw.dispose();

    final db = HealthPalDatabase.file(path);
    expect(
      db.connection.select('SELECT version FROM schema_meta').first['version'],
      3,
    );
    expect(
      db.connection
          .select('SELECT COUNT(*) AS c FROM heart_rate_samples')
          .first['c'],
      0,
    );
    expect(
      db.connection
          .select('SELECT COUNT(*) AS c FROM sleep_sessions')
          .first['c'],
      0,
    );
    expect(
      db.connection.select('SELECT COUNT(*) AS c FROM sleep_stages').first['c'],
      0,
    );
    expect(
      db.connection
          .select('SELECT COUNT(*) AS c FROM hourly_health_bins')
          .first['c'],
      0,
    );
    expect(
      db.connection
          .select('SELECT COUNT(*) AS c FROM daily_health_summaries')
          .first['c'],
      0,
    );
    expect(
      db.connection
          .select('SELECT COUNT(*) AS c FROM fatigue_assessments')
          .first['c'],
      0,
    );
    expect(
      db.connection
          .select(
            'SELECT COUNT(*) AS c FROM outbox_events WHERE sent_at_utc IS NULL',
          )
          .first['c'],
      0,
    );
    expect(
      db.connection
          .select(
            'SELECT COUNT(*) AS c FROM outbox_events WHERE sent_at_utc IS NOT NULL',
          )
          .first['c'],
      1,
    );
    final settings = db.connection.select(
      'SELECT health_connect_sync, auto_sync FROM device_settings WHERE user_id = ?',
      ['u1'],
    ).single;
    expect(settings['health_connect_sync'], 1);
    expect(settings['auto_sync'], 1);
    expect(
      db.connection.select(
        'SELECT payload_json FROM cached_profiles WHERE user_id = ?',
        ['u1'],
      ).single['payload_json'],
      '{"displayName":"Minh"}',
    );
    final sync = db.connection.select(
      'SELECT source_watermark_utc, last_successful_sync_at_utc, preferred_source_id FROM sync_states WHERE user_id = ?',
      ['u1'],
    ).single;
    expect(sync['source_watermark_utc'], isNull);
    expect(sync['last_successful_sync_at_utc'], isNull);
    expect(sync['preferred_source_id'], isNull);
    db.dispose();

    final again = HealthPalDatabase.file(path);
    expect(
      again.connection
          .select('SELECT version FROM schema_meta')
          .first['version'],
      3,
    );
    expect(
      again.connection
          .select('SELECT COUNT(*) AS c FROM device_settings')
          .first['c'],
      1,
    );
    again.dispose();
  });
}

const _v2Ddl = <String>[
  'CREATE TABLE schema_meta (version INTEGER NOT NULL)',
  '''
CREATE TABLE health_records_raw_index (
  user_id TEXT NOT NULL, record_id TEXT NOT NULL, record_hash TEXT NOT NULL,
  record_type TEXT NOT NULL, source_id TEXT NOT NULL, start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL, modified_at_utc TEXT, PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE heart_rate_samples (
  user_id TEXT NOT NULL, record_id TEXT NOT NULL, start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL, zone_offset_minutes INTEGER NOT NULL, bpm REAL NOT NULL,
  source_id TEXT NOT NULL, source_name TEXT NOT NULL, modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE step_intervals (
  user_id TEXT NOT NULL, record_id TEXT NOT NULL, start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL, zone_offset_minutes INTEGER NOT NULL, count INTEGER NOT NULL,
  source_id TEXT NOT NULL, source_name TEXT NOT NULL, modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE resting_heart_rate_records (
  user_id TEXT NOT NULL, record_id TEXT NOT NULL, recorded_at_utc TEXT NOT NULL,
  zone_offset_minutes INTEGER NOT NULL, local_date TEXT NOT NULL, bpm REAL NOT NULL,
  source_id TEXT NOT NULL, source_name TEXT NOT NULL, modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE sleep_sessions (
  user_id TEXT NOT NULL, record_id TEXT NOT NULL, start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL, zone_offset_minutes INTEGER NOT NULL, health_day TEXT NOT NULL,
  asleep_minutes_aggregate INTEGER, source_id TEXT NOT NULL, source_name TEXT NOT NULL,
  modified_at_utc TEXT, PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE sleep_stages (
  user_id TEXT NOT NULL, session_record_id TEXT NOT NULL, record_id TEXT NOT NULL,
  start_utc TEXT NOT NULL, end_utc TEXT NOT NULL, stage_type TEXT NOT NULL,
  source_id TEXT NOT NULL, source_name TEXT NOT NULL, modified_at_utc TEXT,
  PRIMARY KEY (user_id, session_record_id, record_id)
)
''',
  '''
CREATE TABLE exercise_sessions (
  user_id TEXT NOT NULL, record_id TEXT NOT NULL, start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL, zone_offset_minutes INTEGER NOT NULL, type TEXT NOT NULL,
  title TEXT, duration_minutes INTEGER NOT NULL, calories REAL, source_id TEXT NOT NULL,
  source_name TEXT NOT NULL, modified_at_utc TEXT, PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE active_calories_intervals (
  user_id TEXT NOT NULL, record_id TEXT NOT NULL, start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL, zone_offset_minutes INTEGER NOT NULL, kilocalories REAL NOT NULL,
  source_id TEXT NOT NULL, source_name TEXT NOT NULL, modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE hourly_health_bins (
  user_id TEXT NOT NULL, hour_utc TEXT NOT NULL, zone_offset_minutes INTEGER NOT NULL,
  hr_mean REAL, hr_min REAL, hr_max REAL, hr_sample_count INTEGER NOT NULL DEFAULT 0,
  steps INTEGER, active_calories REAL, source_id TEXT NOT NULL,
  coverage_complete INTEGER NOT NULL DEFAULT 0, updated_at_utc TEXT NOT NULL,
  PRIMARY KEY (user_id, hour_utc, source_id)
)
''',
  '''
CREATE TABLE daily_health_summaries (
  user_id TEXT NOT NULL, local_date TEXT NOT NULL, timezone TEXT NOT NULL,
  sleep_minutes INTEGER, steps INTEGER, average_heart_rate REAL, min_heart_rate REAL,
  max_heart_rate REAL, resting_heart_rate REAL, active_calories REAL,
  exercise_count INTEGER NOT NULL DEFAULT 0, exercise_duration_minutes INTEGER NOT NULL DEFAULT 0,
  coverage_flags_json TEXT NOT NULL DEFAULT '{}', updated_at_utc TEXT NOT NULL,
  PRIMARY KEY (user_id, local_date)
)
''',
  '''
CREATE TABLE fatigue_assessments (
  user_id TEXT NOT NULL, id TEXT NOT NULL, evaluated_at_utc TEXT NOT NULL,
  local_date TEXT NOT NULL, model_version TEXT NOT NULL, base_probability REAL,
  calibrated_probability REAL, threshold REAL NOT NULL, status TEXT NOT NULL,
  coverage_hours INTEGER NOT NULL, latest_sample_at_utc TEXT, data_freshness_minutes INTEGER,
  missing_reasons_json TEXT NOT NULL DEFAULT '[]', feature_vector_hash TEXT NOT NULL,
  created_by TEXT NOT NULL, created_at_utc TEXT NOT NULL, PRIMARY KEY (user_id, id)
)
''',
  '''
CREATE TABLE sync_states (
  user_id TEXT NOT NULL PRIMARY KEY, last_successful_sync_at_utc TEXT,
  source_watermark_utc TEXT, latest_data_at_utc TEXT, change_token TEXT,
  last_error TEXT, last_completed_phase TEXT, pending_outbox_count INTEGER NOT NULL DEFAULT 0,
  preferred_source_id TEXT
)
''',
  '''
CREATE TABLE outbox_events (
  id TEXT NOT NULL PRIMARY KEY, user_id TEXT NOT NULL, idempotency_key TEXT NOT NULL,
  schema_version INTEGER NOT NULL, payload_json TEXT NOT NULL, payload_hash TEXT NOT NULL,
  created_at_utc TEXT NOT NULL, attempt_count INTEGER NOT NULL DEFAULT 0,
  last_attempt_at_utc TEXT, dead_lettered INTEGER NOT NULL DEFAULT 0, sent_at_utc TEXT,
  next_attempt_at_utc TEXT, UNIQUE (user_id, idempotency_key)
)
''',
  '''
CREATE TABLE cached_profiles (
  user_id TEXT NOT NULL PRIMARY KEY, payload_json TEXT NOT NULL, cached_at_utc TEXT NOT NULL
)
''',
  '''
CREATE TABLE device_settings (
  user_id TEXT NOT NULL PRIMARY KEY, health_connect_sync INTEGER NOT NULL DEFAULT 0,
  auto_sync INTEGER NOT NULL DEFAULT 1, wifi_only INTEGER NOT NULL DEFAULT 0,
  updated_at_utc TEXT NOT NULL
)
''',
];
