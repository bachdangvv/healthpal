import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/app.dart';
import 'package:healthpal/features/auth/data/demo_auth_repository.dart';
import 'package:healthpal/features/history/data/demo_health_history_repository.dart';

Finder control(String key) => find.byKey(ValueKey<String>(key));

Future<void> openApp(
  WidgetTester tester, {
  Duration latency = Duration.zero,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    HealthPalApp(
      authRepository: DemoAuthRepository(latency: latency),
      historyRepository: DemoHealthHistoryRepository(
        anchorDate: DateTime(2026, 9, 23),
        latency: Duration.zero,
      ),
      restoreOnStart: false,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapControl(WidgetTester tester, String key) async {
  await tester.ensureVisible(control(key));
  await tester.pumpAndSettle();
  await tester.tap(control(key));
  await tester.pumpAndSettle();
}

Future<void> openHistoryTab(WidgetTester tester) async {
  await tapControl(tester, 'nav-history');
}

Future<void> enterField(WidgetTester tester, String key, String value) async {
  await tester.ensureVisible(control(key));
  await tester.enterText(control(key), value);
  await tester.pumpAndSettle();
}

bool fieldHasError(WidgetTester tester, String key) =>
    tester.state<FormFieldState<String>>(control(key)).hasError;

String fieldValue(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(control(key)).controller!.text;

void main() {
  testWidgets('Sign-in validates required fields and malformed credentials', (
    tester,
  ) async {
    await openApp(tester);

    expect(control('login-screen'), findsOneWidget);
    await tapControl(tester, 'login-submit');
    expect(fieldHasError(tester, 'login-email'), isTrue);
    expect(fieldHasError(tester, 'login-password'), isTrue);

    await enterField(tester, 'login-email', 'invalid-email');
    await enterField(tester, 'login-password', 'short');
    await tapControl(tester, 'login-submit');
    expect(fieldHasError(tester, 'login-email'), isTrue);
    expect(fieldHasError(tester, 'login-password'), isTrue);
    expect(control('history-screen'), findsNothing);
  });

  testWidgets('Demo fill and sign-in show the authenticated account', (
    tester,
  ) async {
    await openApp(tester);
    await tapControl(tester, 'fill-demo');

    expect(fieldValue(tester, 'login-email'), 'demo@healthpal.app');
    expect(fieldValue(tester, 'login-password'), 'HealthPal123');
    await tapControl(tester, 'login-submit');

    expect(control('history-screen'), findsOneWidget);
    expect(control('dashboard-content'), findsOneWidget);
    expect(control('login-screen'), findsNothing);
  });

  testWidgets('A wrong password leaves sign-in visible with a useful error', (
    tester,
  ) async {
    await openApp(tester);
    await enterField(tester, 'login-email', 'demo@healthpal.app');
    await enterField(tester, 'login-password', 'WrongPassword123');
    await tapControl(tester, 'login-submit');

    expect(control('login-screen'), findsOneWidget);
    expect(control('history-screen'), findsNothing);
    expect(control('auth-error'), findsOneWidget);
  });

  testWidgets('Registration validates name, email, password and confirmation', (
    tester,
  ) async {
    await openApp(tester);
    await tapControl(tester, 'open-register');
    await tapControl(tester, 'register-submit');

    for (final key in [
      'register-name',
      'register-email',
      'register-password',
      'register-confirm',
    ]) {
      expect(fieldHasError(tester, key), isTrue, reason: key);
    }

    await enterField(tester, 'register-name', 'Minh Anh');
    await enterField(tester, 'register-email', 'invalid-email');
    await enterField(tester, 'register-password', 'short');
    await enterField(tester, 'register-confirm', 'different');
    await tapControl(tester, 'register-submit');

    expect(fieldHasError(tester, 'register-name'), isFalse);
    expect(fieldHasError(tester, 'register-email'), isTrue);
    expect(fieldHasError(tester, 'register-password'), isTrue);
    expect(fieldHasError(tester, 'register-confirm'), isTrue);
    expect(control('history-screen'), findsNothing);
  });

  testWidgets('Existing email is rejected after trimming and case folding', (
    tester,
  ) async {
    await openApp(tester);
    await tapControl(tester, 'open-register');
    await enterField(tester, 'register-name', 'Duplicate account');
    await enterField(tester, 'register-email', ' DEMO@HEALTHPAL.APP ');
    await enterField(tester, 'register-password', 'AnotherPass123');
    await enterField(tester, 'register-confirm', 'AnotherPass123');
    await tapControl(tester, 'register-submit');

    expect(control('register-screen'), findsOneWidget);
    expect(control('history-screen'), findsNothing);
    expect(control('auth-error'), findsOneWidget);
  });

  testWidgets('Register, cancel logout, confirm logout and sign in again', (
    tester,
  ) async {
    await openApp(tester);
    await tapControl(tester, 'open-register');
    await enterField(tester, 'register-name', 'Minh Anh');
    await enterField(tester, 'register-email', ' Minh.Anh@Example.com ');
    await enterField(tester, 'register-password', 'StrongPass123');
    await enterField(tester, 'register-confirm', 'StrongPass123');
    await tapControl(tester, 'register-submit');

    expect(control('history-screen'), findsOneWidget);
    await openHistoryTab(tester);
    await tapControl(tester, 'history-account-menu');
    expect(find.text('Minh Anh'), findsOneWidget);
    expect(find.text('minh.anh@example.com'), findsOneWidget);
    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();

    await tapControl(tester, 'history-account-menu');
    await tapControl(tester, 'history-menu-logout');
    expect(control('confirm-logout'), findsOneWidget);
    await tapControl(tester, 'cancel-logout');
    expect(control('history-screen'), findsOneWidget);
    expect(control('confirm-logout'), findsNothing);

    await tapControl(tester, 'history-account-menu');
    await tapControl(tester, 'history-menu-logout');
    await tapControl(tester, 'confirm-logout');
    expect(control('login-screen'), findsOneWidget);
    expect(fieldValue(tester, 'login-password'), isEmpty);
    expect(control('history-screen'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(control('history-screen'), findsNothing);
    expect(control('login-screen'), findsOneWidget);

    await enterField(tester, 'login-email', ' MINH.ANH@EXAMPLE.COM ');
    await enterField(tester, 'login-password', 'StrongPass123');
    await tapControl(tester, 'login-submit');
    expect(control('history-screen'), findsOneWidget);
    await openHistoryTab(tester);
    await tapControl(tester, 'history-account-menu');
    expect(find.text('Minh Anh'), findsOneWidget);
  });

  testWidgets('Returning from registration opens the sign-in form', (
    tester,
  ) async {
    await openApp(tester);
    await tapControl(tester, 'open-register');
    expect(control('register-screen'), findsOneWidget);
    await tapControl(tester, 'back-login');
    expect(control('login-screen'), findsOneWidget);
    expect(control('register-screen'), findsNothing);
  });

  testWidgets('Sign-in disables repeated submission while processing', (
    tester,
  ) async {
    await openApp(tester, latency: const Duration(milliseconds: 600));
    await tapControl(tester, 'fill-demo');
    await tester.ensureVisible(control('login-submit'));
    await tester.pumpAndSettle();
    await tester.tap(control('login-submit'));
    await tester.pump();

    expect(
      tester.widget<ButtonStyleButton>(control('login-submit')).onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(control('login-submit'));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();

    expect(control('history-screen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small viewport, enlarged text and keyboard remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await enterField(tester, 'login-email', 'demo@healthpal.app');
    await enterField(tester, 'login-password', 'HealthPal123');
    expect(tester.takeException(), isNull);

    await tapControl(tester, 'open-register');
    await enterField(tester, 'register-name', 'Nguyễn Minh Anh');
    await enterField(tester, 'register-email', 'small.screen@example.com');
    await enterField(tester, 'register-password', 'StrongPass123');
    await enterField(tester, 'register-confirm', 'StrongPass123');
    expect(tester.takeException(), isNull);
    await tapControl(tester, 'register-submit');

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(control('history-screen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await openHistoryTab(tester);
    await tapControl(tester, 'history-account-menu');
    await tapControl(tester, 'history-menu-logout');
    expect(tester.takeException(), isNull);
    await tapControl(tester, 'confirm-logout');
    expect(control('login-screen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
