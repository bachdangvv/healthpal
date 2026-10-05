import 'stress_level.dart';

export 'stress_level.dart';

enum TrainingReadinessStatus {
  ready,
  moderate,
  recovery,
  rest,
  insufficientData,
}

enum ExerciseMuscleGroup {
  all,
  chest,
  back,
  shoulder,
  arms,
  legs,
  core,
  cardio,
}

extension TrainingReadinessStatusPresentation on TrainingReadinessStatus {
  String get label => switch (this) {
    TrainingReadinessStatus.ready => 'Sẵn sàng tốt',
    TrainingReadinessStatus.moderate => 'Nên tập vừa',
    TrainingReadinessStatus.recovery => 'Nên phục hồi',
    TrainingReadinessStatus.rest => 'Nên nghỉ',
    TrainingReadinessStatus.insufficientData => 'Chưa đủ dữ liệu',
  };

  String get suggestion => switch (this) {
    TrainingReadinessStatus.ready => 'Có thể tập theo kế hoạch bình thường.',
    TrainingReadinessStatus.moderate =>
      'Giảm cường độ hoặc volume, ưu tiên buổi tập vừa.',
    TrainingReadinessStatus.recovery =>
      'Ưu tiên đi bộ, mobility, stretching hoặc cardio nhẹ.',
    TrainingReadinessStatus.rest => 'Ưu tiên nghỉ ngơi và phục hồi hôm nay.',
    TrainingReadinessStatus.insufficientData =>
      'Chưa đưa ra kết luận khi còn thiếu dữ liệu cốt lõi.',
  };
}

extension ExerciseMuscleGroupPresentation on ExerciseMuscleGroup {
  String get label => switch (this) {
    ExerciseMuscleGroup.all => 'Tất cả',
    ExerciseMuscleGroup.chest => 'Chest',
    ExerciseMuscleGroup.back => 'Back',
    ExerciseMuscleGroup.shoulder => 'Shoulder',
    ExerciseMuscleGroup.arms => 'Arms',
    ExerciseMuscleGroup.legs => 'Legs',
    ExerciseMuscleGroup.core => 'Core',
    ExerciseMuscleGroup.cardio => 'Cardio',
  };
}

extension TrainingStressLevelPresentation on StressLevel {
  String get label => switch (this) {
    StressLevel.low => 'Thấp',
    StressLevel.medium => 'Trung bình',
    StressLevel.high => 'Cao',
  };
}

class TrainingReadinessInput {
  const TrainingReadinessInput({
    this.stress,
    this.sleepMinutes,
    this.steps,
    this.activeCalories,
    required this.collectedAt,
  });

  final StressLevel? stress;
  final int? sleepMinutes;
  final int? steps;
  final double? activeCalories;
  final DateTime collectedAt;
}

class TrainingReadinessResult {
  const TrainingReadinessResult({
    required this.status,
    required this.input,
    this.movementAdjusted = false,
  });

  final TrainingReadinessStatus status;
  final TrainingReadinessInput input;
  final bool movementAdjusted;

  String get label => status.label;
  String get suggestion => status.suggestion;
}

class StressAssessmentInput {
  const StressAssessmentInput({
    this.steps,
    this.sleepMinutes,
    this.activeCalories,
    required this.collectedAt,
  });

  final int? steps;
  final int? sleepMinutes;
  final double? activeCalories;
  final DateTime collectedAt;
}

class StressAssessmentResult {
  const StressAssessmentResult({this.level, this.available = false});

  final StressLevel? level;
  final bool available;
}

abstract interface class StressAssessmentService {
  Future<StressAssessmentResult> assess(StressAssessmentInput input);
}

class UnavailableStressAssessmentService implements StressAssessmentService {
  const UnavailableStressAssessmentService();

  @override
  Future<StressAssessmentResult> assess(StressAssessmentInput input) async =>
      const StressAssessmentResult();
}

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    this.englishName,
    required this.muscleGroup,
    required this.exerciseType,
    required this.equipment,
    required this.instructions,
  });

  final String id;
  final String name;
  final String? englishName;
  final ExerciseMuscleGroup muscleGroup;
  final String exerciseType;
  final String equipment;
  final String instructions;
}
