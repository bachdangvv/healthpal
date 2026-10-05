import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/api/api_client.dart';
import 'package:healthpal/core/auth/cached_user_store.dart';
import 'package:healthpal/core/auth/secure_token_store.dart';
import 'package:healthpal/features/auth/application/auth_controller.dart';
import 'package:healthpal/features/auth/data/api_auth_repository.dart';
import 'package:healthpal/features/auth/data/auth_repository.dart';

void main() {
  test('restore network errors stay retryable and keep tokens', () async {
    final tokens = MemoryTokenStore();
    await tokens.write(
      StoredTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        accessExpiresAtUtc: DateTime.utc(2026, 9, 30),
        refreshExpiresAtUtc: DateTime.utc(2026, 10, 30),
      ),
    );
    final users = MemoryCachedUserStore();
    final adapter = _MeAdapter()..error = DioExceptionType.connectionTimeout;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = adapter;
    final repository = ApiAuthRepository(
      client: ApiClient(tokenStore: tokens, dio: dio),
      tokenStore: tokens,
      userStore: users,
    );
    final controller = AuthController(repository: repository);
    addTearDown(controller.dispose);

    await controller.restoreSession();
    expect(controller.user, isNull);
    expect(controller.error?.code, AuthFailure.network);
    expect((await tokens.read())?.accessToken, 'access');
  });
}

class _MeAdapter implements HttpClientAdapter {
  DioExceptionType error = DioExceptionType.connectionTimeout;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, type: error);
  }

  @override
  void close({bool force = false}) {}
}
