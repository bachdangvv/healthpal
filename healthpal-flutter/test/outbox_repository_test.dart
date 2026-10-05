import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/api/api_client.dart';
import 'package:healthpal/core/api/dto/api_dtos.dart';
import 'package:healthpal/core/auth/secure_token_store.dart';
import 'package:healthpal/core/database/healthpal_database.dart';
import 'package:healthpal/core/sync/outbox_repository.dart';

void main() {
  SyncBatchDto batch(String key) => SyncBatchDto(
    deviceId: 'device',
    idempotencyKey: key,
    generatedAtUtc: DateTime.utc(2026, 9, 30),
  );

  test('same logical batch enqueues once', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final outbox = SyncOutboxRepository(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore()),
    );
    await outbox.enqueue('u1', batch('abc'));
    await outbox.enqueue('u1', batch('abc'));
    expect(await outbox.pendingCount('u1'), 1);
  });

  test('5xx backs off and 4xx dead-letters', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final adapter = _StatusAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = adapter;
    final outbox = SyncOutboxRepository(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore(), dio: dio),
    );
    await outbox.enqueue('u1', batch('five'));
    adapter.status = 503;
    await outbox.flush('u1');
    expect(await outbox.pendingCount('u1'), 1);
    expect(_row(db, 'u1')['attempt_count'], 1);
    expect(_row(db, 'u1')['dead_lettered'], 0);

    adapter.status = 400;
    db.connection.execute("UPDATE outbox_events SET next_attempt_at_utc = ?", [
      DateTime.now().toUtc().toIso8601String(),
    ]);
    await outbox.flush('u1');
    expect(await outbox.pendingCount('u1'), 0);
    expect(_row(db, 'u1')['dead_lettered'], 1);
  });

  test(
    '401 keeps attempt count and stays pending across many flushes',
    () async {
      final db = HealthPalDatabase.memory();
      addTearDown(db.dispose);
      final adapter = _StatusAdapter()..status = 401;
      final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
      dio.httpClientAdapter = adapter;
      final outbox = SyncOutboxRepository(
        database: db,
        client: ApiClient(tokenStore: MemoryTokenStore(), dio: dio),
      );
      await outbox.enqueue('u1', batch('auth'));
      for (var i = 0; i < 20; i++) {
        await outbox.flush('u1');
      }
      expect(await outbox.pendingCount('u1'), 1);
      expect(_row(db, 'u1')['attempt_count'], 0);
      expect(_row(db, 'u1')['dead_lettered'], 0);
    },
  );

  test('429 backs off without dead-lettering', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final adapter = _StatusAdapter()..status = 429;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = adapter;
    final outbox = SyncOutboxRepository(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore(), dio: dio),
    );
    await outbox.enqueue('u1', batch('rate'));
    await outbox.flush('u1');
    expect(await outbox.pendingCount('u1'), 1);
    expect(_row(db, 'u1')['attempt_count'], 1);
    expect(_row(db, 'u1')['dead_lettered'], 0);
    expect(_row(db, 'u1')['next_attempt_at_utc'], isNotNull);
  });

  test('network error uses backoff', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final adapter = _StatusAdapter()..throwConnection = true;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = adapter;
    final outbox = SyncOutboxRepository(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore(), dio: dio),
    );
    await outbox.enqueue('u1', batch('net'));
    await outbox.flush('u1');
    expect(await outbox.pendingCount('u1'), 1);
    expect(_row(db, 'u1')['attempt_count'], 1);
    expect(_row(db, 'u1')['dead_lettered'], 0);
  });

  test('success marks sent once', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final adapter = _StatusAdapter()..status = 200;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = adapter;
    final outbox = SyncOutboxRepository(
      database: db,
      client: ApiClient(tokenStore: MemoryTokenStore(), dio: dio),
    );
    await outbox.enqueue('u1', batch('ok'));
    await outbox.flush('u1');
    await outbox.flush('u1');
    expect(await outbox.pendingCount('u1'), 0);
    expect(_row(db, 'u1')['sent_at_utc'], isNotNull);
    expect(adapter.posts, 1);
  });
}

Map<String, Object?> _row(HealthPalDatabase db, String userId) {
  return db.connection.select(
    'SELECT attempt_count, dead_lettered, sent_at_utc, next_attempt_at_utc FROM outbox_events WHERE user_id = ?',
    [userId],
  ).single;
}

class _StatusAdapter implements HttpClientAdapter {
  int status = 200;
  bool throwConnection = false;
  int posts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    posts += 1;
    if (throwConnection) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      status >= 400 ? '{"error":"no"}' : '{}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
