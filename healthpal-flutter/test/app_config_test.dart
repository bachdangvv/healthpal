import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/config/app_config.dart';

void main() {
  test('valid HTTPS URL passes in release', () {
    expect(
      () => AppConfig.validateUrl('https://api.example.com', isRelease: true),
      returnsNormally,
    );
  });

  test('empty or invalid URL fails', () {
    expect(
      () => AppConfig.validateUrl('', isRelease: false),
      throwsA(isA<AppConfigException>()),
    );
    expect(
      () => AppConfig.validateUrl('not-a-url', isRelease: false),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('release rejects HTTP and emulator hosts', () {
    expect(
      () => AppConfig.validateUrl('http://10.0.2.2:5080', isRelease: true),
      throwsA(isA<AppConfigException>()),
    );
    expect(
      () => AppConfig.validateUrl('https://10.0.2.2:5080', isRelease: true),
      throwsA(isA<AppConfigException>()),
    );
    expect(
      () => AppConfig.validateUrl('https://localhost', isRelease: true),
      throwsA(isA<AppConfigException>()),
    );
  });

  test('debug allows emulator and LAN HTTP', () {
    expect(
      () => AppConfig.validateUrl('http://10.0.2.2:5080', isRelease: false),
      returnsNormally,
    );
    expect(
      () => AppConfig.validateUrl('http://192.168.1.20:5080', isRelease: false),
      returnsNormally,
    );
  });
}
