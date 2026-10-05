import 'package:flutter/foundation.dart';

import '../data/exercise_repository.dart';
import '../domain/training_models.dart';

class ExerciseLibraryController extends ChangeNotifier {
  ExerciseLibraryController({required this.repository});

  final ExerciseRepository repository;
  List<Exercise> _all = const [];
  String query = '';
  ExerciseMuscleGroup group = ExerciseMuscleGroup.all;
  bool isLoading = false;

  List<Exercise> get exercises => _all.where(_matches).toList(growable: false);

  Future<void> load() async {
    if (isLoading) return;
    isLoading = true;
    notifyListeners();
    try {
      _all = await repository.fetchAll();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void setGroup(ExerciseMuscleGroup value) {
    group = value;
    notifyListeners();
  }

  Future<void> toggleFavorite(Exercise exercise) async {
    await repository.setFavorite(
      exercise.id,
      !repository.isFavorite(exercise.id),
    );
    notifyListeners();
  }

  bool isFavorite(Exercise exercise) => repository.isFavorite(exercise.id);

  bool _matches(Exercise exercise) {
    final normalized = query.trim().toLowerCase();
    final text = '${exercise.name} ${exercise.englishName ?? ''}'.toLowerCase();
    return (normalized.isEmpty || text.contains(normalized)) &&
        (group == ExerciseMuscleGroup.all || exercise.muscleGroup == group);
  }
}
