import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/auth_user.dart';

abstract interface class CachedUserStore {
  Future<AuthUser?> read();
  Future<void> write(AuthUser user);
  Future<void> clear();
}

class SecureCachedUserStore implements CachedUserStore {
  SecureCachedUserStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _id = 'healthpal.user.id';
  static const _name = 'healthpal.user.name';
  static const _email = 'healthpal.user.email';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthUser?> read() async {
    final id = await _storage.read(key: _id);
    final name = await _storage.read(key: _name);
    final email = await _storage.read(key: _email);
    if (id == null || name == null || email == null) return null;
    return AuthUser(id: id, name: name, email: email);
  }

  @override
  Future<void> write(AuthUser user) async {
    await _storage.write(key: _id, value: user.id);
    await _storage.write(key: _name, value: user.name);
    await _storage.write(key: _email, value: user.email);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _id);
    await _storage.delete(key: _name);
    await _storage.delete(key: _email);
  }
}

class MemoryCachedUserStore implements CachedUserStore {
  AuthUser? _user;

  @override
  Future<AuthUser?> read() async => _user;

  @override
  Future<void> write(AuthUser user) async => _user = user;

  @override
  Future<void> clear() async => _user = null;
}
