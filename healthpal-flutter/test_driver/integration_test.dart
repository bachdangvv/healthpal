import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory('build/auth_screenshots');
  await directory.create(recursive: true);

  await integrationDriver(
    onScreenshot:
        (
          String screenshotName,
          List<int> screenshotBytes, [
          Map<String, Object?>? args,
        ]) async {
          if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(screenshotName) ||
              screenshotBytes.isEmpty) {
            return false;
          }
          await File('${directory.path}/$screenshotName.png')
              .writeAsBytes(screenshotBytes, flush: true);
          return true;
        },
    responseDataCallback: null,
  );
}
