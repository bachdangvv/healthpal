enum FatigueAssessmentStatus {
  signalDetected,
  noClearSignal,
  insufficientData,
  suppressedDuringExercise,
}

enum AssessmentCreatedBy { foreground, background }

/// Production fatigue result. UI copy must stay experimental and non-clinical.
class FatigueAssessment {
  const FatigueAssessment({
    required this.id,
    required this.evaluatedAtUtc,
    required this.localDate,
    required this.modelVersion,
    this.baseProbability,
    this.calibratedProbability,
    required this.threshold,
    required this.status,
    required this.coverageHours,
    this.latestSampleAtUtc,
    this.dataFreshnessMinutes,
    this.missingReasons = const [],
    required this.featureVectorHash,
    required this.createdBy,
  });

  final String id;
  final DateTime evaluatedAtUtc;
  final DateTime localDate;
  final String modelVersion;
  final double? baseProbability;
  final double? calibratedProbability;
  final double threshold;
  final FatigueAssessmentStatus status;
  final int coverageHours;
  final DateTime? latestSampleAtUtc;
  final int? dataFreshnessMinutes;
  final List<String> missingReasons;
  final String featureVectorHash;
  final AssessmentCreatedBy createdBy;

  String get statusLabel => switch (status) {
    FatigueAssessmentStatus.signalDetected => 'Có dấu hiệu mệt mỏi',
    FatigueAssessmentStatus.noClearSignal => 'Chưa thấy tín hiệu mệt mỏi',
    FatigueAssessmentStatus.insufficientData => 'Chưa đủ dữ liệu',
    FatigueAssessmentStatus.suppressedDuringExercise =>
      'Tạm hoãn vì đang hoặc vừa tập luyện',
  };

  factory FatigueAssessment.fromJson(Map<String, dynamic> json) {
    return FatigueAssessment(
      id: json['id'] as String,
      evaluatedAtUtc: DateTime.parse(json['evaluatedAtUtc'] as String),
      localDate: DateTime.parse(json['localDate'] as String),
      modelVersion: json['modelVersion'] as String,
      baseProbability: (json['baseProbability'] as num?)?.toDouble(),
      calibratedProbability: (json['calibratedProbability'] as num?)
          ?.toDouble(),
      threshold: (json['threshold'] as num).toDouble(),
      status: FatigueAssessmentStatus.values.byName(json['status'] as String),
      coverageHours: json['coverageHours'] as int,
      latestSampleAtUtc: json['latestSampleAtUtc'] == null
          ? null
          : DateTime.parse(json['latestSampleAtUtc'] as String),
      dataFreshnessMinutes: json['dataFreshnessMinutes'] as int?,
      missingReasons: (json['missingReasons'] as List<dynamic>? ?? const [])
          .cast<String>(),
      featureVectorHash: json['featureVectorHash'] as String,
      createdBy: AssessmentCreatedBy.values.byName(json['createdBy'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'evaluatedAtUtc': evaluatedAtUtc.toUtc().toIso8601String(),
    'localDate': _dateOnly(localDate),
    'modelVersion': modelVersion,
    'baseProbability': baseProbability,
    'calibratedProbability': calibratedProbability,
    'threshold': threshold,
    'status': status.name,
    'coverageHours': coverageHours,
    'latestSampleAtUtc': latestSampleAtUtc?.toUtc().toIso8601String(),
    'dataFreshnessMinutes': dataFreshnessMinutes,
    'missingReasons': missingReasons,
    'featureVectorHash': featureVectorHash,
    'createdBy': createdBy.name,
  };
}

class FatigueDailyValue {
  const FatigueDailyValue({
    required this.probability,
    required this.threshold,
    required this.status,
    required this.evaluatedAtUtc,
  });

  final double? probability;
  final double threshold;
  final FatigueAssessmentStatus status;
  final DateTime evaluatedAtUtc;

  factory FatigueDailyValue.fromJson(Map<String, dynamic> json) {
    return FatigueDailyValue(
      probability: (json['probability'] as num?)?.toDouble(),
      threshold: (json['threshold'] as num).toDouble(),
      status: FatigueAssessmentStatus.values.byName(json['status'] as String),
      evaluatedAtUtc: DateTime.parse(json['evaluatedAtUtc'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'probability': probability,
    'threshold': threshold,
    'status': status.name,
    'evaluatedAtUtc': evaluatedAtUtc.toUtc().toIso8601String(),
  };
}

String _dateOnly(DateTime value) {
  final local = DateTime(value.year, value.month, value.day);
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
