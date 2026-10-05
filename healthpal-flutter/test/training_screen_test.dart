import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/app.dart';
import 'package:healthpal/features/auth/data/demo_auth_repository.dart';
import 'package:healthpal/features/dashboard/data/demo_health_connect_repository.dart';
import 'package:healthpal/features/dashboard/domain/dashboard_models.dart';
import 'package:healthpal/features/history/data/demo_health_history_repository.dart';

Finder keyed(String value) => find.byKey(ValueKey<String>(value));

void main() {
  testWidgets('training tab opens with readiness and empty exercise library', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      HealthPalApp(
        authRepository: DemoAuthRepository(latency: Duration.zero),
        historyRepository: DemoHealthHistoryRepository(latency: Duration.zero),
        dashboardRepository: const DemoHealthConnectRepository(
          snapshot: HealthConnectSnapshot(
            availability: HealthConnectAvailability.unavailable,
            access: HealthConnectAccess.denied,
            missingPermissions: [],
          ),
        ),
        restoreOnStart: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(keyed('fill-demo'));
    await tester.tap(keyed('fill-demo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(keyed('login-submit'));
    await tester.tap(keyed('login-submit'));
    await tester.pumpAndSettle();

    expect(keyed('dashboard-content'), findsOneWidget);
    await tester.tap(keyed('nav-training'));
    await tester.pumpAndSettle();

    expect(keyed('training-screen'), findsOneWidget);
    expect(keyed('training-readiness-card'), findsOneWidget);
    expect(find.text('Chưa đủ dữ liệu'), findsOneWidget);
    expect(keyed('training-empty-library'), findsOneWidget);
    expect(find.text('Chưa có dữ liệu bài tập'), findsOneWidget);
    expect(find.text('set'), findsNothing);
    expect(find.text('rep'), findsNothing);
    expect(find.text('weight'), findsNothing);

    await tester.enterText(keyed('training-search'), 'squat');
    await tester.ensureVisible(keyed('training-group-all'));
    await tester.tap(keyed('training-group-all'));
    await tester.pumpAndSettle();
    expect(keyed('training-empty-library'), findsOneWidget);
  });
}
