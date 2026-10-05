import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/app.dart';
import 'package:healthpal/features/auth/data/demo_auth_repository.dart';
import 'package:healthpal/features/history/data/demo_health_history_repository.dart';

Finder keyed(String value) => find.byKey(ValueKey<String>(value));

Future<void> openHistory(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    HealthPalApp(
      authRepository: DemoAuthRepository(latency: Duration.zero),
      historyRepository: DemoHealthHistoryRepository(
        anchorDate: DateTime(2026, 9, 23),
        latency: Duration.zero,
      ),
      restoreOnStart: false,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(keyed('fill-demo'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(keyed('login-submit'));
  await tester.tap(keyed('login-submit'));
  await tester.pumpAndSettle();
  expect(keyed('history-screen'), findsOneWidget);
  await tester.tap(keyed('nav-history'));
  await tester.pumpAndSettle();
}

Future<void> selectMetric(WidgetTester tester, String metric) async {
  final finder = keyed('history-metric-$metric');
  final trailingMetrics = {'restingHeartRate', 'hrv', 'activeCalories'};
  for (var attempt = 0; attempt < 3 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(
      keyed('history-metric-list'),
      Offset(trailingMetrics.contains(metric) ? -260 : 260, 0),
    );
    await tester.pumpAndSettle();
  }
  for (var attempt = 0; attempt < 5; attempt++) {
    final center = tester.getCenter(finder);
    if (center.dx >= 20 && center.dx <= 410) break;
    await tester.drag(
      keyed('history-metric-list'),
      Offset(center.dx > 410 ? -220 : 220, 0),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('history switches between seven and thirty days', (tester) async {
    await openHistory(tester);

    expect(keyed('history-content-7'), findsOneWidget);
    expect(keyed('history-chart-fatigue'), findsOneWidget);

    await tester.tap(keyed('history-period-30'));
    await tester.pumpAndSettle();

    expect(keyed('history-content-30'), findsOneWidget);
    expect(keyed('history-chart-fatigue'), findsOneWidget);
  });

  testWidgets('all metric chips select the expected chart type', (
    tester,
  ) async {
    await openHistory(tester);

    for (final metric in ['sleep', 'steps', 'activeCalories']) {
      await selectMetric(tester, metric);
      expect(keyed('history-metric-icon-$metric'), findsOneWidget);
      expect(keyed('history-chart-icon-$metric'), findsOneWidget);
      expect(keyed('history-chart-$metric'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
    }

    for (final metric in ['restingHeartRate', 'hrv']) {
      await selectMetric(tester, metric);
      expect(keyed('history-metric-icon-$metric'), findsOneWidget);
      expect(keyed('history-chart-icon-$metric'), findsOneWidget);
      expect(keyed('history-chart-$metric'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
    }

    await selectMetric(tester, 'fatigue');
    expect(keyed('history-metric-icon-fatigue'), findsOneWidget);
    expect(keyed('history-chart-icon-fatigue'), findsOneWidget);
    expect(keyed('history-chart-fatigue'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Mệt mỏi'), findsWidgets);
  });

  testWidgets('day details open in a bottom sheet and preserve filters', (
    tester,
  ) async {
    await openHistory(tester);
    await tester.tap(keyed('history-period-30'));
    await tester.pumpAndSettle();
    await selectMetric(tester, 'steps');

    await tester.tap(keyed('history-day-2026-09-23'));
    await tester.pumpAndSettle();

    expect(keyed('history-day-detail'), findsOneWidget);
    expect(find.textContaining('dấu hiệu mệt mỏi'), findsWidgets);
    expect(find.text('Giấc ngủ'), findsWidgets);
    expect(find.text('Nhịp tim nghỉ'), findsWidgets);
    expect(find.text('HRV'), findsWidgets);
    expect(find.text('Calories vận động'), findsOneWidget);

    await tester.tapAt(const Offset(10, 80));
    await tester.pumpAndSettle();
    expect(keyed('history-day-detail'), findsNothing);
    expect(keyed('history-content-30'), findsOneWidget);
    expect(keyed('history-chart-steps'), findsOneWidget);
  });
}
