import '../domain/health_records.dart';
import '../domain/sleep_normalizer.dart';
import 'record_identity.dart';

class CanonicalIngestion {
  const CanonicalIngestion({
    required this.batch,
    required this.droppedDuplicates,
    required this.rejectedHeartRate,
    required this.preferredSourceId,
  });

  final IngestionBatch batch;
  final int droppedDuplicates;
  final int rejectedHeartRate;
  final String? preferredSourceId;
}

class HealthRecordCanonicalizer {
  const HealthRecordCanonicalizer();

  CanonicalIngestion canonicalize(
    IngestionBatch input, {
    String? preferredSourceId,
  }) {
    var rejectedHr = 0;
    final validHr = <HeartRateSample>[];
    for (final sample in input.heartRateSamples) {
      if (sample.isPhysiologicallyPlausible) {
        validHr.add(sample);
      } else {
        rejectedHr += 1;
      }
    }

    final preferred =
        preferredSourceId ??
        _inferPreferredSource(input) ??
        _firstSource(input);

    final hr = _dedupeHr(validHr);
    final steps = _dedupeSteps(input.stepIntervals);
    final rhr = _dedupeRhr(input.restingHeartRateRecords);
    final sleep = _canonicalSleepSessions(
      _dedupeSleep(input.sleepSessions),
      preferred,
    );
    final exercise = _dedupeExercise(input.exerciseSessions);
    final calories = _dedupeCalories(input.activeCaloriesIntervals);

    final originalCount =
        input.heartRateSamples.length +
        input.stepIntervals.length +
        input.restingHeartRateRecords.length +
        input.sleepSessions.length +
        input.exerciseSessions.length +
        input.activeCaloriesIntervals.length;
    final kept =
        hr.length +
        steps.length +
        rhr.length +
        sleep.length +
        exercise.length +
        calories.length;

    return CanonicalIngestion(
      batch: IngestionBatch(
        startUtc: input.startUtc,
        endUtc: input.endUtc,
        heartRateSamples: hr,
        stepIntervals: steps,
        restingHeartRateRecords: rhr,
        sleepSessions: sleep,
        exerciseSessions: exercise,
        activeCaloriesIntervals: calories,
      ),
      droppedDuplicates: originalCount - kept - rejectedHr,
      rejectedHeartRate: rejectedHr,
      preferredSourceId: preferred,
    );
  }

  List<HeartRateSample> _dedupeHr(List<HeartRateSample> items) {
    return _unique(
      items,
      id: (item) => item.recordId,
      hash: (item) => recordHash(
        type: 'hr',
        sourceId: item.source.sourceId,
        startUtc: item.startUtc,
        endUtc: item.endUtc,
        roundedValue: item.bpm.round(),
      ),
    );
  }

  List<StepInterval> _dedupeSteps(List<StepInterval> items) {
    return _unique(
      items,
      id: (item) => item.recordId,
      hash: (item) => recordHash(
        type: 'steps',
        sourceId: item.source.sourceId,
        startUtc: item.startUtc,
        endUtc: item.endUtc,
        roundedValue: item.count,
      ),
    );
  }

  List<RestingHeartRateRecord> _dedupeRhr(List<RestingHeartRateRecord> items) {
    return _unique(
      items,
      id: (item) => item.recordId,
      hash: (item) => recordHash(
        type: 'rhr',
        sourceId: item.source.sourceId,
        startUtc: item.recordedAtUtc,
        endUtc: item.recordedAtUtc,
        roundedValue: item.bpm.round(),
      ),
    );
  }

  List<SleepSession> _canonicalSleepSessions(
    List<SleepSession> items,
    String? preferredSourceId,
  ) {
    const normalizer = SleepStageNormalizer();
    final byDay = <String, List<SleepSession>>{};
    for (final session in items) {
      final normalized = normalizer.normalize(session);
      final next = SleepSession(
        recordId: session.recordId,
        startUtc: session.startUtc,
        endUtc: session.endUtc,
        zoneOffsetMinutes: session.zoneOffsetMinutes,
        healthDay: session.healthDay,
        stages: normalized.stages,
        asleepMinutesAggregate: session.asleepMinutesAggregate,
        source: session.source,
        modifiedAtUtc: session.modifiedAtUtc,
      );
      final key =
          '${session.healthDay.year.toString().padLeft(4, '0')}-${session.healthDay.month.toString().padLeft(2, '0')}-${session.healthDay.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => []).add(next);
    }
    final chosen = <SleepSession>[];
    for (final entry in byDay.entries) {
      final day = DateTime.parse(entry.key);
      final session = canonicalSleepForDay(
        sessions: entry.value,
        healthDay: day,
        preferredSourceId: preferredSourceId,
      );
      if (session != null) chosen.add(session);
    }
    return chosen;
  }

  List<SleepSession> _dedupeSleep(List<SleepSession> items) {
    return _unique(
      items,
      id: (item) => item.recordId,
      hash: (item) => recordHash(
        type: 'sleep',
        sourceId: item.source.sourceId,
        startUtc: item.startUtc,
        endUtc: item.endUtc,
        roundedValue: item.sleepMinutes,
      ),
    );
  }

  List<ExerciseSession> _dedupeExercise(List<ExerciseSession> items) {
    return _unique(
      items,
      id: (item) => item.recordId,
      hash: (item) => recordHash(
        type: 'exercise',
        sourceId: item.source.sourceId,
        startUtc: item.startUtc,
        endUtc: item.endUtc,
        roundedValue: item.durationMinutes,
      ),
    );
  }

  List<ActiveCaloriesInterval> _dedupeCalories(
    List<ActiveCaloriesInterval> items,
  ) {
    return _unique(
      items,
      id: (item) => item.recordId,
      hash: (item) => recordHash(
        type: 'calories',
        sourceId: item.source.sourceId,
        startUtc: item.startUtc,
        endUtc: item.endUtc,
        roundedValue: item.kilocalories.round(),
      ),
    );
  }

  List<T> _unique<T>(
    List<T> items, {
    required String Function(T item) id,
    required String Function(T item) hash,
  }) {
    final seenIds = <String>{};
    final seenHashes = <String>{};
    final result = <T>[];
    for (final item in items) {
      final recordId = id(item);
      final recordHashValue = hash(item);
      if (recordId.isNotEmpty && !seenIds.add(recordId)) continue;
      if (!seenHashes.add(recordHashValue)) continue;
      result.add(item);
    }
    return result;
  }

  String? _inferPreferredSource(IngestionBatch batch) {
    final counts = <String, int>{};
    void tally(String sourceId, String sourceName) {
      counts[sourceId] = (counts[sourceId] ?? 0) + 1;
      if (looksLikeHuaweiSource(
        SourceInfo(sourceId: sourceId, sourceName: sourceName),
      )) {
        counts[sourceId] = (counts[sourceId] ?? 0) + 1000;
      }
    }

    for (final item in batch.stepIntervals) {
      tally(item.source.sourceId, item.source.sourceName);
    }
    for (final item in batch.heartRateSamples) {
      tally(item.source.sourceId, item.source.sourceName);
    }
    if (counts.isEmpty) return null;
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.first.key;
  }

  String? _firstSource(IngestionBatch batch) {
    if (batch.stepIntervals.isNotEmpty) {
      return batch.stepIntervals.first.source.sourceId;
    }
    if (batch.heartRateSamples.isNotEmpty) {
      return batch.heartRateSamples.first.source.sourceId;
    }
    return null;
  }
}

SleepSession? canonicalSleepForDay({
  required List<SleepSession> sessions,
  required DateTime healthDay,
  String? preferredSourceId,
}) {
  final candidates = sessions
      .where(
        (session) =>
            session.healthDay.year == healthDay.year &&
            session.healthDay.month == healthDay.month &&
            session.healthDay.day == healthDay.day,
      )
      .toList();
  if (candidates.isEmpty) return null;

  int rank(SleepSession session) {
    final preferred =
        preferredSourceId != null &&
            session.source.sourceId == preferredSourceId
        ? 1
        : 0;
    final stages = session.hasStageCoverage ? 1 : 0;
    final duration = session.endUtc.difference(session.startUtc).inMinutes;
    final reasonable = duration >= 120 && duration <= 14 * 60 ? 1 : 0;
    return preferred * 1 << 20 |
        stages * 1 << 19 |
        reasonable * 1 << 18 |
        duration;
  }

  candidates.sort((a, b) {
    final byRank = rank(b).compareTo(rank(a));
    if (byRank != 0) return byRank;
    final aUpdated = a.modifiedAtUtc ?? a.endUtc;
    final bUpdated = b.modifiedAtUtc ?? b.endUtc;
    return bUpdated.compareTo(aUpdated);
  });
  return candidates.first;
}

double? canonicalRhrForDay({
  required List<RestingHeartRateRecord> records,
  required DateTime localDate,
  String? preferredSourceId,
}) {
  var pool = records
      .where(
        (record) =>
            record.localDate.year == localDate.year &&
            record.localDate.month == localDate.month &&
            record.localDate.day == localDate.day,
      )
      .toList();
  if (preferredSourceId != null) {
    final preferred = pool
        .where((record) => record.source.sourceId == preferredSourceId)
        .toList();
    if (preferred.isNotEmpty) pool = preferred;
  }
  if (pool.isEmpty) return null;
  final values = pool.map((record) => record.bpm).toList()..sort();
  final mid = values.length ~/ 2;
  if (values.length.isOdd) return values[mid];
  return (values[mid - 1] + values[mid]) / 2;
}
