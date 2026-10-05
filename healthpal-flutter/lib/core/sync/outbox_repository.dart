import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/dto/api_dtos.dart';
import '../database/healthpal_database.dart';

class SyncOutboxRepository {
  SyncOutboxRepository({
    required HealthPalDatabase database,
    required ApiClient client,
  }) : _db = database,
       _client = client;

  final HealthPalDatabase _db;
  final ApiClient _client;
  static const _uuid = Uuid();
  static const _maxAttempts = 8;

  Future<void> enqueue(String userId, SyncBatchDto batch) async {
    final json = jsonEncode(batch.toJson());
    final hash = sha256.convert(utf8.encode(json)).toString();
    _db.connection.execute(
      '''
INSERT INTO outbox_events (id, user_id, idempotency_key, schema_version, payload_json, payload_hash, created_at_utc, next_attempt_at_utc)
VALUES (?,?,?,?,?,?,?,?)
ON CONFLICT(user_id, idempotency_key) DO NOTHING
''',
      [
        _uuid.v4(),
        userId,
        batch.idempotencyKey,
        batch.schemaVersion,
        json,
        hash,
        DateTime.now().toUtc().toIso8601String(),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<int> pendingCount(String userId) async {
    final rows = _db.connection.select(
      'SELECT COUNT(*) AS c FROM outbox_events WHERE user_id = ? AND sent_at_utc IS NULL AND dead_lettered = 0',
      [userId],
    );
    return rows.first['c'] as int;
  }

  Future<void> flush(String userId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = _db.connection.select(
      '''
SELECT * FROM outbox_events
WHERE user_id = ? AND sent_at_utc IS NULL AND dead_lettered = 0
  AND (next_attempt_at_utc IS NULL OR next_attempt_at_utc <= ?)
ORDER BY created_at_utc
''',
      [userId, now],
    );
    for (final row in rows) {
      try {
        await _client.raw.post<void>(
          '/api/v1/sync/batches',
          data: jsonDecode(row['payload_json'] as String),
        );
        _db.connection.execute(
          'UPDATE outbox_events SET sent_at_utc = ?, attempt_count = attempt_count + 1, last_attempt_at_utc = ? WHERE id = ?',
          [now, now, row['id']],
        );
      } on DioException catch (error) {
        final status = error.response?.statusCode ?? 0;
        if (status == 401) {
          return;
        }
        final attempts = (row['attempt_count'] as int? ?? 0) + 1;
        final transient =
            status == 0 || status == 408 || status == 429 || status >= 500;
        if (!transient && status >= 400 && status < 500) {
          _db.connection.execute(
            'UPDATE outbox_events SET dead_lettered = 1, attempt_count = ?, last_attempt_at_utc = ? WHERE id = ?',
            [attempts, now, row['id']],
          );
          continue;
        }
        _markAttempt(row['id'] as String, attempts, now);
        if (transient) {
          return;
        }
      }
    }
  }

  void _markAttempt(String id, int attempts, String nowIso) {
    final delayMinutes = min(pow(2, attempts).toInt(), 360);
    final next = DateTime.now().toUtc().add(Duration(minutes: delayMinutes));
    final dead = attempts >= _maxAttempts ? 1 : 0;
    _db.connection.execute(
      '''
UPDATE outbox_events
SET attempt_count = ?, last_attempt_at_utc = ?, next_attempt_at_utc = ?, dead_lettered = ?
WHERE id = ?
''',
      [attempts, nowIso, next.toIso8601String(), dead, id],
    );
  }
}
