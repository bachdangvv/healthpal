import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/auth/application/auth_controller.dart';
import 'package:healthpal/features/auth/data/demo_auth_repository.dart';
import 'package:healthpal/features/auth/domain/auth_user.dart';
import 'package:healthpal/features/dashboard/data/health_connect_repository.dart';
import 'package:healthpal/features/dashboard/domain/dashboard_models.dart';
import 'package:healthpal/features/profile/data/demo_profile_repository.dart';
import 'package:healthpal/features/profile/presentation/profile_settings_screen.dart';

class _FakeHealthConnect implements HealthConnectRepository {
  _FakeHealthConnect(this.snapshot, {this.grantOnBackgroundRequest = false});

  HealthConnectSnapshot snapshot;
  bool grantOnBackgroundRequest;
  int fetchCount = 0;
  int backgroundRequests = 0;
  int foregroundRequests = 0;
  int syncRequests = 0;
  bool? lastSyncUserInitiated;

  @override
  Future<HealthConnectSnapshot> fetchSnapshot() async {
    fetchCount += 1;
    return snapshot;
  }

  @override
  Future<HealthConnectSnapshot> requestReadPermissions() async {
    foregroundRequests += 1;
    return snapshot;
  }

  @override
  Future<HealthConnectSnapshot> requestBackgroundRead() async {
    backgroundRequests += 1;
    if (grantOnBackgroundRequest) {
      snapshot = HealthConnectSnapshot(
        availability: snapshot.availability,
        access: snapshot.access,
        missingPermissions: snapshot.missingPermissions,
        backgroundReadSupported: true,
        backgroundReadGranted: true,
        lastSyncedAt: snapshot.lastSyncedAt,
        summary: snapshot.summary,
      );
    }
    return snapshot;
  }

  @override
  Future<void> openHealthConnectSettings() async {}

  @override
  Future<HealthConnectSnapshot> syncFromHealthConnect({
    bool userInitiated = false,
  }) async {
    syncRequests += 1;
    lastSyncUserInitiated = userInitiated;
    return snapshot;
  }
}

Finder keyed(String value) => find.byKey(ValueKey<String>(value));

void main() {
  const user = AuthUser(
    id: 'u1',
    name: 'Minh Anh',
    email: 'demo@healthpal.app',
  );

  Future<AuthController> pumpProfile(
    WidgetTester tester,
    _FakeHealthConnect health, {
    void Function()? onSync,
    void Function()? onProfile,
  }) async {
    final auth = AuthController(
      repository: DemoAuthRepository(latency: Duration.zero),
    );
    addTearDown(auth.dispose);
    final profiles = DemoProfileRepository();
    profiles.ensure(user);
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSettingsScreen(
          authController: auth,
          repository: profiles,
          user: user,
          healthConnect: health,
          onSyncSettingsChanged: () async => onSync?.call(),
          onProfileChanged: () async => onProfile?.call(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(keyed('profile-screen'), const Offset(0, -720));
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('startup does not request background read', (tester) async {
    final health = _FakeHealthConnect(
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: [],
        backgroundReadSupported: true,
      ),
    );
    await pumpProfile(tester, health);
    expect(health.backgroundRequests, 0);
  });

  testWidgets('authorized profile shows user-initiated health sync button', (
    tester,
  ) async {
    final health = _FakeHealthConnect(
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: [],
        backgroundReadSupported: true,
      ),
    );
    await pumpProfile(tester, health);
    expect(keyed('profile-sync-health-now'), findsOneWidget);
    await tester.tap(keyed('profile-sync-health-now'));
    await tester.pumpAndSettle();
    expect(health.syncRequests, 1);
    expect(health.lastSyncUserInitiated, isTrue);
  });

  testWidgets(
    'enabling Auto Sync requests background read once when supported',
    (tester) async {
      final health = _FakeHealthConnect(
        const HealthConnectSnapshot(
          availability: HealthConnectAvailability.available,
          access: HealthConnectAccess.granted,
          missingPermissions: [],
          backgroundReadSupported: true,
        ),
      );
      var reconciles = 0;
      await pumpProfile(tester, health, onSync: () => reconciles += 1);
      await tester.tap(keyed('profile-sync-health'));
      await tester.pumpAndSettle();
      expect(health.foregroundRequests, 1);
      expect(health.backgroundRequests, 1);
      expect(reconciles, greaterThan(0));
    },
  );

  testWidgets('granting background read is reflected as connected status', (
    tester,
  ) async {
    final health = _FakeHealthConnect(
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: [],
        backgroundReadSupported: true,
      ),
      grantOnBackgroundRequest: true,
    );
    await pumpProfile(tester, health);
    await tester.tap(keyed('profile-sync-health'));
    await tester.pumpAndSettle();
    expect(health.backgroundRequests, 1);
    expect(health.snapshot.backgroundReadGranted, isTrue);
  });

  testWidgets('denying background read stays foreground-only', (tester) async {
    final health = _FakeHealthConnect(
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: [],
        backgroundReadSupported: true,
        backgroundReadGranted: false,
      ),
    );
    await pumpProfile(tester, health);
    await tester.tap(keyed('profile-sync-health'));
    await tester.pumpAndSettle();
    expect(health.backgroundRequests, 1);
    expect(find.textContaining('chỉ đồng bộ khi mở ứng dụng'), findsWidgets);
  });

  testWidgets('unsupported background read never calls the request API', (
    tester,
  ) async {
    final health = _FakeHealthConnect(
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: [],
      ),
    );
    await pumpProfile(tester, health);
    await tester.tap(keyed('profile-sync-health'));
    await tester.pumpAndSettle();
    expect(health.backgroundRequests, 0);
    expect(health.foregroundRequests, 1);
    expect(find.textContaining('không hỗ trợ đọc dữ liệu nền'), findsOneWidget);
  });

  testWidgets('Wi-Fi-only toggle calls the scheduler callback once', (
    tester,
  ) async {
    final health = _FakeHealthConnect(
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: [],
        backgroundReadSupported: true,
      ),
    );
    var reconciles = 0;
    var profiles = 0;
    await pumpProfile(
      tester,
      health,
      onSync: () => reconciles += 1,
      onProfile: () => profiles += 1,
    );
    await tester.tap(keyed('profile-sync-wifi'));
    await tester.pumpAndSettle();
    expect(reconciles, 1);
    expect(profiles, 0);
  });

  testWidgets('consent toggle does not call the scheduler callback', (
    tester,
  ) async {
    final health = _FakeHealthConnect(
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: [],
        backgroundReadSupported: true,
      ),
    );
    var reconciles = 0;
    var profiles = 0;
    await pumpProfile(
      tester,
      health,
      onSync: () => reconciles += 1,
      onProfile: () => profiles += 1,
    );
    await tester.tap(keyed('profile-fatigue-consent'));
    await tester.pumpAndSettle();
    expect(reconciles, 0);
    expect(profiles, 1);
  });

  testWidgets('app resume refreshes without opening a permission dialog', (
    tester,
  ) async {
    final health = _FakeHealthConnect(
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: [],
        backgroundReadSupported: true,
      ),
    );
    await pumpProfile(tester, health);
    final fetchesAfterLoad = health.fetchCount;
    final observer =
        tester.state<State<ProfileSettingsScreen>>(
              find.byType(ProfileSettingsScreen),
            )
            as WidgetsBindingObserver;
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(health.backgroundRequests, 0);
    expect(health.fetchCount, greaterThan(fetchesAfterLoad));
  });
}
