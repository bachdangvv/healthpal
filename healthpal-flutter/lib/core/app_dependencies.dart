import 'dart:io';

import 'package:healthpal/core/api/api_client.dart';
import 'package:healthpal/core/auth/installation_store.dart';
import 'package:healthpal/core/auth/secure_token_store.dart';
import 'package:healthpal/core/config/app_config.dart';
import 'package:healthpal/core/database/device_settings_store.dart';
import 'package:healthpal/core/database/healthpal_database.dart';
import 'package:healthpal/core/user_health_runtime.dart';
import 'package:healthpal/features/auth/data/api_auth_repository.dart';
import 'package:healthpal/features/auth/data/auth_repository.dart';
import 'package:healthpal/features/auth/data/demo_auth_repository.dart';
import 'package:healthpal/features/dashboard/data/demo_health_connect_repository.dart';
import 'package:healthpal/features/dashboard/data/health_connect_repository.dart';
import 'package:healthpal/features/history/data/demo_health_history_repository.dart';
import 'package:healthpal/features/history/data/health_history_repository.dart';
import 'package:healthpal/features/profile/data/api_profile_repository.dart';
import 'package:healthpal/features/profile/data/demo_profile_repository.dart';
import 'package:healthpal/features/profile/data/profile_repository.dart';
import 'package:healthpal/features/training/data/api_exercise_repository.dart';
import 'package:healthpal/features/training/data/api_training_readiness_repository.dart';
import 'package:healthpal/features/training/data/demo_exercise_repository.dart';
import 'package:healthpal/features/training/data/health_connect_training_readiness_repository.dart';
import 'package:healthpal/features/training/data/exercise_repository.dart';
import 'package:healthpal/features/training/data/training_readiness_repository.dart';
import 'package:healthpal/features/training/domain/training_models.dart';

class AppDependencies {
  AppDependencies({
    required this.authRepository,
    this.historyRepository,
    required this.profileRepository,
    this.dashboardRepository,
    this.trainingReadinessRepository,
    this.exerciseRepository,
    this.database,
    this.runtimeFactory,
    this.fatalStartupError,
  });

  final AuthRepository authRepository;
  final HealthHistoryRepository? historyRepository;
  final ProfileRepository profileRepository;
  final HealthConnectRepository? dashboardRepository;
  final TrainingReadinessRepository? trainingReadinessRepository;
  final ExerciseRepository? exerciseRepository;
  final HealthPalDatabase? database;
  final UserHealthRuntimeFactory? runtimeFactory;
  final String? fatalStartupError;

  static Future<AppDependencies> production() async {
    if (!Platform.isAndroid) {
      return AppDependencies(
        authRepository: DemoAuthRepository(),
        historyRepository: DemoHealthHistoryRepository(),
        profileRepository: DemoProfileRepository(),
        dashboardRepository: const DemoHealthConnectRepository(),
        trainingReadinessRepository: HealthConnectTrainingReadinessRepository(
          healthConnectRepository: const DemoHealthConnectRepository(),
          stressService: const UnavailableStressAssessmentService(),
        ),
        exerciseRepository: DemoExerciseRepository(),
      );
    }

    final tokenStore = SecureTokenStore();
    final client = ApiClient(
      tokenStore: tokenStore,
      baseUrl: AppConfig.apiBaseUrl,
    );
    final authRepository = ApiAuthRepository(
      client: client,
      tokenStore: tokenStore,
    );

    try {
      AppConfig.validateForCurrentBuild();
    } on AppConfigException catch (error) {
      return AppDependencies(
        authRepository: authRepository,
        profileRepository: ApiProfileRepository(client: client),
        trainingReadinessRepository: ApiTrainingReadinessRepository(client: client),
        exerciseRepository: ApiExerciseRepository(client: client),
        fatalStartupError: error.message,
      );
    }

    try {
      final database = await HealthPalDatabase.appFile();
      final settings = DeviceSettingsStore(database);
      return AppDependencies(
        authRepository: authRepository,
        profileRepository: ApiProfileRepository(
          client: client,
          settingsStore: settings,
        ),
        trainingReadinessRepository: ApiTrainingReadinessRepository(client: client),
        exerciseRepository: ApiExerciseRepository(client: client),
        database: database,
        runtimeFactory: UserHealthRuntimeFactory(
          database: database,
          client: client,
          installation: SecureInstallationStore(),
        ),
      );
    } catch (_) {
      return AppDependencies(
        authRepository: authRepository,
        profileRepository: ApiProfileRepository(client: client),
        trainingReadinessRepository: ApiTrainingReadinessRepository(client: client),
        exerciseRepository: ApiExerciseRepository(client: client),
        fatalStartupError:
            'Không thể mở cơ sở dữ liệu cục bộ. Hãy đóng ứng dụng và thử lại.',
      );
    }
  }
}
