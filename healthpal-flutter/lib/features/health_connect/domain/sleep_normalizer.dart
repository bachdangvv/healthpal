import 'health_records.dart';
import '../application/record_identity.dart';

class SleepInterval {
  const SleepInterval({required this.startUtc, required this.endUtc});

  final DateTime startUtc;
  final DateTime endUtc;

  int get durationMs => endUtc.difference(startUtc).inMilliseconds;
}

class NormalizedSleep {
  const NormalizedSleep({
    required this.stages,
    required this.asleepMinutes,
    required this.usedStageCoverage,
  });

  final List<SleepStage> stages;
  final int asleepMinutes;
  final bool usedStageCoverage;
}

/// Canonical sleep duration: union of asleep intervals, never a raw sum.
class SleepStageNormalizer {
  const SleepStageNormalizer();

  List<SleepStage> stagesForSession({
    required SleepSession session,
    required List<SleepStage> stages,
  }) {
    return [
      for (final stage in stages)
        if (_sameSource(stage, session) && _overlaps(stage, session)) stage,
    ];
  }

  /// When Health Connect has stages but no SLEEP_SESSION, derive one session
  /// per source so Huawei and phone stages are never mixed.
  List<SleepSession> sessionsFromUnattachedStages(List<SleepStage> stages) {
    if (stages.isEmpty) return const [];
    final grouped = <String, List<SleepStage>>{};
    for (final stage in stages) {
      final key = effectiveSourceId(
        sourceId: stage.source?.sourceId ?? '',
        sourceName: stage.source?.sourceName ?? '',
      );
      grouped.putIfAbsent(key, () => []).add(stage);
    }
    return [
      for (final entry in grouped.entries) _sessionFromStages(entry.value),
    ];
  }

  SleepSession _sessionFromStages(List<SleepStage> stages) {
    final ordered = [...stages]
      ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
    final start = ordered.first.startUtc;
    final end = ordered.last.endUtc;
    final source =
        ordered.first.source ??
        const SourceInfo(
          sourceId: 'health_connect',
          sourceName: 'Health Connect',
        );
    final local = end;
    return SleepSession(
      recordId: 'sleep-derived-${source.sourceId}-${start.toIso8601String()}',
      startUtc: start,
      endUtc: end,
      zoneOffsetMinutes: 0,
      healthDay: DateTime(local.year, local.month, local.day),
      stages: ordered,
      source: source,
    );
  }

  NormalizedSleep normalize(SleepSession session) {
    final start = session.startUtc.toUtc();
    final end = session.endUtc.toUtc();
    final sessionMs = end.difference(start).inMilliseconds;
    if (sessionMs <= 0) {
      return const NormalizedSleep(
        stages: [],
        asleepMinutes: 0,
        usedStageCoverage: false,
      );
    }

    final unique = <SleepStage>[];
    final seen = <String>{};
    for (final stage in session.stages) {
      var stageStart = stage.startUtc.toUtc();
      var stageEnd = stage.endUtc.toUtc();
      if (stageStart.isBefore(start)) stageStart = start;
      if (stageEnd.isAfter(end)) stageEnd = end;
      if (!stageEnd.isAfter(stageStart)) continue;
      final recordId = stage.recordId.isEmpty
          ? recordHash(
              type: 'sleep_stage',
              sourceId: (stage.source ?? session.source).sourceId,
              startUtc: stageStart,
              endUtc: stageEnd,
              roundedValue: stage.type.index,
            )
          : stage.recordId;
      final normalized = SleepStage(
        recordId: recordId,
        startUtc: stageStart,
        endUtc: stageEnd,
        type: stage.type,
        source: stage.source ?? session.source,
        modifiedAtUtc: stage.modifiedAtUtc,
      );
      final key =
          '$recordId|${normalized.source?.sourceId}|${stageStart.toIso8601String()}|${stageEnd.toIso8601String()}|${stage.type.name}';
      if (seen.add(key)) unique.add(normalized);
    }
    unique.sort((a, b) {
      final byStart = a.startUtc.compareTo(b.startUtc);
      if (byStart != 0) return byStart;
      return a.endUtc.compareTo(b.endUtc);
    });

    final detailed = unique.where(
      (stage) => stage.type != SleepStageType.asleep,
    );
    final generic = unique.where(
      (stage) => stage.type == SleepStageType.asleep,
    );
    final awake = _union(
      detailed
          .where((stage) => stage.type == SleepStageType.awake)
          .map(_intervalOf),
    );
    final detailedAsleep = _union(
      detailed.where((stage) => stage.isAsleep).map(_intervalOf),
    );
    final detailedCoverage = _union(detailed.map(_intervalOf));
    final genericAsleep = _union(generic.map(_intervalOf));
    final genericFill = _subtract(
      _subtract(genericAsleep, detailedCoverage),
      awake,
    );
    final asleep = _subtract(
      _union([...detailedAsleep, ...genericFill]),
      awake,
    );

    final hasReliableStages = unique.any((stage) => stage.isAsleep);
    var minutes = hasReliableStages
        ? _minutes(asleep)
        : (session.asleepMinutesAggregate ?? end.difference(start).inMinutes);
    final maxMinutes = end.difference(start).inMinutes;
    if (minutes < 0) minutes = 0;
    if (minutes > maxMinutes) minutes = maxMinutes;
    return NormalizedSleep(
      stages: unique,
      asleepMinutes: minutes,
      usedStageCoverage: hasReliableStages,
    );
  }

  bool _sameSource(SleepStage stage, SleepSession session) {
    final source = stage.source;
    if (source == null || source.sourceId.isEmpty) return false;
    return source.sourceId == session.source.sourceId;
  }

  bool _overlaps(SleepStage stage, SleepSession session) {
    return stage.startUtc.isBefore(session.endUtc) &&
        stage.endUtc.isAfter(session.startUtc);
  }

  SleepInterval _intervalOf(SleepStage stage) =>
      SleepInterval(startUtc: stage.startUtc, endUtc: stage.endUtc);

  List<SleepInterval> _union(Iterable<SleepInterval> raw) {
    final items = raw.where((item) => item.durationMs > 0).toList()
      ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
    if (items.isEmpty) return const [];
    final merged = <SleepInterval>[];
    var current = items.first;
    for (final next in items.skip(1)) {
      if (!next.startUtc.isAfter(current.endUtc)) {
        current = SleepInterval(
          startUtc: current.startUtc,
          endUtc: next.endUtc.isAfter(current.endUtc)
              ? next.endUtc
              : current.endUtc,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
    return merged;
  }

  List<SleepInterval> _subtract(
    List<SleepInterval> base,
    List<SleepInterval> cut,
  ) {
    var result = base;
    for (final hole in cut) {
      final next = <SleepInterval>[];
      for (final item in result) {
        if (!hole.endUtc.isAfter(item.startUtc) ||
            !hole.startUtc.isBefore(item.endUtc)) {
          next.add(item);
          continue;
        }
        if (hole.startUtc.isAfter(item.startUtc)) {
          next.add(
            SleepInterval(startUtc: item.startUtc, endUtc: hole.startUtc),
          );
        }
        if (hole.endUtc.isBefore(item.endUtc)) {
          next.add(SleepInterval(startUtc: hole.endUtc, endUtc: item.endUtc));
        }
      }
      result = next;
    }
    return result;
  }

  int _minutes(List<SleepInterval> intervals) {
    final ms = intervals.fold<int>(0, (sum, item) => sum + item.durationMs);
    return ms ~/ 60000;
  }
}
