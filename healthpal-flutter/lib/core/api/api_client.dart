import 'package:dio/dio.dart';

import '../auth/secure_token_store.dart';
import '../config/app_config.dart';
import 'dto/api_dtos.dart';

class ApiClient {
  ApiClient({required TokenStore tokenStore, Dio? dio, String? baseUrl})
    : _tokenStore = tokenStore,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ) {
    _refreshDio = Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
      ),
    );
    _refreshDio.httpClientAdapter = _dio.httpClientAdapter;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra[skipAuthHeaderExtra] == true) {
            handler.next(options);
            return;
          }
          final tokens = await _tokenStore.read();
          if (tokens != null) {
            options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          final retried = error.requestOptions.extra[retriedExtra] == true;
          final skip = error.requestOptions.extra[skipRefreshExtra] == true;
          if (status != 401 || retried || skip) {
            handler.next(error);
            return;
          }
          try {
            await refreshTokens();
            final tokens = await _tokenStore.read();
            if (tokens == null) {
              handler.next(error);
              return;
            }
            final options = error.requestOptions;
            options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
            options.extra[retriedExtra] = true;
            final retry = await _dio.fetch<dynamic>(options);
            handler.resolve(retry);
          } catch (_) {
            handler.next(error);
          }
        },
      ),
    );
  }

  static const retriedExtra = 'healthpalRetried';
  static const skipRefreshExtra = 'healthpalSkipRefresh';
  static const skipAuthHeaderExtra = 'healthpalSkipAuthHeader';

  final Dio _dio;
  final TokenStore _tokenStore;
  late final Dio _refreshDio;
  Future<void>? _refreshInFlight;

  Dio get raw => _dio;

  Future<void> refreshTokens() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _refreshOnce();
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
  }

  Future<void> _refreshOnce() async {
    final tokens = await _tokenStore.read();
    if (tokens == null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/v1/auth/refresh'),
        type: DioExceptionType.badResponse,
      );
    }
    try {
      final refreshed = await _refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': tokens.refreshToken},
      );
      final pair = TokenPairDto.fromJson(refreshed.data!);
      await _tokenStore.write(
        StoredTokens(
          accessToken: pair.accessToken,
          refreshToken: pair.refreshToken,
          accessExpiresAtUtc: pair.accessExpiresAtUtc,
          refreshExpiresAtUtc: pair.refreshExpiresAtUtc,
        ),
      );
    } on DioException catch (error) {
      if (_isDefinitiveRefreshRejection(error)) {
        await _tokenStore.clear();
      }
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  bool _isDefinitiveRefreshRejection(DioException error) {
    final status = error.response?.statusCode;
    if (status == null) return false;
    return status == 400 || status == 401 || status == 403;
  }
}
