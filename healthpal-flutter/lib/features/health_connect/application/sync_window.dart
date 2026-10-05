class SyncReplacementWindow {
  SyncReplacementWindow({
    required this.startUtc,
    required this.endUtcExclusive,
    required this.localDateStart,
    required this.localDateEndExclusive,
    required this.timezoneOffsetMinutes,
  }) {
    if (!startUtc.isUtc || !endUtcExclusive.isUtc) {
      throw ArgumentError('UTC window bounds must be UTC.');
    }
    if (!endUtcExclusive.isAfter(startUtc)) {
      throw ArgumentError('endUtcExclusive must be after startUtc.');
    }
    if (localDateStart.hour != 0 ||
        localDateStart.minute != 0 ||
        localDateStart.second != 0 ||
        localDateStart.millisecond != 0) {
      throw ArgumentError('localDateStart must be date-only.');
    }
    if (localDateEndExclusive.hour != 0 ||
        localDateEndExclusive.minute != 0 ||
        localDateEndExclusive.second != 0 ||
        localDateEndExclusive.millisecond != 0) {
      throw ArgumentError('localDateEndExclusive must be date-only.');
    }
  }

  static const correctionOverlap = Duration(hours: 48);
  static const maximumHistoryDays = 30;
  static const maximumUtcDuration = Duration(days: 32);
  static const maximumLocalDateRangeDays = 32;

  final DateTime startUtc;
  final DateTime endUtcExclusive;
  final DateTime localDateStart;
  final DateTime localDateEndExclusive;
  final int timezoneOffsetMinutes;

  Duration get utcDuration => endUtcExclusive.difference(startUtc);

  int get localDateRangeDays =>
      localDateEndExclusive.difference(localDateStart).inDays;

  bool get coversAtLeast48Hours => utcDuration >= correctionOverlap;

  bool get coversAtLeast30Days =>
      utcDuration >= Duration(days: maximumHistoryDays);

  bool containsUtc(DateTime value) {
    final utc = value.toUtc();
    return !utc.isBefore(startUtc) && utc.isBefore(endUtcExclusive);
  }

  bool containsLocalDate(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return !date.isBefore(localDateStart) &&
        date.isBefore(localDateEndExclusive);
  }

  factory SyncReplacementWindow.forSync({
    required DateTime cutoffUtc,
    required int timezoneOffsetMinutes,
    DateTime? previousWatermarkUtc,
    required bool firstSync,
  }) {
    final cutoff = cutoffUtc.toUtc();
    final offset = Duration(minutes: timezoneOffsetMinutes);
    final localCutoff = cutoff.add(offset);
    final localCutoffDate = DateTime(
      localCutoff.year,
      localCutoff.month,
      localCutoff.day,
    );
    final earliestAllowedLocalDate = localCutoffDate.subtract(
      const Duration(days: maximumHistoryDays),
    );
    final DateTime localStartDate;
    if (firstSync || previousWatermarkUtc == null) {
      localStartDate = earliestAllowedLocalDate;
    } else {
      final previous = previousWatermarkUtc.toUtc();
      final effectivePrevious = previous.isAfter(cutoff) ? cutoff : previous;
      final candidateUtc = effectivePrevious.subtract(correctionOverlap);
      final candidateLocal = candidateUtc.add(offset);
      final candidateLocalDate = DateTime(
        candidateLocal.year,
        candidateLocal.month,
        candidateLocal.day,
      );
      localStartDate = candidateLocalDate.isBefore(earliestAllowedLocalDate)
          ? earliestAllowedLocalDate
          : candidateLocalDate;
    }
    final startUtc = DateTime.utc(
      localStartDate.year,
      localStartDate.month,
      localStartDate.day,
    ).subtract(offset);
    final localDateEndExclusive = localCutoffDate.add(const Duration(days: 1));
    final window = SyncReplacementWindow(
      startUtc: startUtc,
      endUtcExclusive: cutoff,
      localDateStart: localStartDate,
      localDateEndExclusive: localDateEndExclusive,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
    );
    if (window.utcDuration > maximumUtcDuration) {
      throw StateError('replacement window exceeds 32-day UTC safety limit');
    }
    if (window.localDateRangeDays > maximumLocalDateRangeDays) {
      throw StateError(
        'replacement window exceeds 32-day local range safety limit',
      );
    }
    return window;
  }
}
