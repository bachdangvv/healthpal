import 'package:healthpal/core/api/api_client.dart';
import 'package:healthpal/core/auth/installation_store.dart';
import 'package:healthpal/core/database/device_settings_store.dart';
import 'package:healthpal/core/database/healthpal_database.dart';
import 'package:healthpal/core/database/local_health_store.dart';
import 'package:healthpal/core/sync/health_sync_coordinator.dart';
import 'package:healthpal/core/sync/health_sync_scheduler.dart';
import 'package:healthpal/core/sync/outbox_repository.dart';
import 'package:healthpal/core/time/app_clock.dart';
import 'package:healthpal/features/assessment/application/fatigue_assessment_runner.dart';
import 'package:healthpal/features/assessment/application/fatigue_engine.dart';
import 'package:healthpal/features/assessment/domain/fatigue_assessment.dart';
import 'package:healthpal/features/auth/domain/auth_user.dart';
import 'package:healthpal/features/dashboard/data/local_dashboard_repository.dart';
import 'package:healthpal/features/health_connect/data/health_connect_adapter.dart';
import 'package:healthpal/features/health_connect/data/health_connect_gateway.dart';
import 'package:healthpal/features/health_connect/data/plugin_health_connect_adapter.dart';
import 'package:healthpal/features/history/data/local_health_history_repository.dart';

class UserHealthRuntime {
  UserHealthRuntime({
    required this.userId,
    required this.store,
    required this.history,
    required this.dashboard,
    required this.coordinator,
    required this.gateway,
    required this.settings,
    required this.outbox,
  });

  final String userId;
  final LocalHealthStore store;
  final LocalHealthHistoryRepository history;
  final LocalDashboardRepository dashboard;
  final HealthSyncCoordinator coordinator;
  final HealthConnectGateway gateway;
  final DeviceSettingsStore settings;
  final SyncOutboxRepository outbox;

  Future<void> dispose() => coordinator.dispose();
}

class UserHealthRuntimeFactory {
  UserHealthRuntimeFactory({
    required this.database,
    required this.client,
    required this.installation,
    HealthConnectAdapter? adapter,
    this.engine,
    this.scheduler = const HealthSyncScheduler(),
    this.canFlush,
    this.clock = const SystemAppClock(),
  }) : adapter = adapter ?? PluginHealthConnectAdapter();

  final HealthPalDatabase database;
  final ApiClient client;
  final InstallationStore installation;
  final HealthConnectAdapter adapter;
  final FatigueEngine? engine;
  final HealthSyncScheduler scheduler;
  final Future<bool> Function(DeviceSyncSettings settings)? canFlush;
  final AppClock clock;

  UserHealthRuntime create(
    AuthUser user, {
    AssessmentCreatedBy createdBy = AssessmentCreatedBy.foreground,
  }) {
    final store = LocalHealthStore(database);
    final settings = DeviceSettingsStore(database);
    final outbox = SyncOutboxRepository(database: database, client: client);
    final gateway = HealthConnectGateway(adapter: adapter);
    final coordinator = HealthSyncCoordinator(
      userId: user.id,
      gateway: gateway,
      store: store,
      outbox: outbox,
      runner: FatigueAssessmentRunner(engine: engine),
      settings: settings,
      installation: installation,
      scheduler: scheduler,
      createdBy: createdBy,
      canFlush: canFlush,
      clock: clock,
    );
    return UserHealthRuntime(
      userId: user.id,
      store: store,
      history: LocalHealthHistoryRepository(
        database: database,
        userId: user.id,
        clock: clock,
      ),
      dashboard: LocalDashboardRepository(
        userId: user.id,
        store: store,
        coordinator: coordinator,
        gateway: gateway,
        outbox: outbox,
        settings: settings,
        clock: clock,
      ),
      coordinator: coordinator,
      gateway: gateway,
      settings: settings,
      outbox: outbox,
    );
  }
}
