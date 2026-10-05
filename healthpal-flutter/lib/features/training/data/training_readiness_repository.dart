import '../domain/training_models.dart';

abstract interface class TrainingReadinessRepository {
  Future<TrainingReadinessInput> fetchInput();
}
