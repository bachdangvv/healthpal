import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/assessment/application/fatigue_assessment_runner.dart';
import '../../features/assessment/domain/fatigue_assessment.dart';
import '../../features/health_connect/data/health_connect_gateway.dart';
import '../../features/health_connect/data/plugin_health_connect_adapter.dart';
import '../../src/rust/api.dart';
import '../api/api_client.dart';
import '../auth/cached_user_store.dart';
import '../auth/installation_store.dart';
import '../auth/secure_token_store.dart';
import '../config/app_config.dart';
import '../database/device_settings_store.dart';
import '../database/healthpal_database.dart';
import '../database/local_health_store.dart';
import 'health_sync_coordinator.dart';
import 'health_sync_scheduler.dart';
import 'outbox_repository.dart';

export 'health_sync_scheduler.dart';

@pragma('vm:entry-point')
void healthSyncBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    HealthPalDatabase? database;
    final tokenStore = SecureTokenStore();
    final gateway = HealthConnectGateway(adapter: PluginHealthConnectAdapter());
    Future<HealthPalDatabase> openDb() async =>
        database ??= await HealthPalDatabase.appFile();
    return HealthSyncJob.run(
      task: task,
      inputData: inputData,
      readUser: () async {
        final tokens = await tokenStore.read();
        if (tokens == null) return null;
        return SecureCachedUserStore().read();
      },
      readSettings: (userId) async {
        return DeviceSettingsStore(await openDb()).read(userId);
      },
      capabilities: gateway.getCapabilities,
      recordSkip: (userId, reason) async {
        await LocalHealthStore(
          await openDb(),
        ).recordSyncDiagnostic(userId, reason);
      },
      sync: (userId) async {
        try {
          await initHealthpalRust();
        } catch (_) {
          // Assessment stays insufficient until the native runtime is available.
        }
        final db = await openDb();
        final client = ApiClient(
          tokenStore: tokenStore,
          baseUrl: AppConfig.apiBaseUrl,
        );
        final coordinator = HealthSyncCoordinator(
          userId: userId,
          gateway: gateway,
          store: LocalHealthStore(db),
          outbox: SyncOutboxRepository(database: db, client: client),
          runner: FatigueAssessmentRunner(),
          settings: DeviceSettingsStore(db),
          installation: SecureInstallationStore(),
          scheduler: const HealthSyncScheduler(),
          createdBy: AssessmentCreatedBy.background,
        );
        return coordinator.syncNow();
      },
    );
  });
}
