import 'package:flutter/material.dart';

import 'core/user_health_runtime.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/demo_auth_repository.dart';
import 'features/auth/presentation/auth_flow.dart';
import 'features/history/data/demo_health_history_repository.dart';
import 'features/history/data/health_history_repository.dart';
import 'features/dashboard/data/demo_health_connect_repository.dart';
import 'features/dashboard/data/health_connect_repository.dart';

import 'features/profile/data/demo_profile_repository.dart';
import 'features/profile/data/profile_repository.dart';
import 'features/training/data/demo_exercise_repository.dart';
import 'features/training/data/exercise_repository.dart';
import 'features/training/data/health_connect_training_readiness_repository.dart';
import 'features/training/data/training_readiness_repository.dart';
import 'features/training/domain/training_models.dart';
import 'theme/healthpal_theme.dart';

class HealthPalApp extends StatefulWidget {
  const HealthPalApp({
    super.key,
    this.authRepository,
    this.historyRepository,
    this.profileRepository,
    this.dashboardRepository,
    this.trainingReadinessRepository,
    this.exerciseRepository,
    this.runtimeFactory,
    this.restoreOnStart = true,
    this.fatalStartupError,
  });

  final AuthRepository? authRepository;
  final HealthHistoryRepository? historyRepository;
  final ProfileRepository? profileRepository;
  final HealthConnectRepository? dashboardRepository;
  final TrainingReadinessRepository? trainingReadinessRepository;
  final ExerciseRepository? exerciseRepository;
  final UserHealthRuntimeFactory? runtimeFactory;
  final bool restoreOnStart;
  final String? fatalStartupError;

  @override
  State<HealthPalApp> createState() => _HealthPalAppState();
}

class _HealthPalAppState extends State<HealthPalApp> {
  late final AuthController _auth = AuthController(
    repository: widget.authRepository ?? DemoAuthRepository(),
    restoreOnStart: widget.restoreOnStart,
  );
  late final HealthHistoryRepository _historyRepository =
      widget.historyRepository ?? DemoHealthHistoryRepository();
  late final ProfileRepository _profileRepository =
      widget.profileRepository ?? DemoProfileRepository();
  late final HealthConnectRepository _dashboardRepository =
      widget.dashboardRepository ?? const DemoHealthConnectRepository();
  late final TrainingReadinessRepository _trainingReadinessRepository =
      widget.trainingReadinessRepository ??
      HealthConnectTrainingReadinessRepository(
        healthConnectRepository: _dashboardRepository,
        stressService: const UnavailableStressAssessmentService(),
      );
  late final ExerciseRepository _exerciseRepository =
      widget.exerciseRepository ?? DemoExerciseRepository();

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fatalStartupError != null) {
      return MaterialApp(
        title: 'HealthPal',
        debugShowCheckedModeBanner: false,
        theme: healthPalTheme,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                widget.fatalStartupError!,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    return MaterialApp(
      title: 'HealthPal',
      debugShowCheckedModeBanner: false,
      theme: healthPalTheme,
      home: AuthFlow(
        controller: _auth,
        historyRepository: _historyRepository,
        profileRepository: _profileRepository,
        dashboardRepository: _dashboardRepository,
        trainingReadinessRepository: _trainingReadinessRepository,
        exerciseRepository: _exerciseRepository,
        runtimeFactory: widget.runtimeFactory,
      ),
    );
  }
}
