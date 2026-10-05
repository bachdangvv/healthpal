import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/dto/api_dtos.dart';
import '../../../core/auth/cached_user_store.dart';
import '../../../core/auth/secure_token_store.dart';
import '../domain/auth_user.dart';
import 'auth_repository.dart';

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({
    required ApiClient client,
    required TokenStore tokenStore,
    CachedUserStore? userStore,
  }) : _client = client,
       _tokenStore = tokenStore,
       _userStore = userStore ?? SecureCachedUserStore();

  final ApiClient _client;
  final TokenStore _tokenStore;
  final CachedUserStore _userStore;

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.raw.post<Map<String, dynamic>>(
        '/api/v1/auth/login',
        data: {'email': email.trim(), 'password': password},
      );
      return _storeSession(response.data!);
    } on DioException catch (error) {
      throw _map(error, AuthFailure.invalidCredentials);
    }
  }

  @override
  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.raw.post<Map<String, dynamic>>(
        '/api/v1/auth/register',
        data: {
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
        },
      );
      return _storeSession(response.data!);
    } on DioException catch (error) {
      throw _map(error, AuthFailure.emailAlreadyInUse);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.raw.post<void>('/api/v1/auth/logout');
    } catch (_) {
      // Local tokens are always cleared.
    } finally {
      await _tokenStore.clear();
      await _userStore.clear();
    }
  }

  @override
  Future<AuthUser?> restoreSession() async {
    final tokens = await _tokenStore.read();
    if (tokens == null) {
      await _userStore.clear();
      return null;
    }
    try {
      final response = await _client.raw.get<Map<String, dynamic>>(
        '/api/v1/auth/me',
      );
      final user = AuthUserDto.fromJson(response.data!);
      final restored = AuthUser(
        id: user.id,
        name: user.name,
        email: user.email,
      );
      await _userStore.write(restored);
      return restored;
    } on DioException catch (error) {
      if (_isRetryable(error)) {
        throw const AuthException(AuthFailure.network);
      }
      final remaining = await _tokenStore.read();
      if (remaining != null && error.response?.statusCode == 401) {
        throw const AuthException(AuthFailure.network);
      }
      await _tokenStore.clear();
      await _userStore.clear();
      return null;
    }
  }

  Future<AuthUser> _storeSession(Map<String, dynamic> json) async {
    final session = AuthSessionDto.fromJson(json);
    await _tokenStore.write(
      StoredTokens(
        accessToken: session.tokens.accessToken,
        refreshToken: session.tokens.refreshToken,
        accessExpiresAtUtc: session.tokens.accessExpiresAtUtc,
        refreshExpiresAtUtc: session.tokens.refreshExpiresAtUtc,
      ),
    );
    final user = AuthUser(
      id: session.user.id,
      name: session.user.name,
      email: session.user.email,
    );
    await _userStore.write(user);
    return user;
  }

  AuthException _map(DioException error, AuthFailure fallback) {
    if (_isRetryable(error)) {
      return const AuthException(AuthFailure.network);
    }
    return AuthException(fallback);
  }

  bool _isRetryable(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.cancel) {
      return true;
    }
    final status = error.response?.statusCode;
    if (status == null) {
      return error.type != DioExceptionType.badResponse;
    }
    return status == 408 || status == 429 || status >= 500;
  }
}
