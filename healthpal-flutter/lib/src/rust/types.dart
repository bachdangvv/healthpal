class HeartRateSample {
  const HeartRateSample({
    required this.timestampUtc,
    required this.bpm,
    this.recordId,
    this.sourceId,
  });

  final DateTime timestampUtc;
  final double bpm;
  final String? recordId;
  final String? sourceId;

  Map<String, dynamic> toNativeJson() => {
    'timestamp_utc_ms': timestampUtc.toUtc().millisecondsSinceEpoch,
    'bpm': bpm,
    'record_id': recordId,
    'source_id': sourceId,
  };
}

class StepInterval {
  const StepInterval({
    required this.startUtc,
    required this.endUtc,
    required this.count,
    this.recordId,
    this.sourceId,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final double count;
  final String? recordId;
  final String? sourceId;

  Map<String, dynamic> toNativeJson() => {
    'start_utc_ms': startUtc.toUtc().millisecondsSinceEpoch,
    'end_utc_ms': endUtc.toUtc().millisecondsSinceEpoch,
    'count': count,
    'record_id': recordId,
    'source_id': sourceId,
  };
}

class RestingHrRecord {
  const RestingHrRecord({
    required this.recordedAtUtc,
    required this.bpm,
    this.localDate,
    this.recordId,
    this.sourceId,
  });

  final DateTime recordedAtUtc;
  final double bpm;
  final String? localDate;
  final String? recordId;
  final String? sourceId;

  Map<String, dynamic> toNativeJson() => {
    'recorded_at_utc_ms': recordedAtUtc.toUtc().millisecondsSinceEpoch,
    'bpm': bpm,
    'local_date': localDate,
    'record_id': recordId,
    'source_id': sourceId,
  };
}

class SleepStage {
  const SleepStage({
    required this.startUtc,
    required this.endUtc,
    required this.stageType,
    this.recordId,
    this.sourceId,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final String stageType;
  final String? recordId;
  final String? sourceId;

  Map<String, dynamic> toNativeJson() => {
    'start_utc_ms': startUtc.toUtc().millisecondsSinceEpoch,
    'end_utc_ms': endUtc.toUtc().millisecondsSinceEpoch,
    'stage_type': stageType,
    'record_id': recordId,
    'source_id': sourceId,
  };
}

class SleepSession {
  const SleepSession({
    required this.startUtc,
    required this.endUtc,
    this.recordId,
    this.healthDay,
    this.stages = const [],
    this.asleepMinutesAggregate,
    this.sourceId,
    this.modifiedAtUtc,
  });

  final String? recordId;
  final DateTime startUtc;
  final DateTime endUtc;
  final String? healthDay;
  final List<SleepStage> stages;
  final double? asleepMinutesAggregate;
  final String? sourceId;
  final DateTime? modifiedAtUtc;

  Map<String, dynamic> toNativeJson() => {
    'record_id': recordId,
    'start_utc_ms': startUtc.toUtc().millisecondsSinceEpoch,
    'end_utc_ms': endUtc.toUtc().millisecondsSinceEpoch,
    'health_day': healthDay,
    'stages': stages
        .map((stage) => stage.toNativeJson())
        .toList(growable: false),
    'asleep_minutes_aggregate': asleepMinutesAggregate,
    'source_id': sourceId,
    'modified_at_utc_ms': modifiedAtUtc?.toUtc().millisecondsSinceEpoch,
  };
}

class ExerciseSession {
  const ExerciseSession({
    required this.startUtc,
    required this.endUtc,
    this.exerciseType,
    this.recordId,
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final String? exerciseType;
  final String? recordId;

  Map<String, dynamic> toNativeJson() => {
    'start_utc_ms': startUtc.toUtc().millisecondsSinceEpoch,
    'end_utc_ms': endUtc.toUtc().millisecondsSinceEpoch,
    'exercise_type': exerciseType,
    'record_id': recordId,
  };
}

class AssessmentRequest {
  const AssessmentRequest({
    required this.evaluationTimeUtc,
    required this.timezoneOffsetMinutes,
    this.heartRateSamples = const [],
    this.stepIntervals = const [],
    this.restingHrRecords = const [],
    this.sleepSessions = const [],
    this.exerciseSessions = const [],
    this.dataWatermarkUtc,
    this.previousAssessmentWatermarkUtc,
    this.preferredSourceId,
    this.heartRatePermission,
    this.stepsPermission,
    this.sleepPermission,
    this.restingHrPermission,
  });

  final DateTime evaluationTimeUtc;
  final int timezoneOffsetMinutes;
  final List<HeartRateSample> heartRateSamples;
  final List<StepInterval> stepIntervals;
  final List<RestingHrRecord> restingHrRecords;
  final List<SleepSession> sleepSessions;
  final List<ExerciseSession> exerciseSessions;
  final DateTime? dataWatermarkUtc;
  final DateTime? previousAssessmentWatermarkUtc;
  final String? preferredSourceId;
  final bool? heartRatePermission;
  final bool? stepsPermission;
  final bool? sleepPermission;
  final bool? restingHrPermission;

  Map<String, dynamic> toNativeJson() => {
    'evaluation_time_utc_ms': evaluationTimeUtc.toUtc().millisecondsSinceEpoch,
    'timezone_offset_minutes': timezoneOffsetMinutes,
    'heart_rate_samples': heartRateSamples
        .map((sample) => sample.toNativeJson())
        .toList(growable: false),
    'step_intervals': stepIntervals
        .map((interval) => interval.toNativeJson())
        .toList(growable: false),
    'resting_hr_records': restingHrRecords
        .map((record) => record.toNativeJson())
        .toList(growable: false),
    'sleep_sessions': sleepSessions
        .map((session) => session.toNativeJson())
        .toList(growable: false),
    'exercise_sessions': exerciseSessions
        .map((session) => session.toNativeJson())
        .toList(growable: false),
    'data_watermark_utc_ms': dataWatermarkUtc?.toUtc().millisecondsSinceEpoch,
    'previous_assessment_watermark_utc_ms': previousAssessmentWatermarkUtc
        ?.toUtc()
        .millisecondsSinceEpoch,
    'preferred_source_id': preferredSourceId,
    'heart_rate_permission': heartRatePermission,
    'steps_permission': stepsPermission,
    'sleep_permission': sleepPermission,
    'resting_hr_permission': restingHrPermission,
  };
}

enum AssessmentStatus {
  signalDetected,
  noClearSignal,
  insufficientData,
  suppressedDuringExercise,
}

class FeatureSlot {
  const FeatureSlot({required this.name, this.value, this.missingReason});

  final String name;
  final double? value;
  final String? missingReason;

  factory FeatureSlot.fromNativeJson(Map<String, dynamic> json) => FeatureSlot(
    name: json['name'] as String,
    value: (json['value'] as num?)?.toDouble(),
    missingReason: json['missing_reason'] as String?,
  );
}

class AssessmentResult {
  const AssessmentResult({
    required this.status,
    required this.features,
    required this.missingReasons,
    this.baseProbability,
    this.calibratedProbability,
    required this.threshold,
    required this.coverageHours,
    required this.validBinCount,
    this.latestSampleAtUtc,
    this.dataFreshnessMinutes,
    required this.modelVersion,
    required this.featureVectorHash,
  });

  final AssessmentStatus status;
  final List<FeatureSlot> features;
  final List<String> missingReasons;
  final double? baseProbability;
  final double? calibratedProbability;
  final double threshold;
  final int coverageHours;
  final int validBinCount;
  final DateTime? latestSampleAtUtc;
  final int? dataFreshnessMinutes;
  final String modelVersion;
  final String featureVectorHash;

  factory AssessmentResult.fromNativeJson(Map<String, dynamic> json) =>
      AssessmentResult(
        status: AssessmentStatus.values.byName(json['status'] as String),
        features:
            ((json['features'] as List<dynamic>? ?? const [])
                    .cast<Map<String, dynamic>>())
                .map(FeatureSlot.fromNativeJson)
                .toList(growable: false),
        missingReasons: ((json['missing_reasons'] as List<dynamic>? ?? const [])
            .cast<String>()),
        baseProbability: (json['base_probability'] as num?)?.toDouble(),
        calibratedProbability: (json['calibrated_probability'] as num?)
            ?.toDouble(),
        threshold: (json['threshold'] as num).toDouble(),
        coverageHours: json['coverage_hours'] as int,
        validBinCount: json['valid_bin_count'] as int,
        latestSampleAtUtc: json['latest_sample_at_utc_ms'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                json['latest_sample_at_utc_ms'] as int,
                isUtc: true,
              ),
        dataFreshnessMinutes: json['data_freshness_minutes'] as int?,
        modelVersion: json['model_version'] as String,
        featureVectorHash: json['feature_vector_hash'] as String,
      );
}

class ModelInfo {
  const ModelInfo({
    required this.modelName,
    required this.modelVersion,
    required this.featureOrder,
    required this.windowHours,
    required this.threshold,
    required this.calibrationSlope,
    required this.calibrationIntercept,
    required this.lowActivityThreshold,
    required this.onnxArtifact,
  });

  final String modelName;
  final String modelVersion;
  final List<String> featureOrder;
  final int windowHours;
  final double threshold;
  final double calibrationSlope;
  final double calibrationIntercept;
  final int lowActivityThreshold;
  final String onnxArtifact;

  factory ModelInfo.fromNativeJson(Map<String, dynamic> json) => ModelInfo(
    modelName: json['model_name'] as String,
    modelVersion: json['model_version'] as String,
    featureOrder: (json['feature_order'] as List<dynamic>).cast<String>(),
    windowHours: json['window_hours'] as int,
    threshold: (json['threshold'] as num).toDouble(),
    calibrationSlope: (json['calibration_slope'] as num).toDouble(),
    calibrationIntercept: (json['calibration_intercept'] as num).toDouble(),
    lowActivityThreshold: json['low_activity_threshold'] as int,
    onnxArtifact: json['onnx_artifact'] as String,
  );
}

class AssessmentException implements Exception {
  const AssessmentException({
    required this.kind,
    required this.code,
    required this.message,
  });

  final String kind;
  final String code;
  final String message;

  factory AssessmentException.fromNativeJson(Map<String, dynamic> json) =>
      AssessmentException(
        kind: json['kind'] as String,
        code: json['code'] as String,
        message: json['message'] as String,
      );

  @override
  String toString() => 'AssessmentException($kind $code): $message';
}
