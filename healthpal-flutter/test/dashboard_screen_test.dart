import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/app.dart';
import 'package:healthpal/features/auth/data/demo_auth_repository.dart';
import 'package:healthpal/features/dashboard/data/demo_health_connect_repository.dart';
import 'package:healthpal/features/dashboard/domain/dashboard_models.dart';
import 'package:healthpal/features/history/data/demo_health_history_repository.dart';

Finder keyed(String value) => find.byKey(ValueKey<String>(value));

Future<void> signIn(WidgetTester tester, HealthConnectSnapshot snapshot) async {
  await tester.binding.setSurfaceSize(const Size(360, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    HealthPalApp(
      authRepository: DemoAuthRepository(latency: Duration.zero),
      historyRepository: DemoHealthHistoryRepository(latency: Duration.zero),
      dashboardRepository: DemoHealthConnectRepository(snapshot: snapshot),
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
}

void main() {
  testWidgets('login opens Dashboard as the first tab', (tester) async {
    await signIn(
      tester,
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.unavailable,
        access: HealthConnectAccess.denied,
        missingPermissions: [],
      ),
    );

    expect(keyed('dashboard-content'), findsOneWidget);
    expect(keyed('dashboard-health-status'), findsOneWidget);
    expect(find.text('Health Connect chưa sẵn sàng'), findsOneWidget);
    expect(find.text('Tín hiệu mệt mỏi thử nghiệm'), findsOneWidget);
    expect(find.text('Chưa đủ dữ liệu'), findsWidgets);
    expect(
      find.text(
        'Kết quả chỉ mang tính tham khảo. Không dùng làm chẩn đoán y tế.',
      ),
      findsOneWidget,
    );

    await tester.tap(keyed('nav-training'));
    await tester.pumpAndSettle();
    expect(keyed('training-screen'), findsOneWidget);
    await tester.tap(keyed('nav-history'));
    await tester.pumpAndSettle();
    expect(find.text('Lịch sử sức khỏe'), findsOneWidget);
    await tester.tap(keyed('nav-profile'));
    await tester.pumpAndSettle();
    expect(keyed('profile-screen'), findsOneWidget);
    await tester.tap(keyed('nav-dashboard'));
    await tester.pumpAndSettle();
    expect(keyed('dashboard-content'), findsOneWidget);
  });

  testWidgets('missing permissions are listed and null metrics stay empty', (
    tester,
  ) async {
    await signIn(
      tester,
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.missingPermissions,
        missingPermissions: [
          HealthMetricPermission.sleep,
          HealthMetricPermission.hrv,
        ],
      ),
    );

    expect(find.text('Thiếu quyền'), findsOneWidget);
    expect(find.text('Giấc ngủ · HRV'), findsOneWidget);
    expect(keyed('dashboard-request-permissions'), findsOneWidget);
    expect(find.text('Chưa có dữ liệu'), findsWidgets);
  });

  testWidgets('connected summary shows values and no stress score', (
    tester,
  ) async {
    final now = DateTime.now();
    await signIn(
      tester,
      HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: const [],
        summary: TodayHealthSummary(
          steps: 7420,
          sleepMinutes: 402,
          averageHeartRate: 72,
          restingHeartRate: 68,
          hrv: 47,
          activeCalories: 380,
          collectedAt: now,
        ),
        lastSyncedAt: now,
      ),
    );

    expect(find.text('Đã kết nối'), findsOneWidget);
    expect(find.text('7.420'), findsOneWidget);
    expect(find.text('6h 42m'), findsOneWidget);
    expect(find.text('68'), findsOneWidget);
    expect(find.text('47'), findsOneWidget);
    expect(find.text('Stress hiện tại'), findsNothing);
    expect(find.text('Stress Trung bình'), findsNothing);
    expect(find.text('Stress Cao'), findsNothing);
    expect(find.text('Tín hiệu mệt mỏi thử nghiệm'), findsOneWidget);
    expect(keyed('dashboard-sync-health-data'), findsOneWidget);
  });

  testWidgets('authorized no-data state still offers manual health sync', (
    tester,
  ) async {
    await signIn(
      tester,
      const HealthConnectSnapshot(
        availability: HealthConnectAvailability.available,
        access: HealthConnectAccess.granted,
        missingPermissions: [],
      ),
    );

    expect(find.text('Không có dữ liệu'), findsOneWidget);
    expect(keyed('dashboard-sync-health-data'), findsOneWidget);
    expect(find.text('Đồng bộ dữ liệu sức khỏe'), findsOneWidget);
  });
}
