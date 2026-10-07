import 'dart:io';

import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/app_dependencies.dart';
import 'core/sync/health_sync_worker.dart';
import 'src/rust/api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    try {
      await initHealthpalRust();
    } catch (_) {
      // Assessment stays insufficient until the native runtime is available.
    }
    await Workmanager().initialize(healthSyncBackgroundDispatcher);
  }
  final dependencies = await AppDependencies.production();
  runApp(
    HealthPalApp(
      authRepository: dependencies.authRepository,
      historyRepository: dependencies.historyRepository,
      profileRepository: dependencies.profileRepository,
      dashboardRepository: dependencies.dashboardRepository,
      trainingReadinessRepository: dependencies.trainingReadinessRepository,
      exerciseRepository: dependencies.exerciseRepository,
      runtimeFactory: dependencies.runtimeFactory,
      restoreOnStart: true,
      fatalStartupError: dependencies.fatalStartupError,
    ),
  );
}
