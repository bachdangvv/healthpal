import '../../../core/api/api_client.dart';
import '../domain/training_models.dart';
import 'exercise_repository.dart';

class ApiExerciseRepository implements ExerciseRepository {
  ApiExerciseRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;
  final Map<String, bool> _favorites = {};

  @override
  Future<List<Exercise>> fetchAll() async {
    final response = await _client.raw.get<List<dynamic>>(
      '/api/v1/training/exercises',
    );
    final items = response.data ?? const <dynamic>[];
    final exercises = <Exercise>[];
    for (final item in items) {
      final json = item as Map<String, dynamic>;
      final exercise = _fromJson(json);
      exercises.add(exercise);
      _favorites[exercise.id] = json['favorite'] as bool? ?? false;
    }
    return List.unmodifiable(exercises);
  }

  @override
  Future<void> setFavorite(String exerciseId, bool favorite) async {
    await _client.raw.put<void>(
      '/api/v1/training/exercises/$exerciseId/favorite',
      data: {'favorite': favorite},
    );
    _favorites[exerciseId] = favorite;
  }

  @override
  bool isFavorite(String exerciseId) => _favorites[exerciseId] ?? false;

  Exercise _fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String,
    name: json['name'] as String,
    englishName: json['englishName'] as String?,
    muscleGroup: _parseGroup(json['muscleGroup'] as String),
    exerciseType: json['exerciseType'] as String,
    equipment: json['equipment'] as String,
    instructions: json['instructions'] as String,
  );

  ExerciseMuscleGroup _parseGroup(String value) => switch (value.toLowerCase()) {
    'chest' => ExerciseMuscleGroup.chest,
    'back' => ExerciseMuscleGroup.back,
    'shoulder' => ExerciseMuscleGroup.shoulder,
    'arms' => ExerciseMuscleGroup.arms,
    'legs' => ExerciseMuscleGroup.legs,
    'core' => ExerciseMuscleGroup.core,
    'cardio' => ExerciseMuscleGroup.cardio,
    _ => ExerciseMuscleGroup.all,
  };
}
