import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/app.dart';
import 'package:healthpal/core/config/app_config.dart';
import 'package:healthpal/features/assessment/domain/fatigue_assessment.dart';
import 'package:healthpal/features/auth/data/demo_auth_repository.dart';
import 'package:healthpal/features/auth/domain/auth_user.dart';
import 'package:healthpal/features/dashboard/data/demo_health_connect_repository.dart';
import 'package:healthpal/features/dashboard/domain/dashboard_models.dart';
import 'package:healthpal/features/history/data/demo_health_history_repository.dart';
import 'package:healthpal/features/profile/application/profile_controller.dart';
import 'package:healthpal/features/profile/data/demo_profile_repository.dart';
import 'package:healthpal/features/profile/data/profile_repository.dart';
import 'package:healthpal/features/profile/domain/user_profile.dart';

Finder keyed(String value) => find.byKey(ValueKey<String>(value));

final _fatigueSnapshot = HealthConnectSnapshot(
  availability: HealthConnectAvailability.available,
  access: HealthConnectAccess.granted,
  missingPermissions: [],
  fatigue: FatigueAssessment(
    id: 'fx',
    evaluatedAtUtc: DateTime.utc(2026, 9, 30, 8),
    localDate: DateTime(2026, 9, 30),
    modelVersion: AppConfig.fatigueModelVersion,
    baseProbability: 0.4,
    calibratedProbability: 0.35,
    threshold: AppConfig.fatigueDecisionThreshold,
    status: FatigueAssessmentStatus.signalDetected,
    coverageHours: 6,
    featureVectorHash: 'hash',
    createdBy: AssessmentCreatedBy.foreground,
  ),
);

class _FailingConsentRepository extends DemoProfileRepository {
  @override
  Future<UserProfile> updateSettings({
    required String userId,
    HealthGoal? goal,
    int? dailyStepGoal,
    bool? healthConnectSync,
    bool? autoSync,
    bool? wifiOnly,
    bool? experimentalFatigueConsent,
  }) async {
    if (experimentalFatigueConsent != null) {
      throw const ProfileException(ProfileFailure.network);
    }
    return super.updateSettings(
      userId: userId,
      goal: goal,
      dailyStepGoal: dailyStepGoal,
      healthConnectSync: healthConnectSync,
      autoSync: autoSync,
      wifiOnly: wifiOnly,
      experimentalFatigueConsent: experimentalFatigueConsent,
    );
  }
}

class _ScriptedProfileRepository implements ProfileRepository {
  _ScriptedProfileRepository({this.fetchError});

  final Completer<UserProfile> pending = Completer<UserProfile>();
  final Object? fetchError;
  bool usePending = false;
  final Map<String, UserProfile> _profiles = {};

  @override
  void ensure(AuthUser user) {
    _profiles.putIfAbsent(
      user.id,
      () => UserProfile(
        user: user,
        rowVersion: 'v1',
        experimentalFatigueConsent: false,
      ),
    );
  }

  @override
  Future<UserProfile> fetch(String userId) async {
    if (fetchError != null) throw fetchError!;
    if (usePending) return pending.future;
    final profile = _profiles[userId];
    if (profile == null) throw StateError('Profile not found');
    return profile;
  }

  @override
  Future<UserProfile> updateProfile(UserProfile profile) async {
    _profiles[profile.user.id] = profile;
    return profile;
  }

  @override
  Future<UserProfile> updateSettings({
    required String userId,
    HealthGoal? goal,
    int? dailyStepGoal,
    bool? healthConnectSync,
    bool? autoSync,
    bool? wifiOnly,
    bool? experimentalFatigueConsent,
  }) async {
    final current = _profiles[userId];
    if (current == null) throw StateError('Profile not found');
    final updated = current.copyWith(
      goal: goal,
      dailyStepGoal: dailyStepGoal,
      healthConnectSync: healthConnectSync,
      autoSync: autoSync,
      wifiOnly: wifiOnly,
      experimentalFatigueConsent: experimentalFatigueConsent,
    );
    _profiles[userId] = updated;
    return updated;
  }

  @override
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {}
}

Future<void> _login(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(keyed('fill-demo'));
  await tester.pumpAndSettle();
  await tester.tap(keyed('login-submit'));
  await tester.pumpAndSettle();
}

void main() {
  const user = AuthUser(
    id: 'profile-test',
    name: 'Minh Anh',
    email: 'demo@healthpal.app',
  );

  test('controller caches a new rowVersion after consent update', () async {
    final repository = DemoProfileRepository();
    repository.ensure(user);
    final controller = ProfileController(
      repository: repository,
      userId: user.id,
    );
    await controller.load();
    expect(controller.profile?.experimentalFatigueConsent, isTrue);
    expect(
      await controller.updateSettings(experimentalFatigueConsent: false),
      isTrue,
    );
    expect(controller.profile?.experimentalFatigueConsent, isFalse);
    expect(controller.profile?.rowVersion, 'demo');
  });

  test(
    'controller leaves consent unchanged when the API update fails',
    () async {
      final repository = _FailingConsentRepository();
      repository.ensure(user);
      final controller = ProfileController(
        repository: repository,
        userId: user.id,
      );
      await controller.load();
      expect(
        await controller.updateSettings(experimentalFatigueConsent: false),
        isFalse,
      );
      expect(controller.profile?.experimentalFatigueConsent, isTrue);
    },
  );

  testWidgets(
    'consent false from first profile response never shows fatigue card',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        HealthPalApp(
          authRepository: DemoAuthRepository(latency: Duration.zero),
          historyRepository: DemoHealthHistoryRepository(
            latency: Duration.zero,
          ),
          profileRepository: DemoProfileRepository(
            defaultFatigueConsent: false,
          ),
          dashboardRepository: DemoHealthConnectRepository(
            snapshot: _fatigueSnapshot,
          ),
          restoreOnStart: false,
        ),
      );
      await _login(tester);
      expect(keyed('dashboard-fatigue-card'), findsNothing);
    },
  );

  testWidgets(
    'dashboard stays fail-closed while profile request is pending or fails',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = _ScriptedProfileRepository()..usePending = true;
      await tester.pumpWidget(
        HealthPalApp(
          authRepository: DemoAuthRepository(latency: Duration.zero),
          historyRepository: DemoHealthHistoryRepository(
            latency: Duration.zero,
          ),
          profileRepository: pending,
          dashboardRepository: DemoHealthConnectRepository(
            snapshot: _fatigueSnapshot,
          ),
          restoreOnStart: false,
        ),
      );
      await tester.pump();
      await tester.tap(keyed('fill-demo'));
      await tester.pump();
      await tester.tap(keyed('login-submit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(keyed('dashboard-fatigue-card'), findsNothing);

      pending.pending.complete(
        UserProfile(
          user: const AuthUser(
            id: 'demo',
            name: 'Minh Anh',
            email: 'demo@healthpal.app',
          ),
          rowVersion: 'v1',
          experimentalFatigueConsent: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(keyed('dashboard-fatigue-card'), findsNothing);
    },
  );

  testWidgets('dashboard stays fail-closed when profile request fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final failing = _ScriptedProfileRepository(
      fetchError: const ProfileException(ProfileFailure.network),
    );
    await tester.pumpWidget(
      HealthPalApp(
        authRepository: DemoAuthRepository(latency: Duration.zero),
        historyRepository: DemoHealthHistoryRepository(latency: Duration.zero),
        profileRepository: failing,
        dashboardRepository: DemoHealthConnectRepository(
          snapshot: _fatigueSnapshot,
        ),
        restoreOnStart: false,
      ),
    );
    await _login(tester);
    expect(keyed('dashboard-fatigue-card'), findsNothing);
  });

  testWidgets('successful opt-in shows card and opt-out hides it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      HealthPalApp(
        authRepository: DemoAuthRepository(latency: Duration.zero),
        historyRepository: DemoHealthHistoryRepository(latency: Duration.zero),
        profileRepository: DemoProfileRepository(defaultFatigueConsent: false),
        dashboardRepository: DemoHealthConnectRepository(
          snapshot: _fatigueSnapshot,
        ),
        restoreOnStart: false,
      ),
    );
    await _login(tester);
    expect(keyed('dashboard-fatigue-card'), findsNothing);

    await tester.tap(keyed('nav-profile'));
    await tester.pumpAndSettle();
    await tester.drag(keyed('profile-screen'), const Offset(0, -720));
    await tester.pumpAndSettle();
    await tester.tap(keyed('profile-fatigue-consent'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('nav-dashboard'));
    await tester.pumpAndSettle();
    expect(keyed('dashboard-fatigue-card'), findsOneWidget);
    expect(keyed('dashboard-fatigue-score'), findsNothing);
    expect(find.text('Có dấu hiệu mệt mỏi'), findsOneWidget);

    await tester.tap(keyed('nav-profile'));
    await tester.pumpAndSettle();
    await tester.drag(keyed('profile-screen'), const Offset(0, -720));
    await tester.pumpAndSettle();
    await tester.tap(keyed('profile-fatigue-consent'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('nav-dashboard'));
    await tester.pumpAndSettle();
    expect(keyed('dashboard-fatigue-card'), findsNothing);
  });
}
