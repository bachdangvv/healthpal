import '../../dashboard/data/health_connect_repository.dart';
import '../domain/training_models.dart';
import 'training_readiness_repository.dart';

class HealthConnectTrainingReadinessRepository
    implements TrainingReadinessRepository {
  const HealthConnectTrainingReadinessRepository({
    required this.healthConnectRepository,
    this.stressService = const UnavailableStressAssessmentService(),
  });

  final HealthConnectRepository healthConnectRepository;
  final StressAssessmentService stressService;

  @override
  Future<TrainingReadinessInput> fetchInput() async {
    final snapshot = await healthConnectRepository.fetchSnapshot();
    final summary = snapshot.summary;
    final collectedAt = summary?.collectedAt ?? DateTime.now();
    final stressResult = await stressService.assess(
      StressAssessmentInput(
        steps: summary?.steps,
        sleepMinutes: summary?.sleepMinutes,
        activeCalories: summary?.activeCalories,
        collectedAt: collectedAt,
      ),
    );
    return TrainingReadinessInput(
      stress: stressResult.available ? stressResult.level : null,
      sleepMinutes: summary?.sleepMinutes,
      steps: summary?.steps,
      activeCalories: summary?.activeCalories,
      collectedAt: collectedAt,
    );
  }
}
