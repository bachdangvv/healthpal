import 'sleep_normalizer.dart';

class SourceInfo {
  const SourceInfo({required this.sourceId, required this.sourceName});

  final String sourceId;
  final String sourceName;

  factory SourceInfo.fromJson(Map<String, dynamic> json) => SourceInfo(
    sourceId: json['sourceId'] as String,
    sourceName: json['sourceName'] as String,
  );

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'sourceName': sourceName,
  };
}

class HeartRateSample {
  const HeartRateSample({
    required this.recordId,
    required this.startUtc,
    required this.endUtc,
    required this.zoneOffsetMinutes,
    required this.bpm,
    required this.source,
    this.modifiedAtUtc,
  });

  final String recordId;
  final DateTime startUtc;
  final DateTime endUtc;
  final int zoneOffsetMinutes;
  final double bpm;
  final SourceInfo source;
  final DateTime? modifiedAtUtc;

  bool get isPhysiologicallyPlausible => bpm > 20 && bpm < 260;

  factory HeartRateSample.fromJson(Map<String, dynamic> json) =>
      HeartRateSample(
        recordId: json['recordId'] as String,
        startUtc: DateTime.parse(json['startUtc'] as String),
        endUtc: DateTime.parse(json['endUtc'] as String),
        zoneOffsetMinutes: json['zoneOffsetMinutes'] as int,
        bpm: (json['bpm'] as num).toDouble(),
        source: SourceInfo.fromJson(json['source'] as Map<String, dynamic>),
        modifiedAtUtc: json['modifiedAtUtc'] == null
            ? null
            : DateTime.parse(json['modifiedAtUtc'] as String),
      );

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'startUtc': startUtc.toUtc().toIso8601String(),
    'endUtc': endUtc.toUtc().toIso8601String(),
    'zoneOffsetMinutes': zoneOffsetMinutes,
    'bpm': bpm,
    'source': source.toJson(),
    'modifiedAtUtc': modifiedAtUtc?.toUtc().toIso8601String(),
  };
}

class StepInterval {
  const StepInterval({
    required this.recordId,
    required this.startUtc,
    required this.endUtc,
    required this.zoneOffsetMinutes,
    required this.count,
    required this.source,
    this.modifiedAtUtc,
  });

  final String recordId;
  final DateTime startUtc;
  final DateTime endUtc;
  final int zoneOffsetMinutes;
  final int count;
  final SourceInfo source;
  final DateTime? modifiedAtUtc;

  factory StepInterval.fromJson(Map<String, dynamic> json) => StepInterval(
    recordId: json['recordId'] as String,
    startUtc: DateTime.parse(json['startUtc'] as String),
    endUtc: DateTime.parse(json['endUtc'] as String),
    zoneOffsetMinutes: json['zoneOffsetMinutes'] as int,
    count: json['count'] as int,
    source: SourceInfo.fromJson(json['source'] as Map<String, dynamic>),
    modifiedAtUtc: json['modifiedAtUtc'] == null
        ? null
        : DateTime.parse(json['modifiedAtUtc'] as String),
  );

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'startUtc': startUtc.toUtc().toIso8601String(),
    'endUtc': endUtc.toUtc().toIso8601String(),
    'zoneOffsetMinutes': zoneOffsetMinutes,
    'count': count,
    'source': source.toJson(),
    'modifiedAtUtc': modifiedAtUtc?.toUtc().toIso8601String(),
  };
}

class RestingHeartRateRecord {
  const RestingHeartRateRecord({
    required this.recordId,
    required this.recordedAtUtc,
    required this.zoneOffsetMinutes,
    required this.localDate,
    required this.bpm,
    required this.source,
    this.modifiedAtUtc,
  });

  final String recordId;
  final DateTime recordedAtUtc;
  final int zoneOffsetMinutes;
  final DateTime localDate;
  final double bpm;
  final SourceInfo source;
  final DateTime? modifiedAtUtc;

  factory RestingHeartRateRecord.fromJson(Map<String, dynamic> json) =>
      RestingHeartRateRecord(
        recordId: json['recordId'] as String,
        recordedAtUtc: DateTime.parse(json['recordedAtUtc'] as String),
        zoneOffsetMinutes: json['zoneOffsetMinutes'] as int,
        localDate: DateTime.parse(json['localDate'] as String),
        bpm: (json['bpm'] as num).toDouble(),
        source: SourceInfo.fromJson(json['source'] as Map<String, dynamic>),
        modifiedAtUtc: json['modifiedAtUtc'] == null
            ? null
            : DateTime.parse(json['modifiedAtUtc'] as String),
      );

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'recordedAtUtc': recordedAtUtc.toUtc().toIso8601String(),
    'zoneOffsetMinutes': zoneOffsetMinutes,
    'localDate': _dateOnly(localDate),
    'bpm': bpm,
    'source': source.toJson(),
    'modifiedAtUtc': modifiedAtUtc?.toUtc().toIso8601String(),
  };
}

enum SleepStageType { awake, light, deep, rem, asleep, unknown }

class SleepStage {
  const SleepStage({
    this.recordId = '',
    required this.startUtc,
    required this.endUtc,
    required this.type,
    this.source,
    this.modifiedAtUtc,
  });

  final String recordId;
  final DateTime startUtc;
  final DateTime endUtc;
  final SleepStageType type;
  final SourceInfo? source;
  final DateTime? modifiedAtUtc;

  int get durationMinutes => endUtc.difference(startUtc).inMinutes;

  bool get isAsleep =>
      type == SleepStageType.asleep ||
      type == SleepStageType.light ||
      type == SleepStageType.deep ||
      type == SleepStageType.rem;

  factory SleepStage.fromJson(Map<String, dynamic> json) => SleepStage(
    recordId: json['recordId'] as String? ?? '',
    startUtc: DateTime.parse(json['startUtc'] as String),
    endUtc: DateTime.parse(json['endUtc'] as String),
    type: SleepStageType.values.byName(json['type'] as String),
    source: json['source'] == null
        ? null
        : SourceInfo.fromJson(json['source'] as Map<String, dynamic>),
    modifiedAtUtc: json['modifiedAtUtc'] == null
        ? null
        : DateTime.parse(json['modifiedAtUtc'] as String),
  );

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'startUtc': startUtc.toUtc().toIso8601String(),
    'endUtc': endUtc.toUtc().toIso8601String(),
    'type': type.name,
    'source': source?.toJson(),
    'modifiedAtUtc': modifiedAtUtc?.toUtc().toIso8601String(),
  };
}

class SleepSession {
  const SleepSession({
    required this.recordId,
    required this.startUtc,
    required this.endUtc,
    required this.zoneOffsetMinutes,
    required this.healthDay,
    this.stages = const [],
    this.asleepMinutesAggregate,
    required this.source,
    this.modifiedAtUtc,
  });

  final String recordId;
  final DateTime startUtc;
  final DateTime endUtc;
  final int zoneOffsetMinutes;
  final DateTime healthDay;
  final List<SleepStage> stages;
  final int? asleepMinutesAggregate;
  final SourceInfo source;
  final DateTime? modifiedAtUtc;

  bool get hasStageCoverage => stages.any((stage) => stage.isAsleep);

  int get sleepMinutes =>
      const SleepStageNormalizer().normalize(this).asleepMinutes;

  factory SleepSession.fromJson(Map<String, dynamic> json) => SleepSession(
    recordId: json['recordId'] as String,
    startUtc: DateTime.parse(json['startUtc'] as String),
    endUtc: DateTime.parse(json['endUtc'] as String),
    zoneOffsetMinutes: json['zoneOffsetMinutes'] as int,
    healthDay: DateTime.parse(json['healthDay'] as String),
    stages: (json['stages'] as List<dynamic>? ?? const [])
        .map((item) => SleepStage.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    asleepMinutesAggregate: json['asleepMinutesAggregate'] as int?,
    source: SourceInfo.fromJson(json['source'] as Map<String, dynamic>),
    modifiedAtUtc: json['modifiedAtUtc'] == null
        ? null
        : DateTime.parse(json['modifiedAtUtc'] as String),
  );

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'startUtc': startUtc.toUtc().toIso8601String(),
    'endUtc': endUtc.toUtc().toIso8601String(),
    'zoneOffsetMinutes': zoneOffsetMinutes,
    'healthDay': _dateOnly(healthDay),
    'stages': stages.map((stage) => stage.toJson()).toList(growable: false),
    'asleepMinutesAggregate': asleepMinutesAggregate,
    'source': source.toJson(),
    'modifiedAtUtc': modifiedAtUtc?.toUtc().toIso8601String(),
  };
}

class ExerciseSession {
  const ExerciseSession({
    required this.recordId,
    required this.startUtc,
    required this.endUtc,
    required this.zoneOffsetMinutes,
    required this.type,
    this.title,
    required this.durationMinutes,
    this.calories,
    required this.source,
    this.modifiedAtUtc,
  });

  final String recordId;
  final DateTime startUtc;
  final DateTime endUtc;
  final int zoneOffsetMinutes;
  final String type;
  final String? title;
  final int durationMinutes;
  final double? calories;
  final SourceInfo source;
  final DateTime? modifiedAtUtc;

  factory ExerciseSession.fromJson(Map<String, dynamic> json) =>
      ExerciseSession(
        recordId: json['recordId'] as String,
        startUtc: DateTime.parse(json['startUtc'] as String),
        endUtc: DateTime.parse(json['endUtc'] as String),
        zoneOffsetMinutes: json['zoneOffsetMinutes'] as int,
        type: json['type'] as String,
        title: json['title'] as String?,
        durationMinutes: json['durationMinutes'] as int,
        calories: (json['calories'] as num?)?.toDouble(),
        source: SourceInfo.fromJson(json['source'] as Map<String, dynamic>),
        modifiedAtUtc: json['modifiedAtUtc'] == null
            ? null
            : DateTime.parse(json['modifiedAtUtc'] as String),
      );

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'startUtc': startUtc.toUtc().toIso8601String(),
    'endUtc': endUtc.toUtc().toIso8601String(),
    'zoneOffsetMinutes': zoneOffsetMinutes,
    'type': type,
    'title': title,
    'durationMinutes': durationMinutes,
    'calories': calories,
    'source': source.toJson(),
    'modifiedAtUtc': modifiedAtUtc?.toUtc().toIso8601String(),
  };
}

class ActiveCaloriesInterval {
  const ActiveCaloriesInterval({
    required this.recordId,
    required this.startUtc,
    required this.endUtc,
    required this.zoneOffsetMinutes,
    required this.kilocalories,
    required this.source,
    this.modifiedAtUtc,
  });

  final String recordId;
  final DateTime startUtc;
  final DateTime endUtc;
  final int zoneOffsetMinutes;
  final double kilocalories;
  final SourceInfo source;
  final DateTime? modifiedAtUtc;

  factory ActiveCaloriesInterval.fromJson(Map<String, dynamic> json) =>
      ActiveCaloriesInterval(
        recordId: json['recordId'] as String,
        startUtc: DateTime.parse(json['startUtc'] as String),
        endUtc: DateTime.parse(json['endUtc'] as String),
        zoneOffsetMinutes: json['zoneOffsetMinutes'] as int,
        kilocalories: (json['kilocalories'] as num).toDouble(),
        source: SourceInfo.fromJson(json['source'] as Map<String, dynamic>),
        modifiedAtUtc: json['modifiedAtUtc'] == null
            ? null
            : DateTime.parse(json['modifiedAtUtc'] as String),
      );

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'startUtc': startUtc.toUtc().toIso8601String(),
    'endUtc': endUtc.toUtc().toIso8601String(),
    'zoneOffsetMinutes': zoneOffsetMinutes,
    'kilocalories': kilocalories,
    'source': source.toJson(),
    'modifiedAtUtc': modifiedAtUtc?.toUtc().toIso8601String(),
  };
}

enum HealthPermission {
  steps,
  sleep,
  heartRate,
  restingHeartRate,
  activeCalories,
  exercise,
  heartRateVariability,
  healthDataInBackground,
}

class HealthConnectCapabilities {
  const HealthConnectCapabilities({
    required this.sdkAvailable,
    this.backgroundReadSupported = false,
    this.backgroundReadGranted = false,
  });

  final bool sdkAvailable;
  final bool backgroundReadSupported;
  final bool backgroundReadGranted;
}

class PermissionSnapshot {
  const PermissionSnapshot({required this.granted, required this.missing});

  final Set<HealthPermission> granted;
  final Set<HealthPermission> missing;

  static const v4Required = <HealthPermission>{
    HealthPermission.heartRate,
    HealthPermission.steps,
    HealthPermission.sleep,
    HealthPermission.restingHeartRate,
  };

  static const analyticsRequired = <HealthPermission>{
    HealthPermission.exercise,
    HealthPermission.activeCalories,
  };

  static const optionalReads = <HealthPermission>{
    HealthPermission.heartRateVariability,
  };

  bool get hasAllForegroundReads => v4Required.every(granted.contains);

  bool get hasAnalyticsReads => analyticsRequired.every(granted.contains);

  Set<HealthPermission> get missingRequired =>
      missing.intersection(v4Required.union(analyticsRequired));

  factory PermissionSnapshot.fromJson(Map<String, dynamic> json) {
    Set<HealthPermission> parse(String key) =>
        ((json[key] as List<dynamic>?) ?? const [])
            .map((name) => HealthPermission.values.byName(name as String))
            .toSet();
    return PermissionSnapshot(
      granted: parse('granted'),
      missing: parse('missing'),
    );
  }

  Map<String, dynamic> toJson() => {
    'granted': granted.map((item) => item.name).toList(growable: false),
    'missing': missing.map((item) => item.name).toList(growable: false),
  };
}

class IngestionBatch {
  const IngestionBatch({
    required this.startUtc,
    required this.endUtc,
    this.heartRateSamples = const [],
    this.stepIntervals = const [],
    this.restingHeartRateRecords = const [],
    this.sleepSessions = const [],
    this.exerciseSessions = const [],
    this.activeCaloriesIntervals = const [],
  });

  final DateTime startUtc;
  final DateTime endUtc;
  final List<HeartRateSample> heartRateSamples;
  final List<StepInterval> stepIntervals;
  final List<RestingHeartRateRecord> restingHeartRateRecords;
  final List<SleepSession> sleepSessions;
  final List<ExerciseSession> exerciseSessions;
  final List<ActiveCaloriesInterval> activeCaloriesIntervals;

  bool get isEmpty =>
      heartRateSamples.isEmpty &&
      stepIntervals.isEmpty &&
      restingHeartRateRecords.isEmpty &&
      sleepSessions.isEmpty &&
      exerciseSessions.isEmpty &&
      activeCaloriesIntervals.isEmpty;

  factory IngestionBatch.fromJson(Map<String, dynamic> json) => IngestionBatch(
    startUtc: DateTime.parse(json['startUtc'] as String),
    endUtc: DateTime.parse(json['endUtc'] as String),
    heartRateSamples: _mapList(
      json['heartRateSamples'],
      HeartRateSample.fromJson,
    ),
    stepIntervals: _mapList(json['stepIntervals'], StepInterval.fromJson),
    restingHeartRateRecords: _mapList(
      json['restingHeartRateRecords'],
      RestingHeartRateRecord.fromJson,
    ),
    sleepSessions: _mapList(json['sleepSessions'], SleepSession.fromJson),
    exerciseSessions: _mapList(
      json['exerciseSessions'],
      ExerciseSession.fromJson,
    ),
    activeCaloriesIntervals: _mapList(
      json['activeCaloriesIntervals'],
      ActiveCaloriesInterval.fromJson,
    ),
  );

  Map<String, dynamic> toJson() => {
    'startUtc': startUtc.toUtc().toIso8601String(),
    'endUtc': endUtc.toUtc().toIso8601String(),
    'heartRateSamples': heartRateSamples
        .map((item) => item.toJson())
        .toList(growable: false),
    'stepIntervals': stepIntervals
        .map((item) => item.toJson())
        .toList(growable: false),
    'restingHeartRateRecords': restingHeartRateRecords
        .map((item) => item.toJson())
        .toList(growable: false),
    'sleepSessions': sleepSessions
        .map((item) => item.toJson())
        .toList(growable: false),
    'exerciseSessions': exerciseSessions
        .map((item) => item.toJson())
        .toList(growable: false),
    'activeCaloriesIntervals': activeCaloriesIntervals
        .map((item) => item.toJson())
        .toList(growable: false),
  };
}

List<T> _mapList<T>(Object? raw, T Function(Map<String, dynamic> json) parse) {
  return ((raw as List<dynamic>?) ?? const [])
      .map((item) => parse(item as Map<String, dynamic>))
      .toList(growable: false);
}

String _dateOnly(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
