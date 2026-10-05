import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Local SQLite store. Schema matches `tables.dart`. Drift codegen is blocked
/// on Dart 3.10 `build_runner` native-asset hooks, so sqlite3 is the runtime.
class HealthPalDatabase {
  HealthPalDatabase._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    _create();
  }

  factory HealthPalDatabase.memory() =>
      HealthPalDatabase._(sqlite3.openInMemory());

  factory HealthPalDatabase.file(String path) =>
      HealthPalDatabase._(sqlite3.open(path));

  static Future<HealthPalDatabase> appFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return HealthPalDatabase.file(p.join(dir.path, 'healthpal.sqlite'));
  }

  final Database _db;
  static const schemaVersion = 3;

  Database get connection => _db;

  void _create() {
    _db.execute(
      'CREATE TABLE IF NOT EXISTS schema_meta (version INTEGER NOT NULL)',
    );
    final versionRows = _db.select('SELECT version FROM schema_meta');
    if (versionRows.isEmpty) {
      for (final stmt in _ddl) {
        _db.execute(stmt);
      }
      _db.execute('INSERT INTO schema_meta(version) VALUES (?)', [
        schemaVersion,
      ]);
      return;
    }
    var version = versionRows.first['version'] as int;
    if (version < 2) {
      _migrateTo2();
      version = 2;
    }
    if (version < 3) {
      _migrateTo3();
      version = 3;
    }
    if (version != schemaVersion) {
      throw StateError('Unsupported HealthPal schema version $version');
    }
  }

  void _migrateTo2() {
    void addColumn(String sql) {
      try {
        _db.execute(sql);
      } catch (_) {
        // Column already exists on a partially migrated database.
      }
    }

    addColumn('ALTER TABLE sleep_stages ADD COLUMN record_id TEXT');
    addColumn('ALTER TABLE sleep_stages ADD COLUMN source_id TEXT');
    addColumn('ALTER TABLE sleep_stages ADD COLUMN source_name TEXT');
    addColumn('ALTER TABLE sleep_stages ADD COLUMN modified_at_utc TEXT');
    addColumn('ALTER TABLE outbox_events ADD COLUMN next_attempt_at_utc TEXT');
    _db.execute(
      "UPDATE sleep_stages SET record_id = 'legacy-' || id WHERE record_id IS NULL OR record_id = ''",
    );
    _db.execute(
      "UPDATE sleep_stages SET source_id = '' WHERE source_id IS NULL",
    );
    _db.execute(
      "UPDATE sleep_stages SET source_name = '' WHERE source_name IS NULL",
    );
    _db.execute('''
CREATE UNIQUE INDEX IF NOT EXISTS sleep_stages_identity
ON sleep_stages(user_id, session_record_id, record_id)
''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS device_settings (
  user_id TEXT NOT NULL PRIMARY KEY,
  health_connect_sync INTEGER NOT NULL DEFAULT 0,
  auto_sync INTEGER NOT NULL DEFAULT 1,
  wifi_only INTEGER NOT NULL DEFAULT 0,
  updated_at_utc TEXT NOT NULL
)
''');
    _db.execute('UPDATE schema_meta SET version = 2');
  }

  void _migrateTo3() {
    _db.execute('BEGIN');
    try {
      const derived = [
        'health_records_raw_index',
        'heart_rate_samples',
        'step_intervals',
        'resting_heart_rate_records',
        'sleep_stages',
        'sleep_sessions',
        'exercise_sessions',
        'active_calories_intervals',
        'hourly_health_bins',
        'daily_health_summaries',
        'fatigue_assessments',
      ];
      for (final table in derived) {
        _db.execute('DELETE FROM $table');
      }
      _db.execute('DELETE FROM outbox_events WHERE sent_at_utc IS NULL');
      _db.execute('''
UPDATE sync_states SET
  last_successful_sync_at_utc = NULL,
  source_watermark_utc = NULL,
  latest_data_at_utc = NULL,
  last_error = NULL,
  last_completed_phase = NULL,
  preferred_source_id = NULL
''');
      _db.execute('UPDATE schema_meta SET version = 3');
      _db.execute('COMMIT');
    } catch (error) {
      _db.execute('ROLLBACK');
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  Future<void> deleteUserPartition(String userId) async {
    final tables = [
      'health_records_raw_index',
      'heart_rate_samples',
      'step_intervals',
      'resting_heart_rate_records',
      'sleep_stages',
      'sleep_sessions',
      'exercise_sessions',
      'active_calories_intervals',
      'hourly_health_bins',
      'daily_health_summaries',
      'fatigue_assessments',
      'sync_states',
      'outbox_events',
      'cached_profiles',
      'device_settings',
    ];
    _db.execute('BEGIN');
    try {
      for (final table in tables) {
        _db.execute('DELETE FROM $table WHERE user_id = ?', [userId]);
      }
      _db.execute('COMMIT');
    } catch (error) {
      _db.execute('ROLLBACK');
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  Future<int> count(String table, String userId) async {
    final rows = _db.select(
      'SELECT COUNT(*) AS c FROM $table WHERE user_id = ?',
      [userId],
    );
    return rows.first['c'] as int;
  }

  void dispose() => _db.dispose();
}

const _ddl = <String>[
  '''
CREATE TABLE IF NOT EXISTS health_records_raw_index (
  user_id TEXT NOT NULL,
  record_id TEXT NOT NULL,
  record_hash TEXT NOT NULL,
  record_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL,
  modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id),
  UNIQUE (user_id, record_hash)
)
''',
  '''
CREATE TABLE IF NOT EXISTS heart_rate_samples (
  user_id TEXT NOT NULL,
  record_id TEXT NOT NULL,
  start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL,
  zone_offset_minutes INTEGER NOT NULL,
  bpm REAL NOT NULL,
  source_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE IF NOT EXISTS step_intervals (
  user_id TEXT NOT NULL,
  record_id TEXT NOT NULL,
  start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL,
  zone_offset_minutes INTEGER NOT NULL,
  count INTEGER NOT NULL CHECK (count >= 0),
  source_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE IF NOT EXISTS resting_heart_rate_records (
  user_id TEXT NOT NULL,
  record_id TEXT NOT NULL,
  recorded_at_utc TEXT NOT NULL,
  zone_offset_minutes INTEGER NOT NULL,
  local_date TEXT NOT NULL,
  bpm REAL NOT NULL,
  source_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE IF NOT EXISTS sleep_sessions (
  user_id TEXT NOT NULL,
  record_id TEXT NOT NULL,
  start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL,
  zone_offset_minutes INTEGER NOT NULL,
  health_day TEXT NOT NULL,
  asleep_minutes_aggregate INTEGER,
  source_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE IF NOT EXISTS sleep_stages (
  user_id TEXT NOT NULL,
  session_record_id TEXT NOT NULL,
  record_id TEXT NOT NULL,
  start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL,
  stage_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  modified_at_utc TEXT,
  PRIMARY KEY (user_id, session_record_id, record_id)
)
''',
  '''
CREATE TABLE IF NOT EXISTS exercise_sessions (
  user_id TEXT NOT NULL,
  record_id TEXT NOT NULL,
  start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL,
  zone_offset_minutes INTEGER NOT NULL,
  type TEXT NOT NULL,
  title TEXT,
  duration_minutes INTEGER NOT NULL CHECK (duration_minutes >= 0),
  calories REAL,
  source_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE IF NOT EXISTS active_calories_intervals (
  user_id TEXT NOT NULL,
  record_id TEXT NOT NULL,
  start_utc TEXT NOT NULL,
  end_utc TEXT NOT NULL,
  zone_offset_minutes INTEGER NOT NULL,
  kilocalories REAL NOT NULL,
  source_id TEXT NOT NULL,
  source_name TEXT NOT NULL,
  modified_at_utc TEXT,
  PRIMARY KEY (user_id, record_id)
)
''',
  '''
CREATE TABLE IF NOT EXISTS hourly_health_bins (
  user_id TEXT NOT NULL,
  hour_utc TEXT NOT NULL,
  zone_offset_minutes INTEGER NOT NULL,
  hr_mean REAL,
  hr_min REAL,
  hr_max REAL,
  hr_sample_count INTEGER NOT NULL DEFAULT 0,
  steps INTEGER,
  active_calories REAL,
  source_id TEXT NOT NULL,
  coverage_complete INTEGER NOT NULL DEFAULT 0,
  updated_at_utc TEXT NOT NULL,
  PRIMARY KEY (user_id, hour_utc, source_id)
)
''',
  '''
CREATE TABLE IF NOT EXISTS daily_health_summaries (
  user_id TEXT NOT NULL,
  local_date TEXT NOT NULL,
  timezone TEXT NOT NULL,
  sleep_minutes INTEGER,
  steps INTEGER,
  average_heart_rate REAL,
  min_heart_rate REAL,
  max_heart_rate REAL,
  resting_heart_rate REAL,
  active_calories REAL,
  exercise_count INTEGER NOT NULL DEFAULT 0,
  exercise_duration_minutes INTEGER NOT NULL DEFAULT 0,
  coverage_flags_json TEXT NOT NULL DEFAULT '{}',
  updated_at_utc TEXT NOT NULL,
  PRIMARY KEY (user_id, local_date)
)
''',
  '''
CREATE TABLE IF NOT EXISTS fatigue_assessments (
  user_id TEXT NOT NULL,
  id TEXT NOT NULL,
  evaluated_at_utc TEXT NOT NULL,
  local_date TEXT NOT NULL,
  model_version TEXT NOT NULL,
  base_probability REAL,
  calibrated_probability REAL,
  threshold REAL NOT NULL,
  status TEXT NOT NULL,
  coverage_hours INTEGER NOT NULL,
  latest_sample_at_utc TEXT,
  data_freshness_minutes INTEGER,
  missing_reasons_json TEXT NOT NULL DEFAULT '[]',
  feature_vector_hash TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at_utc TEXT NOT NULL,
  PRIMARY KEY (user_id, id),
  UNIQUE (user_id, evaluated_at_utc, model_version)
)
''',
  '''
CREATE TABLE IF NOT EXISTS sync_states (
  user_id TEXT NOT NULL PRIMARY KEY,
  last_successful_sync_at_utc TEXT,
  source_watermark_utc TEXT,
  latest_data_at_utc TEXT,
  change_token TEXT,
  last_error TEXT,
  last_completed_phase TEXT,
  pending_outbox_count INTEGER NOT NULL DEFAULT 0,
  preferred_source_id TEXT
)
''',
  '''
CREATE TABLE IF NOT EXISTS outbox_events (
  id TEXT NOT NULL PRIMARY KEY,
  user_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  payload_json TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  created_at_utc TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  last_attempt_at_utc TEXT,
  dead_lettered INTEGER NOT NULL DEFAULT 0,
  sent_at_utc TEXT,
  next_attempt_at_utc TEXT,
  UNIQUE (user_id, idempotency_key)
)
''',
  '''
CREATE TABLE IF NOT EXISTS cached_profiles (
  user_id TEXT NOT NULL PRIMARY KEY,
  payload_json TEXT NOT NULL,
  cached_at_utc TEXT NOT NULL
)
''',
  '''
CREATE TABLE IF NOT EXISTS device_settings (
  user_id TEXT NOT NULL PRIMARY KEY,
  health_connect_sync INTEGER NOT NULL DEFAULT 0,
  auto_sync INTEGER NOT NULL DEFAULT 1,
  wifi_only INTEGER NOT NULL DEFAULT 0,
  updated_at_utc TEXT NOT NULL
)
''',
];
