import 'package:flutter/foundation.dart';

/// Compile-time configuration. Pass values with `--dart-define`.
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080 --dart-define=ENABLE_EXPERIMENTAL_FATIGUE=true
/// ```
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5080',
  );

  /// Team demo builds leave this on. Release outside the trial group must
  /// pass `--dart-define=ENABLE_EXPERIMENTAL_FATIGUE=false`.
  static const bool experimentalFatigueAssessment = bool.fromEnvironment(
    'ENABLE_EXPERIMENTAL_FATIGUE',
    defaultValue: true,
  );

  static const int syncSchemaVersion = 2;
  static const String fatigueModelVersion = 'healthpal_fatigue_v4';
  static const double fatigueDecisionThreshold = 0.18170608515558545;

  static void validateForCurrentBuild() {
    validateUrl(apiBaseUrl, isRelease: kReleaseMode);
  }

  static void validateUrl(String url, {required bool isRelease}) {
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        parsed.host.isEmpty ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      throw const AppConfigException(
        'Địa chỉ máy chủ không hợp lệ. Kiểm tra API_BASE_URL.',
      );
    }
    if (!isRelease) return;
    final host = parsed.host.toLowerCase();
    if (parsed.scheme != 'https' ||
        host == '10.0.2.2' ||
        host == 'localhost' ||
        host == '127.0.0.1') {
      throw const AppConfigException(
        'Bản phát hành cần HTTPS tới máy chủ thật, không dùng emulator hoặc localhost.',
      );
    }
  }
}

class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}
