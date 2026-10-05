import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/training/application/training_readiness_rule_engine.dart';
import 'package:healthpal/features/training/application/exercise_library_controller.dart';
import 'package:healthpal/features/training/data/demo_exercise_repository.dart';
import 'package:healthpal/features/training/domain/training_models.dart';

void main() {
  final now = DateTime(2026, 9, 28);
  const engine = TrainingReadinessRuleEngine();

  TrainingReadinessInput input({
    StressLevel? stress = StressLevel.low,
    int? sleepMinutes = 450,
    int? steps = 6000,
    double? activeCalories = 300,
  }) => TrainingReadinessInput(
    stress: stress,
    sleepMinutes: sleepMinutes,
    steps: steps,
    activeCalories: activeCalories,
    collectedAt: now,
  );

  test('missing stress or sleep never produces a readiness conclusion', () {
    expect(
      engine.evaluate(input(stress: null)).status,
      TrainingReadinessStatus.insufficientData,
    );
    expect(
      engine.evaluate(input(sleepMinutes: null)).status,
      TrainingReadinessStatus.insufficientData,
    );
  });

  test('readiness rules apply thresholds and movement adjustment', () {
    expect(engine.evaluate(input()).status, TrainingReadinessStatus.ready);
    expect(
      engine.evaluate(input(stress: StressLevel.medium)).status,
      TrainingReadinessStatus.moderate,
    );
    expect(
      engine.evaluate(input(sleepMinutes: 390)).status,
      TrainingReadinessStatus.moderate,
    );
    expect(
      engine
          .evaluate(input(stress: StressLevel.high, sleepMinutes: 330))
          .status,
      TrainingReadinessStatus.recovery,
    );
    expect(
      engine
          .evaluate(input(stress: StressLevel.high, sleepMinutes: 299))
          .status,
      TrainingReadinessStatus.rest,
    );
    expect(
      engine.evaluate(input(steps: 1000)).status,
      TrainingReadinessStatus.moderate,
    );
  });

  test(
    'exercise search, group filtering and favorites work with repository data',
    () async {
      const exercises = [
        Exercise(
          id: 'squat',
          name: 'Squat',
          muscleGroup: ExerciseMuscleGroup.legs,
          exerciseType: 'Strength',
          equipment: 'Bodyweight',
          instructions: 'Giữ lưng thẳng.',
        ),
        Exercise(
          id: 'push-up',
          name: 'Chống đẩy',
          muscleGroup: ExerciseMuscleGroup.chest,
          exerciseType: 'Strength',
          equipment: 'Bodyweight',
          instructions: 'Hạ người có kiểm soát.',
        ),
      ];
      final repository = DemoExerciseRepository(exercises: exercises);
      final controller = ExerciseLibraryController(repository: repository);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.exercises, hasLength(2));
      controller.setGroup(ExerciseMuscleGroup.legs);
      expect(controller.exercises.single.id, 'squat');
      controller.setGroup(ExerciseMuscleGroup.all);
      controller.setQuery('đẩy');
      expect(controller.exercises.single.id, 'push-up');
      await controller.toggleFavorite(controller.exercises.single);
      expect(controller.isFavorite(controller.exercises.single), isTrue);
    },
  );
}
