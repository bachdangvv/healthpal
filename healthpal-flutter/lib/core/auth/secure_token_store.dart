import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredTokens {
  const StoredTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAtUtc,
    required this.refreshExpiresAtUtc,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAtUtc;
  final DateTime refreshExpiresAtUtc;
}

abstract interface class TokenStore {
  Future<StoredTokens?> read();
  Future<void> write(StoredTokens tokens);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _access = 'healthpal.accessToken';
  static const _refresh = 'healthpal.refreshToken';
  static const _accessExp = 'healthpal.accessExpiresAtUtc';
  static const _refreshExp = 'healthpal.refreshExpiresAtUtc';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredTokens?> read() async {
    final access = await _storage.read(key: _access);
    final refresh = await _storage.read(key: _refresh);
    final accessExp = await _storage.read(key: _accessExp);
    final refreshExp = await _storage.read(key: _refreshExp);
    if (access == null ||
        refresh == null ||
        accessExp == null ||
        refreshExp == null) {
      return null;
    }
    return StoredTokens(
      accessToken: access,
      refreshToken: refresh,
      accessExpiresAtUtc: DateTime.parse(accessExp),
      refreshExpiresAtUtc: DateTime.parse(refreshExp),
    );
  }

  @override
  Future<void> write(StoredTokens tokens) async {
    await _storage.write(key: _access, value: tokens.accessToken);
    await _storage.write(key: _refresh, value: tokens.refreshToken);
    await _storage.write(
      key: _accessExp,
      value: tokens.accessExpiresAtUtc.toUtc().toIso8601String(),
    );
    await _storage.write(
      key: _refreshExp,
      value: tokens.refreshExpiresAtUtc.toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
    await _storage.delete(key: _accessExp);
    await _storage.delete(key: _refreshExp);
  }
}

class MemoryTokenStore implements TokenStore {
  StoredTokens? _tokens;

  @override
  Future<StoredTokens?> read() async => _tokens;

  @override
  Future<void> write(StoredTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
