import '../../../core/api/api_client.dart';
import '../domain/stress_level.dart';
import '../domain/training_models.dart';
import 'training_readiness_repository.dart';

class ApiTrainingReadinessRepository implements TrainingReadinessRepository {
  ApiTrainingReadinessRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<TrainingReadinessInput> fetchInput() async {
    final date = DateTime.now();
    final localDate =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final response = await _client.raw.get<Map<String, dynamic>>(
      '/api/v1/training/readiness',
      queryParameters: {'localDate': localDate},
    );
    final json = response.data!;
    return TrainingReadinessInput(
      stress: _parseStress(json['stress'] as String?),
      sleepMinutes: json['sleepMinutes'] as int?,
      steps: json['steps'] as int?,
      activeCalories: (json['activeCalories'] as num?)?.toDouble(),
      collectedAt: DateTime.parse(json['collectedAtUtc'] as String).toLocal(),
    );
  }

  StressLevel? _parseStress(String? value) => switch (value?.toLowerCase()) {
    'low' => StressLevel.low,
    'medium' => StressLevel.medium,
    'high' => StressLevel.high,
    _ => null,
  };
}
