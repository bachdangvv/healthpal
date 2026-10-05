import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/main.dart' as app;
import 'package:integration_test/integration_test.dart';

Finder control(String key) => find.byKey(ValueKey<String>(key));

Future<void> tapControl(WidgetTester tester, String key) async {
  await tester.ensureVisible(control(key));
  await tester.pumpAndSettle();
  await tester.tap(control(key));
  await tester.pumpAndSettle();
}

Future<void> enterField(WidgetTester tester, String key, String value) async {
  await tester.ensureVisible(control(key));
  await tester.enterText(control(key), value);
  await tester.pumpAndSettle();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android registration and logout smoke test with screenshots', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();

    expect(control('login-screen'), findsOneWidget);
    await binding.takeScreenshot('01-login');

    await tapControl(tester, 'open-register');
    expect(control('register-screen'), findsOneWidget);
    await binding.takeScreenshot('02-register-top');
    await tester.ensureVisible(control('register-submit'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('03-register-bottom');

    await enterField(tester, 'register-name', 'Minh Anh');
    await enterField(tester, 'register-email', 'minh.anh@example.com');
    await enterField(tester, 'register-password', 'HealthPal123');
    await enterField(tester, 'register-confirm', 'HealthPal123');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapControl(tester, 'register-submit');

    expect(control('history-screen'), findsOneWidget);
    await tapControl(tester, 'nav-history');
    expect(find.text('Lịch sử sức khỏe'), findsOneWidget);
    await binding.takeScreenshot('04-history');

    await tapControl(tester, 'history-account-menu');
    expect(find.text('minh.anh@example.com'), findsOneWidget);
    await tapControl(tester, 'history-menu-logout');
    expect(control('confirm-logout'), findsOneWidget);
    await binding.takeScreenshot('05-logout-confirmation');
    await tapControl(tester, 'confirm-logout');

    expect(control('login-screen'), findsOneWidget);
    expect(control('history-screen'), findsNothing);
    expect(
      tester.widget<TextFormField>(control('login-password')).controller!.text,
      isEmpty,
    );
    await binding.takeScreenshot('06-logged-out');
    expect(tester.takeException(), isNull);
  });
}
