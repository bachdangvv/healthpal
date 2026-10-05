import 'package:workmanager/workmanager.dart';

import '../../features/auth/domain/auth_user.dart';
import '../../features/health_connect/domain/health_records.dart';
import '../database/device_settings_store.dart';
import 'sync_state.dart';

const healthSyncUniqueName = 'healthpal-health-sync';

class HealthSyncScheduler {
  const HealthSyncScheduler();

  static String uniqueNameFor(String userId) => '$healthSyncUniqueName-$userId';

  Future<void> reconcile({
    required String userId,
    required bool healthConnectSync,
    required bool autoSync,
    required bool wifiOnly,
    required bool backgroundAvailable,
    required bool backgroundGranted,
  }) async {
    final name = uniqueNameFor(userId);
    final shouldRun =
        userId.isNotEmpty &&
        healthConnectSync &&
        autoSync &&
        backgroundAvailable &&
        backgroundGranted;
    await Workmanager().cancelByUniqueName(healthSyncUniqueName);
    if (!shouldRun) {
      await Workmanager().cancelByUniqueName(name);
      return;
    }
    await Workmanager().registerPeriodicTask(
      name,
      name,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      inputData: {'userId': userId},
      constraints: Constraints(
        networkType: wifiOnly ? NetworkType.unmetered : NetworkType.notRequired,
        requiresBatteryNotLow: true,
      ),
    );
  }

  Future<void> cancel(String userId) async {
    await Workmanager().cancelByUniqueName(uniqueNameFor(userId));
    await Workmanager().cancelByUniqueName(healthSyncUniqueName);
  }
}

class HealthSyncJob {
  const HealthSyncJob();

  static const skippedNoUser = 'no_user';
  static const skippedTaskMismatch = 'task_mismatch';
  static const skippedSyncDisabled = 'sync_disabled';
  static const skippedNoBackground = 'background_unavailable';
  static const skippedMissingPermissions = 'missing_permissions';

  /// Shared skip/success policy for the WorkManager isolate and unit tests.
  static Future<bool> run({
    required String task,
    Map<String, dynamic>? inputData,
    required Future<AuthUser?> Function() readUser,
    required Future<DeviceSyncSettings> Function(String userId) readSettings,
    required Future<HealthConnectCapabilities> Function() capabilities,
    required Future<SyncState> Function(String userId) sync,
    Future<void> Function(String userId, String reason)? recordSkip,
  }) async {
    Future<bool> skip(String? userId, String reason) async {
      if (userId != null && userId.isNotEmpty) {
        await recordSkip?.call(userId, reason);
      }
      return true;
    }

    final claimedUserId = inputData?['userId'] as String?;
    final user = await readUser();
    if (user == null) return skip(claimedUserId, skippedNoUser);
    final expected = HealthSyncScheduler.uniqueNameFor(user.id);
    if (task != expected && task != healthSyncUniqueName) {
      return skip(user.id, skippedTaskMismatch);
    }
    if (claimedUserId != null && claimedUserId != user.id) {
      return skip(user.id, skippedTaskMismatch);
    }
    final settings = await readSettings(user.id);
    if (!settings.healthConnectSync || !settings.autoSync) {
      return skip(user.id, skippedSyncDisabled);
    }
    final caps = await capabilities();
    if (!caps.backgroundReadSupported || !caps.backgroundReadGranted) {
      return skip(user.id, skippedNoBackground);
    }
    try {
      final state = await sync(user.id);
      if (state.lastSuccessfulSyncAtUtc != null) return true;
      final error = state.lastError;
      if (error == null ||
          error == skippedSyncDisabled ||
          error == skippedMissingPermissions ||
          error.contains('permission')) {
        if (error != null) await recordSkip?.call(user.id, error);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
