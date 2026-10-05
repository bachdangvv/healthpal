import '../domain/health_records.dart';
import 'canonicalizer.dart';
import 'record_identity.dart';

class HourlyBin {
  const HourlyBin({
    required this.hourUtc,
    required this.zoneOffsetMinutes,
    this.hrMean,
    this.hrMin,
    this.hrMax,
    this.hrSampleCount = 0,
    this.steps,
    this.activeCalories,
    required this.sourceId,
    required this.coverageComplete,
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
  final bool coverageComplete;
}

class DailyAggregate {
  const DailyAggregate({
    required this.localDate,
    this.sleepMinutes,
    this.steps,
    this.averageHeartRate,
    this.minHeartRate,
    this.maxHeartRate,
    this.restingHeartRate,
    this.activeCalories,
    this.exerciseCount = 0,
    this.exerciseDurationMinutes = 0,
    required this.coverageFlags,
  });

  final DateTime localDate;
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
}

class HealthAggregator {
  const HealthAggregator();

  List<({DateTime hourUtc, int count})> splitStepsAcrossHours(
    StepInterval interval,
  ) {
    final start = interval.startUtc.toUtc();
    final end = interval.endUtc.toUtc();
    final durationMs = end.difference(start).inMilliseconds;
    if (durationMs <= 0) {
      return [
        (
          hourUtc: localHourFloor(start, interval.zoneOffsetMinutes),
          count: interval.count,
        ),
      ];
    }

    final slices = <({DateTime hourUtc, int ms})>[];
    var cursor = start;
    while (cursor.isBefore(end)) {
      final hour = localHourFloor(cursor, interval.zoneOffsetMinutes);
      final nextHour = hour.add(const Duration(hours: 1));
      final sliceEnd = nextHour.isBefore(end) ? nextHour : end;
      slices.add((
        hourUtc: hour,
        ms: sliceEnd.difference(cursor).inMilliseconds,
      ));
      cursor = sliceEnd;
    }

    final raw = slices
        .map(
          (slice) => (
            hourUtc: slice.hourUtc,
            exact: interval.count * slice.ms / durationMs,
          ),
        )
        .toList();
    final floors = raw.map((item) => item.exact.floor()).toList();
    var remainder =
        interval.count - floors.fold<int>(0, (sum, value) => sum + value);
    final remainders = List<int>.generate(raw.length, (index) => index)
      ..sort(
        (a, b) =>
            (raw[b].exact - floors[b]).compareTo(raw[a].exact - floors[a]),
      );
    final allocated = List<int>.from(floors);
    for (var i = 0; i < remainder; i++) {
      allocated[remainders[i % remainders.length]] += 1;
    }
    return [
      for (var i = 0; i < raw.length; i++)
        (hourUtc: raw[i].hourUtc, count: allocated[i]),
    ];
  }

  List<HourlyBin> hourlyBins(
    IngestionBatch batch, {
    required String preferredSourceId,
    DateTime? completenessWatermarkUtc,
  }) {
    final hours = <DateTime, _HourAcc>{};

    void ensure(DateTime hourUtc, int offset, String sourceId) {
      hours.putIfAbsent(
        hourUtc,
        () => _HourAcc(offset: offset, sourceId: sourceId),
      );
    }

    final preferredHr = batch.heartRateSamples.where(
      (sample) => sample.source.sourceId == preferredSourceId,
    );
    final hrPool = preferredHr.isNotEmpty
        ? preferredHr
        : batch.heartRateSamples;
    for (final sample in hrPool) {
      final hour = localHourFloor(sample.startUtc, sample.zoneOffsetMinutes);
      ensure(hour, sample.zoneOffsetMinutes, preferredSourceId);
      hours[hour]!.hr.add(sample.bpm);
    }

    final preferredSteps = batch.stepIntervals.where(
      (item) => item.source.sourceId == preferredSourceId,
    );
    final stepPool = preferredSteps.isNotEmpty
        ? preferredSteps
        : batch.stepIntervals;
    for (final interval in stepPool) {
      for (final slice in splitStepsAcrossHours(interval)) {
        ensure(slice.hourUtc, interval.zoneOffsetMinutes, preferredSourceId);
        hours[slice.hourUtc]!.steps += slice.count;
        hours[slice.hourUtc]!.hasSteps = true;
      }
    }

    final preferredCal = batch.activeCaloriesIntervals.where(
      (item) => item.source.sourceId == preferredSourceId,
    );
    final calPool = preferredCal.isNotEmpty
        ? preferredCal
        : batch.activeCaloriesIntervals;
    for (final interval in calPool) {
      for (final slice in _splitCalories(interval)) {
        ensure(slice.hourUtc, interval.zoneOffsetMinutes, preferredSourceId);
        hours[slice.hourUtc]!.calories += slice.kcal;
        hours[slice.hourUtc]!.hasCalories = true;
      }
    }

    final bins = <HourlyBin>[];
    final sortedHours = hours.keys.toList()..sort();
    for (final hour in sortedHours) {
      final acc = hours[hour]!;
      final hourEnd = hour.add(const Duration(hours: 1));
      final complete =
          completenessWatermarkUtc != null &&
          !completenessWatermarkUtc.isBefore(hourEnd);
      bins.add(
        HourlyBin(
          hourUtc: hour,
          zoneOffsetMinutes: acc.offset,
          hrMean: acc.hr.isEmpty
              ? null
              : acc.hr.reduce((a, b) => a + b) / acc.hr.length,
          hrMin: acc.hr.isEmpty ? null : acc.hr.reduce((a, b) => a < b ? a : b),
          hrMax: acc.hr.isEmpty ? null : acc.hr.reduce((a, b) => a > b ? a : b),
          hrSampleCount: acc.hr.length,
          steps: acc.hasSteps ? acc.steps : null,
          activeCalories: acc.hasCalories ? acc.calories : null,
          sourceId: acc.sourceId,
          coverageComplete: complete,
        ),
      );
    }
    return bins;
  }

  List<DailyAggregate> dailySummaries({
    required List<HourlyBin> bins,
    required IngestionBatch batch,
    required String preferredSourceId,
    required String timezone,
    DateTime? completenessWatermarkUtc,
  }) {
    final byDay = <DateTime, List<HourlyBin>>{};
    for (final bin in bins) {
      final day = localDateOf(bin.hourUtc, bin.zoneOffsetMinutes);
      byDay.putIfAbsent(day, () => []).add(bin);
    }

    final days = <DateTime>{};
    days.addAll(byDay.keys);
    for (final session in batch.sleepSessions) {
      days.add(_dateOnly(session.healthDay));
    }
    for (final record in batch.restingHeartRateRecords) {
      days.add(_dateOnly(record.localDate));
    }
    for (final session in batch.exerciseSessions) {
      days.add(localDateOf(session.startUtc, session.zoneOffsetMinutes));
    }
    final sortedDays = days.toList()..sort();
    return [
      for (final day in sortedDays)
        _daily(
          day: day,
          bins: [...?byDay[day]]
            ..sort((a, b) => a.hourUtc.compareTo(b.hourUtc)),
          batch: batch,
          preferredSourceId: preferredSourceId,
          completenessWatermarkUtc: completenessWatermarkUtc,
        ),
    ];
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  int _offsetForDay({
    required DateTime day,
    required List<HourlyBin> bins,
    required IngestionBatch batch,
    required String preferredSourceId,
  }) {
    if (bins.isNotEmpty) return bins.first.zoneOffsetMinutes;
    final sleep = canonicalSleepForDay(
      sessions: batch.sleepSessions,
      healthDay: day,
      preferredSourceId: preferredSourceId,
    );
    if (sleep != null) return sleep.zoneOffsetMinutes;
    final rhrRecords = _rhrRecordsForDay(
      records: batch.restingHeartRateRecords,
      localDate: day,
      preferredSourceId: preferredSourceId,
    );
    if (rhrRecords.isNotEmpty) return rhrRecords.first.zoneOffsetMinutes;
    final exercises = _exercisesForDay(batch.exerciseSessions, day);
    if (exercises.isNotEmpty) return exercises.first.zoneOffsetMinutes;
    return 0;
  }

  List<RestingHeartRateRecord> _rhrRecordsForDay({
    required List<RestingHeartRateRecord> records,
    required DateTime localDate,
    required String preferredSourceId,
  }) {
    var pool = records
        .where((record) => _dateOnly(record.localDate) == localDate)
        .toList();
    final preferred = pool
        .where((record) => record.source.sourceId == preferredSourceId)
        .toList();
    if (preferred.isNotEmpty) pool = preferred;
    pool.sort((a, b) => a.recordedAtUtc.compareTo(b.recordedAtUtc));
    return pool;
  }

  List<ExerciseSession> _exercisesForDay(
    List<ExerciseSession> sessions,
    DateTime day,
  ) {
    final matches = sessions
        .where(
          (session) =>
              localDateOf(session.startUtc, session.zoneOffsetMinutes) == day,
        )
        .toList();
    matches.sort((a, b) => a.startUtc.compareTo(b.startUtc));
    return matches;
  }

  DailyAggregate _daily({
    required DateTime day,
    required List<HourlyBin> bins,
    required IngestionBatch batch,
    required String preferredSourceId,
    DateTime? completenessWatermarkUtc,
  }) {
    final hr = bins.where((bin) => bin.hrMean != null).toList();
    final stepBins = bins.where((bin) => bin.steps != null).toList();
    final calBins = bins.where((bin) => bin.activeCalories != null).toList();
    final offset = _offsetForDay(
      day: day,
      bins: bins,
      batch: batch,
      preferredSourceId: preferredSourceId,
    );
    final localDayEndUtc = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).subtract(Duration(minutes: offset)).add(const Duration(days: 1));
    final stepsComplete =
        completenessWatermarkUtc != null &&
        !completenessWatermarkUtc.isBefore(localDayEndUtc);

    final sleep = canonicalSleepForDay(
      sessions: batch.sleepSessions,
      healthDay: day,
      preferredSourceId: preferredSourceId,
    );
    final rhr = canonicalRhrForDay(
      records: batch.restingHeartRateRecords,
      localDate: day,
      preferredSourceId: preferredSourceId,
    );

    final exercises = _exercisesForDay(batch.exerciseSessions, day);

    return DailyAggregate(
      localDate: day,
      sleepMinutes: sleep?.sleepMinutes,
      steps: stepBins.isEmpty
          ? (stepsComplete ? 0 : null)
          : stepBins.fold<int>(0, (sum, bin) => sum + (bin.steps ?? 0)),
      averageHeartRate: hr.isEmpty
          ? null
          : hr.fold<double>(0, (sum, bin) => sum + bin.hrMean!) / hr.length,
      minHeartRate: hr.isEmpty
          ? null
          : hr.map((bin) => bin.hrMin!).reduce((a, b) => a < b ? a : b),
      maxHeartRate: hr.isEmpty
          ? null
          : hr.map((bin) => bin.hrMax!).reduce((a, b) => a > b ? a : b),
      restingHeartRate: rhr,
      activeCalories: calBins.isEmpty
          ? null
          : calBins.fold<double>(
              0,
              (sum, bin) => sum + (bin.activeCalories ?? 0),
            ),
      exerciseCount: exercises.length,
      exerciseDurationMinutes: exercises.fold<int>(
        0,
        (sum, session) => sum + session.durationMinutes,
      ),
      coverageFlags: {
        'stepsComplete': stepsComplete,
        'hasHeartRate': hr.isNotEmpty,
        'hasSleep': sleep != null,
        'hasRhr': rhr != null,
      },
    );
  }

  List<({DateTime hourUtc, double kcal})> _splitCalories(
    ActiveCaloriesInterval interval,
  ) {
    final start = interval.startUtc.toUtc();
    final end = interval.endUtc.toUtc();
    final durationMs = end.difference(start).inMilliseconds;
    if (durationMs <= 0) {
      return [
        (
          hourUtc: localHourFloor(start, interval.zoneOffsetMinutes),
          kcal: interval.kilocalories,
        ),
      ];
    }
    final result = <({DateTime hourUtc, double kcal})>[];
    var cursor = start;
    while (cursor.isBefore(end)) {
      final hour = localHourFloor(cursor, interval.zoneOffsetMinutes);
      final nextHour = hour.add(const Duration(hours: 1));
      final sliceEnd = nextHour.isBefore(end) ? nextHour : end;
      final share =
          interval.kilocalories *
          sliceEnd.difference(cursor).inMilliseconds /
          durationMs;
      result.add((hourUtc: hour, kcal: share));
      cursor = sliceEnd;
    }
    return result;
  }
}

class _HourAcc {
  _HourAcc({required this.offset, required this.sourceId});

  final int offset;
  final String sourceId;
  final List<double> hr = [];
  int steps = 0;
  double calories = 0;
  bool hasSteps = false;
  bool hasCalories = false;
}
