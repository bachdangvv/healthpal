import '../domain/training_models.dart';

abstract interface class ExerciseRepository {
  Future<List<Exercise>> fetchAll();

  Future<void> setFavorite(String exerciseId, bool favorite);

  bool isFavorite(String exerciseId);
}
