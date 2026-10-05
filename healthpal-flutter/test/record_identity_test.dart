import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/health_connect/application/record_identity.dart';
import 'package:healthpal/features/health_connect/domain/health_records.dart';

void main() {
  test('effectiveSourceId prefers sourceId then sourceName then sentinel', () {
    expect(
      effectiveSourceId(sourceId: 'abc', sourceName: 'Health Sync'),
      'abc',
    );
    expect(
      effectiveSourceId(
        sourceId: '  ',
        sourceName: 'com.github.yourapp.healthsync',
      ),
      'com.github.yourapp.healthsync',
    );
    expect(
      effectiveSourceId(sourceId: '', sourceName: ''),
      unknownHealthConnectSourceId,
    );
  });

  test('childRecordId is deterministic and independent of list index', () {
    final start = DateTime.utc(2026, 9, 30, 8, 1);
    final first = childRecordId(
      parentRecordId: 'parent',
      recordType: 'heart_rate',
      sourceId: 'com.github.yourapp.healthsync',
      startUtc: start,
      endUtc: start,
      discriminator: 'sample',
    );
    final second = childRecordId(
      parentRecordId: 'parent',
      recordType: 'heart_rate',
      sourceId: 'com.github.yourapp.healthsync',
      startUtc: start,
      endUtc: start,
      discriminator: 'sample',
    );
    expect(first, second);
    expect(first, hasLength(64));
    expect(
      childRecordId(
        parentRecordId: 'parent',
        recordType: 'heart_rate',
        sourceId: 'com.github.yourapp.healthsync',
        startUtc: start,
        endUtc: start,
        discriminator: 'sample',
      ),
      isNot(
        childRecordId(
          parentRecordId: 'parent',
          recordType: 'heart_rate',
          sourceId: 'com.github.yourapp.healthsync',
          startUtc: start.add(const Duration(minutes: 1)),
          endUtc: start.add(const Duration(minutes: 1)),
          discriminator: 'sample',
        ),
      ),
    );
  });

  test('looksLikeHuaweiSource matches Health Sync package fallback', () {
    expect(
      looksLikeHuaweiSource(
        const SourceInfo(
          sourceId: 'com.github.yourapp.healthsync',
          sourceName: 'Health Sync',
        ),
      ),
      isTrue,
    );
    expect(
      looksLikeHuaweiSource(
        const SourceInfo(sourceId: 'phone.steps', sourceName: 'Phone'),
      ),
      isFalse,
    );
  });
}
