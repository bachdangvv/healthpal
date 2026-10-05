import 'dart:async';

import '../../../core/sync/sync_state.dart';
import '../data/health_connect_gateway.dart';
import '../domain/health_connect_failure.dart';
import '../domain/health_records.dart';
import 'aggregator.dart';
import 'canonicalizer.dart';
import 'sync_window.dart';

typedef AssessmentHook =
    Future<void> Function(IngestionBatch batch, CanonicalIngestion canonical);
typedef PersistHook =
    Future<void> Function({
      required CanonicalIngestion canonical,
      required List<HourlyBin> bins,
      required List<DailyAggregate> days,
      required SyncState state,
      required SyncReplacementWindow window,
    });
typedef PermissionHook = void Function(PermissionSnapshot snapshot);

class SyncOrchestrator {
  SyncOrchestrator({
    required this.gateway,
    this.canonicalizer = const HealthRecordCanonicalizer(),
    this.aggregator = const HealthAggregator(),
    this.onPersist,
    this.onAssess,
  });

  final HealthConnectGateway gateway;
  final HealthRecordCanonicalizer canonicalizer;
  final HealthAggregator aggregator;
  final PersistHook? onPersist;
  final AssessmentHook? onAssess;

  Future<SyncState>? _inFlight;

  Future<SyncState> syncNow({
    required DateTime nowUtc,
    DateTime? previousWatermarkUtc,
    String? preferredSourceId,
    bool firstSync = false,
    bool requestPermissionsIfMissing = false,
    int timezoneOffsetMinutes = 0,
    SyncReplacementWindow? replacementWindow,
    PermissionHook? onPermissions,
    PersistHook? onPersist,
    AssessmentHook? onAssess,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _run(
      nowUtc: nowUtc,
      previousWatermarkUtc: previousWatermarkUtc,
      preferredSourceId: preferredSourceId,
      firstSync: firstSync,
      requestPermissionsIfMissing: requestPermissionsIfMissing,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
      replacementWindow: replacementWindow,
      onPermissions: onPermissions,
      onPersist: onPersist ?? this.onPersist,
      onAssess: onAssess ?? this.onAssess,
    );
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<SyncState> _run({
    required DateTime nowUtc,
    DateTime? previousWatermarkUtc,
    String? preferredSourceId,
    required bool firstSync,
    required bool requestPermissionsIfMissing,
    required int timezoneOffsetMinutes,
    SyncReplacementWindow? replacementWindow,
    PermissionHook? onPermissions,
    PersistHook? onPersist,
    AssessmentHook? onAssess,
  }) async {
    var phase = SyncPhase.checkCapabilities;
    try {
      final capabilities = await gateway.getCapabilities();
      if (!capabilities.sdkAvailable) {
        throw const HealthConnectFailure(HealthConnectFailureCode.unavailable);
      }
      phase = SyncPhase.readLookback;
      var permissions = await gateway.getPermissions();
      if (requestPermissionsIfMissing &&
          permissions.missing
              .intersection(PermissionSnapshot.v4Required)
              .isNotEmpty) {
        permissions = await gateway.requestPermissions({
          ...PermissionSnapshot.v4Required,
          ...PermissionSnapshot.analyticsRequired,
        });
      }
      onPermissions?.call(permissions);
      if (permissions.missing
          .intersection(PermissionSnapshot.v4Required)
          .isNotEmpty) {
        return SyncState(
          lastError: 'missing_permissions',
          lastCompletedPhase: phase,
        );
      }

      final window =
          replacementWindow ??
          SyncReplacementWindow.forSync(
            cutoffUtc: nowUtc,
            timezoneOffsetMinutes: timezoneOffsetMinutes,
            previousWatermarkUtc: previousWatermarkUtc,
            firstSync: firstSync,
          );
      final batch = await gateway.readRange(window.startUtc, nowUtc);

      phase = SyncPhase.canonicalize;
      final canonical = canonicalizer.canonicalize(
        batch,
        preferredSourceId: preferredSourceId,
      );
      final sourceId = canonical.preferredSourceId ?? preferredSourceId ?? '';
      DateTime? latest;
      void consider(DateTime time) {
        if (latest == null || time.isAfter(latest!)) latest = time;
      }

      for (final item in canonical.batch.heartRateSamples) {
        consider(item.startUtc);
      }
      for (final item in canonical.batch.stepIntervals) {
        consider(item.endUtc);
      }
      for (final item in canonical.batch.sleepSessions) {
        consider(item.endUtc);
      }
      for (final item in canonical.batch.restingHeartRateRecords) {
        consider(item.recordedAtUtc);
      }
      for (final item in canonical.batch.exerciseSessions) {
        consider(item.endUtc);
      }
      for (final item in canonical.batch.activeCaloriesIntervals) {
        consider(item.endUtc);
      }

      phase = SyncPhase.recomputeAggregates;
      final bins = aggregator
          .hourlyBins(
            canonical.batch,
            preferredSourceId: sourceId,
            completenessWatermarkUtc: latest,
          )
          .where((bin) => window.containsUtc(bin.hourUtc))
          .toList(growable: false);
      final days = aggregator
          .dailySummaries(
            bins: bins,
            batch: canonical.batch,
            preferredSourceId: sourceId,
            timezone: 'local',
            completenessWatermarkUtc: latest,
          )
          .where((day) => window.containsLocalDate(day.localDate))
          .toList(growable: false);

      phase = SyncPhase.upsertLocal;
      // sourceWatermarkUtc: query completed through nowUtc (syncCutoffUtc).
      // latestDataAtUtc: newest real sample; freshness only, not completeness.
      final state = SyncState(
        lastSuccessfulSyncAtUtc: nowUtc,
        sourceWatermarkUtc: nowUtc,
        latestDataAtUtc: latest,
        lastCompletedPhase: SyncPhase.refreshUi,
        preferredSourceId: sourceId,
      );
      await onPersist?.call(
        canonical: canonical,
        bins: bins,
        days: days,
        state: state,
        window: window,
      );

      phase = SyncPhase.assess;
      await onAssess?.call(canonical.batch, canonical);
      return state;
    } on HealthConnectFailure catch (error) {
      return SyncState(lastError: error.toString(), lastCompletedPhase: phase);
    }
  }
}
