import '../../config/app_config.dart';
import '../../../features/assessment/domain/fatigue_assessment.dart';

/// Wire DTOs independent of widget/view models. Keep field names aligned with
/// the backend OpenAPI snapshot. New batches emit `schemaVersion = 2` with a
/// replacement window; pending schema v1 outbox payloads still deserialize.
class AuthUserDto {
  const AuthUserDto({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory AuthUserDto.fromJson(Map<String, dynamic> json) => AuthUserDto(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

class TokenPairDto {
  const TokenPairDto({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAtUtc,
    required this.refreshExpiresAtUtc,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAtUtc;
  final DateTime refreshExpiresAtUtc;

  factory TokenPairDto.fromJson(Map<String, dynamic> json) => TokenPairDto(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    accessExpiresAtUtc: DateTime.parse(json['accessExpiresAtUtc'] as String),
    refreshExpiresAtUtc: DateTime.parse(json['refreshExpiresAtUtc'] as String),
  );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'accessExpiresAtUtc': accessExpiresAtUtc.toUtc().toIso8601String(),
    'refreshExpiresAtUtc': refreshExpiresAtUtc.toUtc().toIso8601String(),
  };
}

class AuthSessionDto {
  const AuthSessionDto({required this.user, required this.tokens});

  final AuthUserDto user;
  final TokenPairDto tokens;

  factory AuthSessionDto.fromJson(Map<String, dynamic> json) => AuthSessionDto(
    user: AuthUserDto.fromJson(json['user'] as Map<String, dynamic>),
    tokens: TokenPairDto.fromJson(json['tokens'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'tokens': tokens.toJson(),
  };
}

class ProfileDto {
  const ProfileDto({
    required this.userId,
    required this.displayName,
    this.email,
    this.birthDate,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.goal,
    this.dailyStepGoal = 8000,
    this.timezone,
    this.preferredSourceId,
    this.rowVersion,
    this.experimentalFatigueConsent = false,
  });

  final String userId;
  final String displayName;
  final String? email;
  final DateTime? birthDate;
  final String? gender;
  final double? heightCm;
  final double? weightKg;
  final String? goal;
  final int dailyStepGoal;
  final String? timezone;
  final String? preferredSourceId;
  final String? rowVersion;
  final bool experimentalFatigueConsent;

  factory ProfileDto.fromJson(Map<String, dynamic> json) => ProfileDto(
    userId: json['userId'] as String,
    displayName: json['displayName'] as String,
    email: json['email'] as String?,
    birthDate: json['birthDate'] == null
        ? null
        : DateTime.parse(json['birthDate'] as String),
    gender: json['gender'] as String?,
    heightCm: (json['heightCm'] as num?)?.toDouble(),
    weightKg: (json['weightKg'] as num?)?.toDouble(),
    goal: json['goal'] as String?,
    dailyStepGoal: json['dailyStepGoal'] as int? ?? 8000,
    timezone: json['timezone'] as String?,
    preferredSourceId: json['preferredSourceId'] as String?,
    rowVersion: json['rowVersion'] as String?,
    experimentalFatigueConsent:
        json['experimentalFatigueConsent'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'email': email,
    'birthDate': birthDate == null
        ? null
        : '${birthDate!.year.toString().padLeft(4, '0')}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}',
    'gender': gender,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'goal': goal,
    'dailyStepGoal': dailyStepGoal,
    'timezone': timezone,
    'preferredSourceId': preferredSourceId,
    'rowVersion': rowVersion,
    'experimentalFatigueConsent': experimentalFatigueConsent,
  };
}

class HourlyHealthBinDto {
  const HourlyHealthBinDto({
    required this.hourUtc,
    required this.zoneOffsetMinutes,
    this.hrMean,
    this.hrMin,
    this.hrMax,
    this.hrSampleCount = 0,
    this.steps,
    this.activeCalories,
    required this.sourceId,
  });

  final DateTime hourUtc;
  final int zoneOffsetMinutes;
  final double? hrMean;
  final double? hrMin;
  final double? hrMax;
  final int hrSampleCount;
  final int? steps;
  final double? activeCalories;
  final String sourceId;

  factory HourlyHealthBinDto.fromJson(Map<String, dynamic> json) =>
      HourlyHealthBinDto(
        hourUtc: DateTime.parse(json['hourUtc'] as String),
        zoneOffsetMinutes: json['zoneOffsetMinutes'] as int,
        hrMean: (json['hrMean'] as num?)?.toDouble(),
        hrMin: (json['hrMin'] as num?)?.toDouble(),
        hrMax: (json['hrMax'] as num?)?.toDouble(),
        hrSampleCount: json['hrSampleCount'] as int? ?? 0,
        steps: json['steps'] as int?,
        activeCalories: (json['activeCalories'] as num?)?.toDouble(),
        sourceId: json['sourceId'] as String,
      );

  Map<String, dynamic> toJson() => {
    'hourUtc': hourUtc.toUtc().toIso8601String(),
    'zoneOffsetMinutes': zoneOffsetMinutes,
    'hrMean': hrMean,
    'hrMin': hrMin,
    'hrMax': hrMax,
    'hrSampleCount': hrSampleCount,
    'steps': steps,
    'activeCalories': activeCalories,
    'sourceId': sourceId,
  };
}

class DailyHealthSummaryDto {
  const DailyHealthSummaryDto({
    required this.localDate,
    required this.timezone,
    this.sleepMinutes,
    this.steps,
    this.averageHeartRate,
    this.minHeartRate,
    this.maxHeartRate,
    this.restingHeartRate,
    this.activeCalories,
    this.exerciseCount = 0,
    this.exerciseDurationMinutes = 0,
    this.coverageFlags = const {},
    this.fatigue,
  });

  final DateTime localDate;
  final String timezone;
  final int? sleepMinutes;
  final int? steps;
  final double? averageHeartRate;
  final double? minHeartRate;
  final double? maxHeartRate;
  final double? restingHeartRate;
  final double? activeCalories;
  final int exerciseCount;
  final int exerciseDurationMinutes;
  final Map<String, bool> coverageFlags;
  final FatigueDailyValue? fatigue;

  factory DailyHealthSummaryDto.fromJson(Map<String, dynamic> json) =>
      DailyHealthSummaryDto(
        localDate: DateTime.parse(json['localDate'] as String),
        timezone: json['timezone'] as String,
        sleepMinutes: json['sleepMinutes'] as int?,
        steps: json['steps'] as int?,
        averageHeartRate: (json['averageHeartRate'] as num?)?.toDouble(),
        minHeartRate: (json['minHeartRate'] as num?)?.toDouble(),
        maxHeartRate: (json['maxHeartRate'] as num?)?.toDouble(),
        restingHeartRate: (json['restingHeartRate'] as num?)?.toDouble(),
        activeCalories: (json['activeCalories'] as num?)?.toDouble(),
        exerciseCount: json['exerciseCount'] as int? ?? 0,
        exerciseDurationMinutes: json['exerciseDurationMinutes'] as int? ?? 0,
        coverageFlags: Map<String, bool>.from(
          (json['coverageFlags'] as Map?)?.map(
                (key, value) => MapEntry(key as String, value as bool),
              ) ??
              const {},
        ),
        fatigue: json['fatigue'] == null
            ? null
            : FatigueDailyValue.fromJson(
                json['fatigue'] as Map<String, dynamic>,
              ),
      );

  Map<String, dynamic> toJson() => {
    'localDate':
        '${localDate.year.toString().padLeft(4, '0')}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}',
    'timezone': timezone,
    'sleepMinutes': sleepMinutes,
    'steps': steps,
    'averageHeartRate': averageHeartRate,
    'minHeartRate': minHeartRate,
    'maxHeartRate': maxHeartRate,
    'restingHeartRate': restingHeartRate,
    'activeCalories': activeCalories,
    'exerciseCount': exerciseCount,
    'exerciseDurationMinutes': exerciseDurationMinutes,
    'coverageFlags': coverageFlags,
    'fatigue': fatigue?.toJson(),
  };
}

class ExerciseSessionDto {
  const ExerciseSessionDto({
    required this.externalRecordId,
    required this.type,
    required this.startUtc,
    required this.endUtc,
    required this.zoneOffsetMinutes,
    required this.durationMinutes,
    this.calories,
    required this.sourceId,
  });

  final String externalRecordId;
  final String type;
  final DateTime startUtc;
  final DateTime endUtc;
  final int zoneOffsetMinutes;
  final int durationMinutes;
  final double? calories;
  final String sourceId;

  factory ExerciseSessionDto.fromJson(Map<String, dynamic> json) =>
      ExerciseSessionDto(
        externalRecordId: json['externalRecordId'] as String,
        type: json['type'] as String,
        startUtc: DateTime.parse(json['startUtc'] as String),
        endUtc: DateTime.parse(json['endUtc'] as String),
        zoneOffsetMinutes: json['zoneOffsetMinutes'] as int,
        durationMinutes: json['durationMinutes'] as int,
        calories: (json['calories'] as num?)?.toDouble(),
        sourceId: json['sourceId'] as String,
      );

  Map<String, dynamic> toJson() => {
    'externalRecordId': externalRecordId,
    'type': type,
    'startUtc': startUtc.toUtc().toIso8601String(),
    'endUtc': endUtc.toUtc().toIso8601String(),
    'zoneOffsetMinutes': zoneOffsetMinutes,
    'durationMinutes': durationMinutes,
    'calories': calories,
    'sourceId': sourceId,
  };
}

class FatigueAssessmentDto {
  const FatigueAssessmentDto({required this.assessment});

  final FatigueAssessment assessment;

  factory FatigueAssessmentDto.fromJson(Map<String, dynamic> json) =>
      FatigueAssessmentDto(assessment: FatigueAssessment.fromJson(json));

  Map<String, dynamic> toJson() => assessment.toJson();
}

class ReplacementWindowDto {
  const ReplacementWindowDto({
    required this.startUtc,
    required this.endUtcExclusive,
    required this.localDateStart,
    required this.localDateEndExclusive,
  });

  final DateTime startUtc;
  final DateTime endUtcExclusive;
  final DateTime localDateStart;
  final DateTime localDateEndExclusive;

  factory ReplacementWindowDto.fromJson(Map<String, dynamic> json) =>
      ReplacementWindowDto(
        startUtc: DateTime.parse(json['startUtc'] as String).toUtc(),
        endUtcExclusive: DateTime.parse(
          json['endUtcExclusive'] as String,
        ).toUtc(),
        localDateStart: DateTime.parse(json['localDateStart'] as String),
        localDateEndExclusive: DateTime.parse(
          json['localDateEndExclusive'] as String,
        ),
      );

  Map<String, dynamic> toJson() => {
    'startUtc': startUtc.toUtc().toIso8601String(),
    'endUtcExclusive': endUtcExclusive.toUtc().toIso8601String(),
    'localDateStart': _dateOnly(localDateStart),
    'localDateEndExclusive': _dateOnly(localDateEndExclusive),
  };

  static String _dateOnly(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class SyncBatchDto {
  const SyncBatchDto({
    this.schemaVersion = AppConfig.syncSchemaVersion,
    required this.deviceId,
    required this.idempotencyKey,
    required this.generatedAtUtc,
    this.hourlyBins = const [],
    this.dailySummaries = const [],
    this.exerciseSessions = const [],
    this.fatigueAssessments = const [],
    this.replacementWindow,
  });

  final int schemaVersion;
  final String deviceId;
  final String idempotencyKey;
  final DateTime generatedAtUtc;
  final List<HourlyHealthBinDto> hourlyBins;
  final List<DailyHealthSummaryDto> dailySummaries;
  final List<ExerciseSessionDto> exerciseSessions;
  final List<FatigueAssessmentDto> fatigueAssessments;
  final ReplacementWindowDto? replacementWindow;

  factory SyncBatchDto.fromJson(Map<String, dynamic> json) => SyncBatchDto(
    schemaVersion: json['schemaVersion'] as int? ?? 1,
    deviceId: json['deviceId'] as String,
    idempotencyKey: json['idempotencyKey'] as String,
    generatedAtUtc: DateTime.parse(json['generatedAtUtc'] as String),
    hourlyBins: ((json['hourlyBins'] as List<dynamic>?) ?? const [])
        .map(
          (item) => HourlyHealthBinDto.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false),
    dailySummaries: ((json['dailySummaries'] as List<dynamic>?) ?? const [])
        .map(
          (item) =>
              DailyHealthSummaryDto.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false),
    exerciseSessions: ((json['exerciseSessions'] as List<dynamic>?) ?? const [])
        .map(
          (item) => ExerciseSessionDto.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false),
    fatigueAssessments:
        ((json['fatigueAssessments'] as List<dynamic>?) ?? const [])
            .map(
              (item) =>
                  FatigueAssessmentDto.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
    replacementWindow: json['replacementWindow'] == null
        ? null
        : ReplacementWindowDto.fromJson(
            json['replacementWindow'] as Map<String, dynamic>,
          ),
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'deviceId': deviceId,
    'idempotencyKey': idempotencyKey,
    'generatedAtUtc': generatedAtUtc.toUtc().toIso8601String(),
    'hourlyBins': hourlyBins
        .map((item) => item.toJson())
        .toList(growable: false),
    'dailySummaries': dailySummaries
        .map((item) => item.toJson())
        .toList(growable: false),
    'exerciseSessions': exerciseSessions
        .map((item) => item.toJson())
        .toList(growable: false),
    'fatigueAssessments': fatigueAssessments
        .map((item) => item.toJson())
        .toList(growable: false),
    if (replacementWindow != null)
      'replacementWindow': replacementWindow!.toJson(),
  };
}

class DashboardTodayDto {
  const DashboardTodayDto({
    required this.localDate,
    this.summary,
    this.latestAssessment,
    this.latestSampleAtUtc,
    this.serverSyncedAtUtc,
  });

  final DateTime localDate;
  final DailyHealthSummaryDto? summary;
  final FatigueAssessmentDto? latestAssessment;
  final DateTime? latestSampleAtUtc;
  final DateTime? serverSyncedAtUtc;

  factory DashboardTodayDto.fromJson(Map<String, dynamic> json) =>
      DashboardTodayDto(
        localDate: DateTime.parse(json['localDate'] as String),
        summary: json['summary'] == null
            ? null
            : DailyHealthSummaryDto.fromJson(
                json['summary'] as Map<String, dynamic>,
              ),
        latestAssessment: json['latestAssessment'] == null
            ? null
            : FatigueAssessmentDto.fromJson(
                json['latestAssessment'] as Map<String, dynamic>,
              ),
        latestSampleAtUtc: json['latestSampleAtUtc'] == null
            ? null
            : DateTime.parse(json['latestSampleAtUtc'] as String),
        serverSyncedAtUtc: json['serverSyncedAtUtc'] == null
            ? null
            : DateTime.parse(json['serverSyncedAtUtc'] as String),
      );

  Map<String, dynamic> toJson() => {
    'localDate':
        '${localDate.year.toString().padLeft(4, '0')}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}',
    'summary': summary?.toJson(),
    'latestAssessment': latestAssessment?.toJson(),
    'latestSampleAtUtc': latestSampleAtUtc?.toUtc().toIso8601String(),
    'serverSyncedAtUtc': serverSyncedAtUtc?.toUtc().toIso8601String(),
  };
}
