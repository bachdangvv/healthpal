import 'package:connectivity_plus/connectivity_plus.dart';

import '../../features/assessment/application/fatigue_assessment_runner.dart';
import '../../features/assessment/domain/fatigue_assessment.dart';
import '../../features/health_connect/application/sync_orchestrator.dart';
import '../../features/health_connect/application/sync_window.dart';
import '../../features/health_connect/data/health_connect_gateway.dart';
import '../../features/health_connect/domain/health_records.dart';
import '../auth/installation_store.dart';
import '../database/device_settings_store.dart';
import '../database/local_health_store.dart';
import '../time/app_clock.dart';
import 'health_sync_scheduler.dart';
import 'outbox_repository.dart';
import 'sync_batch_factory.dart';
import 'sync_state.dart';

class HealthSyncCoordinator {
  HealthSyncCoordinator({
    required this.userId,
    required this.gateway,
    required this.store,
    required this.outbox,
    required this.runner,
    required this.settings,
    required this.installation,
    required this.scheduler,
    this.batchFactory = const SyncBatchFactory(),
    this.createdBy = AssessmentCreatedBy.foreground,
    this.clock = const SystemAppClock(),
    Future<bool> Function(DeviceSyncSettings settings)? canFlush,
  }) : orchestrator = SyncOrchestrator(gateway: gateway),
       canFlush = canFlush ?? defaultCanFlush;

  final String userId;
  final HealthConnectGateway gateway;
  final LocalHealthStore store;
  final SyncOutboxRepository outbox;
  final FatigueAssessmentRunner runner;
  final DeviceSettingsStore settings;
  final InstallationStore installation;
  final HealthSyncScheduler scheduler;
  final SyncBatchFactory batchFactory;
  final AssessmentCreatedBy createdBy;
  final AppClock clock;
  final SyncOrchestrator orchestrator;
  final Future<bool> Function(DeviceSyncSettings settings) canFlush;

  static Future<bool> defaultCanFlush(DeviceSyncSettings settings) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final online = connectivity.any(
        (item) =>
            item == ConnectivityResult.wifi ||
            item == ConnectivityResult.ethernet ||
            item == ConnectivityResult.mobile ||
            item == ConnectivityResult.vpn,
      );
      if (!online) return false;
      if (settings.wifiOnly) {
        return connectivity.contains(ConnectivityResult.wifi);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<SyncState> syncNow({bool fullResync = false}) async {
    final localSettings = await settings.read(userId);
    if (!localSettings.healthConnectSync) {
      return const SyncState(lastError: 'sync_disabled');
    }
    final previous = await store.readSyncState(userId);
    PermissionSnapshot? permissions;
    FatigueAssessment? assessment;
    final now = clock.now();
    final syncCutoffUtc = now.toUtc();
    final timezoneOffsetMinutes = now.timeZoneOffset.inMinutes;
    final firstSync = fullResync || previous.sourceWatermarkUtc == null;
    final window = SyncReplacementWindow.forSync(
      cutoffUtc: syncCutoffUtc,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      previousWatermarkUtc: previous.sourceWatermarkUtc,
      firstSync: firstSync,
    );
    final state = await orchestrator.syncNow(
      nowUtc: syncCutoffUtc,
      previousWatermarkUtc: previous.sourceWatermarkUtc,
      preferredSourceId: previous.preferredSourceId,
      firstSync: firstSync,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      replacementWindow: window,
      onPermissions: (snapshot) => permissions = snapshot,
      onPersist:
          ({
            required canonical,
            required bins,
            required days,
            required state,
            required window,
          }) async {
            final deviceId = await installation.deviceId();
            final previousAssessment = await store.latestAssessment(userId);
            await store.transaction(() async {
              await store.replaceCanonicalWindow(
                userId: userId,
                window: window,
                canonical: canonical,
                bins: bins,
                days: days,
                state: state,
                transactional: false,
              );
              assessment = await runner.run(
                canonical: canonical,
                evaluationTimeUtc: syncCutoffUtc,
                permissions:
                    permissions ??
                    const PermissionSnapshot(granted: {}, missing: {}),
                createdBy: createdBy,
                dataWatermarkUtc: state.sourceWatermarkUtc,
                previousAssessmentWatermarkUtc:
                    previousAssessment?.latestSampleAtUtc,
              );
              await store.saveAssessment(userId, assessment!);
              final batch = batchFactory.build(
                deviceId: deviceId,
                bins: bins,
                days: days,
                exercises: canonical.batch.exerciseSessions,
                assessments: [if (assessment != null) assessment!],
                generatedAtUtc: syncCutoffUtc,
                replacementWindow: window,
              );
              await outbox.enqueue(userId, batch);
            });
            if (await canFlush(localSettings)) {
              try {
                await outbox.flush(userId);
              } catch (_) {
                // Local persist succeeded; upload stays pending.
              }
            }
          },
    );
    return state;
  }

  Future<void> reconcileScheduler() async {
    final localSettings = await settings.read(userId);
    final caps = await gateway.getCapabilities();
    await scheduler.reconcile(
      userId: userId,
      healthConnectSync: localSettings.healthConnectSync,
      autoSync: localSettings.autoSync,
      wifiOnly: localSettings.wifiOnly,
      backgroundAvailable: caps.backgroundReadSupported,
      backgroundGranted: caps.backgroundReadGranted,
    );
  }

  Future<void> dispose() => scheduler.cancel(userId);
}
