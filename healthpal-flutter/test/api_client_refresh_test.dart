import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/api/api_client.dart';
import 'package:healthpal/core/auth/secure_token_store.dart';

void main() {
  Future<(ApiClient, MemoryTokenStore, _ScriptedAdapter)> clientWith({
    int? refreshStatus,
    DioExceptionType? refreshError,
  }) async {
    final store = MemoryTokenStore();
    await store.write(
      StoredTokens(
        accessToken: 'old',
        refreshToken: 'refresh-1',
        accessExpiresAtUtc: DateTime.utc(2026, 9, 30),
        refreshExpiresAtUtc: DateTime.utc(2026, 10, 30),
      ),
    );
    final adapter = _ScriptedAdapter(
      refreshStatus: refreshStatus,
      refreshError: refreshError,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = adapter;
    return (ApiClient(tokenStore: store, dio: dio), store, adapter);
  }

  test('refresh success rotates and stores the new token pair', () async {
    final (client, store, adapter) = await clientWith(refreshStatus: 200);
    await client.refreshTokens();
    expect((await store.read())?.accessToken, 'new');
    expect(adapter.refreshCalls, 1);
  });

  test('HTTP 401 refresh clears stored tokens', () async {
    final (client, store, _) = await clientWith(refreshStatus: 401);
    await expectLater(client.refreshTokens(), throwsA(isA<DioException>()));
    expect(await store.read(), isNull);
  });

  test('HTTP 400 invalid refresh clears stored tokens', () async {
    final (client, store, _) = await clientWith(refreshStatus: 400);
    await expectLater(client.refreshTokens(), throwsA(isA<DioException>()));
    expect(await store.read(), isNull);
  });

  test('HTTP 500 refresh keeps the previous tokens', () async {
    final (client, store, _) = await clientWith(refreshStatus: 500);
    await expectLater(client.refreshTokens(), throwsA(isA<DioException>()));
    expect((await store.read())?.accessToken, 'old');
  });

  test('connection timeout refresh keeps the previous tokens', () async {
    final (client, store, _) = await clientWith(
      refreshError: DioExceptionType.connectionTimeout,
    );
    await expectLater(client.refreshTokens(), throwsA(isA<DioException>()));
    expect((await store.read())?.accessToken, 'old');
  });

  test('HTTP 429 refresh keeps the previous tokens', () async {
    final (client, store, _) = await clientWith(refreshStatus: 429);
    await expectLater(client.refreshTokens(), throwsA(isA<DioException>()));
    expect((await store.read())?.accessToken, 'old');
  });

  test('concurrent 401s share a single refresh call', () async {
    final (client, store, adapter) = await clientWith(refreshStatus: 200);
    final results = await Future.wait([
      for (var i = 0; i < 10; i++)
        client.raw.get<Map<String, dynamic>>('/data'),
    ]);
    expect(results, hasLength(10));
    expect(adapter.refreshCalls, 1);
    expect(adapter.dataCalls, 20);
    expect((await store.read())?.accessToken, 'new');
  });
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({this.refreshStatus, this.refreshError});

  final int? refreshStatus;
  final DioExceptionType? refreshError;
  int refreshCalls = 0;
  int dataCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/auth/refresh')) {
      refreshCalls += 1;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (refreshError != null) {
        throw DioException(requestOptions: options, type: refreshError!);
      }
      final status = refreshStatus ?? 200;
      if (status == 200) {
        return ResponseBody.fromString(
          jsonEncode({
            'accessToken': 'new',
            'refreshToken': 'refresh-2',
            'accessExpiresAtUtc': '2026-10-01T00:00:00.000Z',
            'refreshExpiresAtUtc': '2026-11-01T00:00:00.000Z',
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        '{"error":"refresh"}',
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    dataCalls += 1;
    final token = options.headers['Authorization'] as String? ?? '';
    if (token.contains('old')) {
      return ResponseBody.fromString(
        '{"error":"expired"}',
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
