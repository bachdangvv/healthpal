import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/health_connect/application/sync_window.dart';

void _assertWithinBackendLimit(SyncReplacementWindow window) {
  expect(window.endUtcExclusive.isAfter(window.startUtc), isTrue);
  expect(window.utcDuration, lessThanOrEqualTo(const Duration(days: 32)));
  expect(window.localDateRangeDays, lessThanOrEqualTo(32));
}

void main() {
  test('normal incremental keeps 48-hour overlap and local-midnight floor', () {
    final window = SyncReplacementWindow.forSync(
      cutoffUtc: DateTime.utc(2026, 9, 30, 8),
      timezoneOffsetMinutes: 0,
      previousWatermarkUtc: DateTime.utc(2026, 9, 30, 8),
      firstSync: false,
    );
    expect(window.startUtc, DateTime.utc(2026, 9, 28));
    expect(window.endUtcExclusive, DateTime.utc(2026, 9, 30, 8));
    expect(window.localDateStart, DateTime(2026, 9, 28));
    expect(window.localDateEndExclusive, DateTime(2026, 10, 1));
    expect(window.coversAtLeast48Hours, isTrue);
    _assertWithinBackendLimit(window);
  });

  test('explicit UTC+7 offset floors without calling toLocal', () {
    final window = SyncReplacementWindow.forSync(
      cutoffUtc: DateTime.utc(2026, 9, 30, 8),
      timezoneOffsetMinutes: 420,
      previousWatermarkUtc: DateTime.utc(2026, 9, 30, 8),
      firstSync: false,
    );
    expect(window.startUtc, DateTime.utc(2026, 9, 27, 17));
    expect(window.localDateStart, DateTime(2026, 9, 28));
    expect(window.localDateStart.hour, 0);
    expect(window.coversAtLeast48Hours, isTrue);
    _assertWithinBackendLimit(window);
  });

  test('33-day stale watermark becomes bounded 30-day resync', () {
    const offsetMinutes = 420;
    final cutoff = DateTime.utc(2026, 10, 1, 8);
    final window = SyncReplacementWindow.forSync(
      cutoffUtc: cutoff,
      timezoneOffsetMinutes: offsetMinutes,
      previousWatermarkUtc: cutoff.subtract(const Duration(days: 33)),
      firstSync: false,
    );
    expect(window.localDateStart, DateTime(2026, 9, 1));
    expect(window.localDateStart.hour, 0);
    expect(window.startUtc, DateTime.utc(2026, 8, 31, 17));
    expect(window.endUtcExclusive, cutoff);
    expect(window.localDateEndExclusive, DateTime(2026, 10, 2));
    _assertWithinBackendLimit(window);
  });

  test('60-day stale watermark becomes the same bounded resync', () {
    const offsetMinutes = 420;
    final cutoff = DateTime.utc(2026, 10, 1, 8);
    final bounded33 = SyncReplacementWindow.forSync(
      cutoffUtc: cutoff,
      timezoneOffsetMinutes: offsetMinutes,
      previousWatermarkUtc: cutoff.subtract(const Duration(days: 33)),
      firstSync: false,
    );
    final window = SyncReplacementWindow.forSync(
      cutoffUtc: cutoff,
      timezoneOffsetMinutes: offsetMinutes,
      previousWatermarkUtc: cutoff.subtract(const Duration(days: 60)),
      firstSync: false,
    );
    expect(window.startUtc, bounded33.startUtc);
    expect(window.localDateStart, DateTime(2026, 9, 1));
    expect(window.utcDuration, lessThan(const Duration(days: 62)));
    _assertWithinBackendLimit(window);
  });

  test('future watermark is clamped to cutoff', () {
    final cutoff = DateTime.utc(2026, 10, 1, 8);
    final window = SyncReplacementWindow.forSync(
      cutoffUtc: cutoff,
      timezoneOffsetMinutes: 420,
      previousWatermarkUtc: cutoff.add(const Duration(hours: 24)),
      firstSync: false,
    );
    expect(window.endUtcExclusive, cutoff);
    expect(window.startUtc, DateTime.utc(2026, 9, 28, 17));
    expect(window.localDateStart, DateTime(2026, 9, 29));
    expect(window.coversAtLeast48Hours, isTrue);
    _assertWithinBackendLimit(window);
  });

  test('initial sync remains bounded to 30 local calendar days', () {
    final cutoff = DateTime.utc(2026, 9, 30, 8);
    final window = SyncReplacementWindow.forSync(
      cutoffUtc: cutoff,
      timezoneOffsetMinutes: 420,
      firstSync: true,
    );
    expect(window.localDateStart, DateTime(2026, 8, 31));
    expect(window.startUtc, DateTime.utc(2026, 8, 30, 17));
    expect(window.endUtcExclusive, cutoff);
    expect(window.coversAtLeast30Days, isTrue);
    _assertWithinBackendLimit(window);
  });

  test('negative timezone offset stays below backend maximum', () {
    final cutoff = DateTime.utc(2026, 10, 1, 7, 59);
    final window = SyncReplacementWindow.forSync(
      cutoffUtc: cutoff,
      timezoneOffsetMinutes: -480,
      previousWatermarkUtc: cutoff.subtract(const Duration(days: 60)),
      firstSync: false,
    );
    expect(window.localDateStart, DateTime(2026, 8, 31));
    expect(window.startUtc, DateTime.utc(2026, 8, 31, 8));
    expect(window.endUtcExclusive, cutoff);
    _assertWithinBackendLimit(window);
  });

  test('containment helpers use half-open UTC and local-date bounds', () {
    final window = SyncReplacementWindow(
      startUtc: DateTime.utc(2026, 9, 27, 17),
      endUtcExclusive: DateTime.utc(2026, 9, 30, 8, 30),
      localDateStart: DateTime(2026, 9, 28),
      localDateEndExclusive: DateTime(2026, 10, 1),
      timezoneOffsetMinutes: 420,
    );

    expect(window.containsUtc(DateTime.utc(2026, 9, 27, 16, 59, 59)), isFalse);
    expect(window.containsUtc(window.startUtc), isTrue);
    expect(
      window.containsUtc(
        window.endUtcExclusive.subtract(const Duration(microseconds: 1)),
      ),
      isTrue,
    );
    expect(window.containsUtc(window.endUtcExclusive), isFalse);

    expect(window.containsLocalDate(DateTime(2026, 9, 27, 23, 59)), isFalse);
    expect(window.containsLocalDate(DateTime(2026, 9, 28, 12)), isTrue);
    expect(window.containsLocalDate(DateTime(2026, 9, 30, 23, 59)), isTrue);
    expect(window.containsLocalDate(DateTime(2026, 10, 1)), isFalse);
  });
}
