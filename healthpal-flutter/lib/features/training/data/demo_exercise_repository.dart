import '../domain/training_models.dart';
import 'exercise_repository.dart';

class DemoExerciseRepository implements ExerciseRepository {
  DemoExerciseRepository({List<Exercise> exercises = const []})
    : _exercises = List.unmodifiable(exercises);

  final List<Exercise> _exercises;
  final Set<String> _favorites = {};

  @override
  Future<List<Exercise>> fetchAll() async => _exercises;

  @override
  Future<void> setFavorite(String exerciseId, bool favorite) async {
    if (favorite) {
      _favorites.add(exerciseId);
    } else {
      _favorites.remove(exerciseId);
    }
  }

  @override
  bool isFavorite(String exerciseId) => _favorites.contains(exerciseId);
}
