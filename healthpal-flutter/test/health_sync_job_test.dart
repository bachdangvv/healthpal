import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/database/device_settings_store.dart';
import 'package:healthpal/core/sync/health_sync_scheduler.dart';
import 'package:healthpal/core/sync/sync_state.dart';
import 'package:healthpal/features/auth/domain/auth_user.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';

void main() {
  const user = AuthUser(id: 'u1', name: 'A', email: 'a@example.com');

  test('worker without a user does not ingest', () async {
    var synced = false;
    final ok = await HealthSyncJob.run(
      task: HealthSyncScheduler.uniqueNameFor('u1'),
      readUser: () async => null,
      readSettings: (_) async =>
          const DeviceSyncSettings(healthConnectSync: true),
      capabilities: () async => const HealthConnectCapabilities(
        sdkAvailable: true,
        backgroundReadSupported: true,
        backgroundReadGranted: true,
      ),
      sync: (_) async {
        synced = true;
        return const SyncState();
      },
    );
    expect(ok, isTrue);
    expect(synced, isFalse);
  });

  test('worker skip records a diagnostic without ingesting', () async {
    String? reason;
    final ok = await HealthSyncJob.run(
      task: HealthSyncScheduler.uniqueNameFor(user.id),
      inputData: {'userId': user.id},
      readUser: () async => user,
      readSettings: (_) async =>
          const DeviceSyncSettings(healthConnectSync: true, autoSync: true),
      capabilities: () async => const HealthConnectCapabilities(
        sdkAvailable: true,
        backgroundReadSupported: false,
        backgroundReadGranted: false,
      ),
      sync: (_) async => const SyncState(),
      recordSkip: (userId, skipReason) async => reason = skipReason,
    );
    expect(ok, isTrue);
    expect(reason, HealthSyncJob.skippedNoBackground);
  });

  test('worker without background permission does not ingest', () async {
    var synced = false;
    final ok = await HealthSyncJob.run(
      task: HealthSyncScheduler.uniqueNameFor(user.id),
      inputData: {'userId': user.id},
      readUser: () async => user,
      readSettings: (_) async =>
          const DeviceSyncSettings(healthConnectSync: true, autoSync: true),
      capabilities: () async => const HealthConnectCapabilities(
        sdkAvailable: true,
        backgroundReadSupported: false,
        backgroundReadGranted: false,
      ),
      sync: (_) async {
        synced = true;
        return const SyncState();
      },
    );
    expect(ok, isTrue);
    expect(synced, isFalse);
  });

  test('worker success requires a completed local transaction', () async {
    final ok = await HealthSyncJob.run(
      task: HealthSyncScheduler.uniqueNameFor(user.id),
      inputData: {'userId': user.id},
      readUser: () async => user,
      readSettings: (_) async =>
          const DeviceSyncSettings(healthConnectSync: true, autoSync: true),
      capabilities: () async => const HealthConnectCapabilities(
        sdkAvailable: true,
        backgroundReadSupported: true,
        backgroundReadGranted: true,
      ),
      sync: (_) async =>
          SyncState(lastSuccessfulSyncAtUtc: DateTime.utc(2026, 9, 30)),
    );
    expect(ok, isTrue);
  });

  test('transient model failure is returned as retry', () async {
    final ok = await HealthSyncJob.run(
      task: HealthSyncScheduler.uniqueNameFor(user.id),
      inputData: {'userId': user.id},
      readUser: () async => user,
      readSettings: (_) async =>
          const DeviceSyncSettings(healthConnectSync: true, autoSync: true),
      capabilities: () async => const HealthConnectCapabilities(
        sdkAvailable: true,
        backgroundReadSupported: true,
        backgroundReadGranted: true,
      ),
      sync: (_) async => throw StateError('model'),
    );
    expect(ok, isFalse);
  });
}
