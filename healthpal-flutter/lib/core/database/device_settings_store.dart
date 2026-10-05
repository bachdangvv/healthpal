import 'healthpal_database.dart';

class DeviceSyncSettings {
  const DeviceSyncSettings({
    this.healthConnectSync = false,
    this.autoSync = true,
    this.wifiOnly = false,
  });

  final bool healthConnectSync;
  final bool autoSync;
  final bool wifiOnly;
}

class DeviceSettingsStore {
  DeviceSettingsStore(this._db);

  final HealthPalDatabase _db;

  Future<DeviceSyncSettings> read(String userId) async {
    final rows = _db.connection.select(
      'SELECT * FROM device_settings WHERE user_id = ?',
      [userId],
    );
    if (rows.isEmpty) return const DeviceSyncSettings();
    final row = rows.first;
    return DeviceSyncSettings(
      healthConnectSync: (row['health_connect_sync'] as int) == 1,
      autoSync: (row['auto_sync'] as int) == 1,
      wifiOnly: (row['wifi_only'] as int) == 1,
    );
  }

  Future<void> write(String userId, DeviceSyncSettings settings) async {
    _db.connection.execute(
      '''
INSERT INTO device_settings (user_id, health_connect_sync, auto_sync, wifi_only, updated_at_utc)
VALUES (?,?,?,?,?)
ON CONFLICT(user_id) DO UPDATE SET
  health_connect_sync=excluded.health_connect_sync,
  auto_sync=excluded.auto_sync,
  wifi_only=excluded.wifi_only,
  updated_at_utc=excluded.updated_at_utc
''',
      [
        userId,
        settings.healthConnectSync ? 1 : 0,
        settings.autoSync ? 1 : 0,
        settings.wifiOnly ? 1 : 0,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }
}
