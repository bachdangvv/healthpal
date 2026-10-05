import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/health_records.dart';

const unknownHealthConnectSourceId = 'health_connect_unknown';

String effectiveSourceId({
  required String sourceId,
  required String sourceName,
}) {
  final id = sourceId.trim();
  if (id.isNotEmpty) return id;
  final name = sourceName.trim();
  if (name.isNotEmpty) return name;
  return unknownHealthConnectSourceId;
}

String childRecordId({
  required String parentRecordId,
  required String recordType,
  required String sourceId,
  required DateTime startUtc,
  required DateTime endUtc,
  required String discriminator,
}) {
  final payload = [
    parentRecordId,
    recordType,
    sourceId,
    startUtc.toUtc().toIso8601String(),
    endUtc.toUtc().toIso8601String(),
    discriminator,
  ].join('|');
  return sha256.convert(utf8.encode(payload)).toString();
}

String recordHash({
  required String type,
  required String sourceId,
  required DateTime startUtc,
  required DateTime endUtc,
  required num roundedValue,
}) {
  final payload =
      '$type|$sourceId|${startUtc.toUtc().toIso8601String()}|${endUtc.toUtc().toIso8601String()}|$roundedValue';
  return sha256.convert(utf8.encode(payload)).toString();
}

String identityOf({required String recordId, required String hash}) =>
    recordId.isNotEmpty ? recordId : hash;

DateTime localDateOf(DateTime utc, int zoneOffsetMinutes) {
  final local = utc.toUtc().add(Duration(minutes: zoneOffsetMinutes));
  return DateTime(local.year, local.month, local.day);
}

DateTime localHourFloor(DateTime utc, int zoneOffsetMinutes) {
  final local = utc.toUtc().add(Duration(minutes: zoneOffsetMinutes));
  final floor = DateTime(local.year, local.month, local.day, local.hour);
  return DateTime.utc(
    floor.year,
    floor.month,
    floor.day,
    floor.hour,
  ).subtract(Duration(minutes: zoneOffsetMinutes));
}

const huaweiSourceHints = ['healthsync', 'huawei', 'band 10', 'band10'];

bool looksLikeHuaweiSource(SourceInfo source) {
  final haystack = '${source.sourceId} ${source.sourceName}'.toLowerCase();
  return huaweiSourceHints.any(haystack.contains);
}
