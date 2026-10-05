import '../../assessment/domain/fatigue_assessment.dart';

enum HealthConnectAvailability { available, unavailable, unsupported }

enum HealthConnectAccess { granted, missingPermissions, denied }

enum DashboardDataStatus {
  connected,
  missingPermissions,
  noData,
  needsSync,
  unavailable,
}

enum HealthMetricPermission {
  steps,
  sleep,
  heartRate,
  restingHeartRate,
  hrv,
  activeCalories,
}

extension HealthMetricPermissionPresentation on HealthMetricPermission {
  String get label => switch (this) {
    HealthMetricPermission.steps => 'Số bước',
    HealthMetricPermission.sleep => 'Giấc ngủ',
    HealthMetricPermission.heartRate => 'Nhịp tim',
    HealthMetricPermission.restingHeartRate => 'Nhịp tim nghỉ',
    HealthMetricPermission.hrv => 'HRV',
    HealthMetricPermission.activeCalories => 'Calories vận động',
  };
}

class TodayHealthSummary {
  const TodayHealthSummary({
    this.steps,
    this.sleepMinutes,
    this.averageHeartRate,
    this.latestHeartRate,
    this.restingHeartRate,
    this.hrv,
    this.activeCalories,
    required this.collectedAt,
  });

  final int? steps;
  final int? sleepMinutes;
  final double? averageHeartRate;
  final double? latestHeartRate;
  final double? restingHeartRate;
  final double? hrv;
  final double? activeCalories;
  final DateTime collectedAt;

  bool get hasAnyData =>
      steps != null ||
      sleepMinutes != null ||
      averageHeartRate != null ||
      latestHeartRate != null ||
      restingHeartRate != null ||
      hrv != null ||
      activeCalories != null;
}

class HealthConnectSnapshot {
  const HealthConnectSnapshot({
    required this.availability,
    required this.access,
    required this.missingPermissions,
    this.summary,
    this.lastSyncedAt,
    this.latestDataAt,
    this.errorMessage,
    this.fatigue,
    this.showExperimentalFatigue = true,
    this.backgroundReadSupported = false,
    this.backgroundReadGranted = false,
    this.pendingOutboxCount = 0,
  });

  final HealthConnectAvailability availability;
  final HealthConnectAccess access;
  final List<HealthMetricPermission> missingPermissions;
  final TodayHealthSummary? summary;
  final DateTime? lastSyncedAt;
  final DateTime? latestDataAt;
  final String? errorMessage;
  final FatigueAssessment? fatigue;
  final bool showExperimentalFatigue;
  final bool backgroundReadSupported;
  final bool backgroundReadGranted;
  final int pendingOutboxCount;

  DashboardDataStatus get status {
    if (availability != HealthConnectAvailability.available) {
      return DashboardDataStatus.unavailable;
    }
    if (access != HealthConnectAccess.granted ||
        missingPermissions.isNotEmpty) {
      return DashboardDataStatus.missingPermissions;
    }
    if (summary == null || !summary!.hasAnyData) {
      return DashboardDataStatus.noData;
    }
    final synced = lastSyncedAt;
    if (synced == null || DateTime.now().difference(synced).inHours >= 6) {
      return DashboardDataStatus.needsSync;
    }
    return DashboardDataStatus.connected;
  }
}
