import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

abstract interface class InstallationStore {
  Future<String> deviceId();
}

class SecureInstallationStore implements InstallationStore {
  SecureInstallationStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'healthpal.deviceId';
  static const _uuid = Uuid();
  final FlutterSecureStorage _storage;
  String? _cached;

  @override
  Future<String> deviceId() async {
    if (_cached != null) return _cached!;
    var value = await _storage.read(key: _key);
    if (value == null || value.isEmpty) {
      value = _uuid.v4();
      await _storage.write(key: _key, value: value);
    }
    _cached = value;
    return value;
  }
}

class MemoryInstallationStore implements InstallationStore {
  MemoryInstallationStore([this._id = 'test-device']);

  final String _id;

  @override
  Future<String> deviceId() async => _id;
}
