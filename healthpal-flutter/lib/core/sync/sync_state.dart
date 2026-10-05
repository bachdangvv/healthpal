enum SyncPhase {
  checkCapabilities,
  readLookback,
  canonicalize,
  upsertLocal,
  recomputeAggregates,
  assess,
  enqueueOutbox,
  refreshUi,
}

class SyncState {
  const SyncState({
    this.lastSuccessfulSyncAtUtc,
    this.sourceWatermarkUtc,
    this.latestDataAtUtc,
    this.changeToken,
    this.lastError,
    this.lastCompletedPhase,
    this.pendingOutboxCount = 0,
    this.preferredSourceId,
  });

  final DateTime? lastSuccessfulSyncAtUtc;
  final DateTime? sourceWatermarkUtc;
  final DateTime? latestDataAtUtc;
  final String? changeToken;
  final String? lastError;
  final SyncPhase? lastCompletedPhase;
  final int pendingOutboxCount;
  final String? preferredSourceId;

  bool get hasPendingUpload => pendingOutboxCount > 0;

  factory SyncState.fromJson(Map<String, dynamic> json) => SyncState(
    lastSuccessfulSyncAtUtc: _parseTime(json['lastSuccessfulSyncAtUtc']),
    sourceWatermarkUtc: _parseTime(json['sourceWatermarkUtc']),
    latestDataAtUtc: _parseTime(json['latestDataAtUtc']),
    changeToken: json['changeToken'] as String?,
    lastError: json['lastError'] as String?,
    lastCompletedPhase: json['lastCompletedPhase'] == null
        ? null
        : SyncPhase.values.byName(json['lastCompletedPhase'] as String),
    pendingOutboxCount: json['pendingOutboxCount'] as int? ?? 0,
    preferredSourceId: json['preferredSourceId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'lastSuccessfulSyncAtUtc': lastSuccessfulSyncAtUtc
        ?.toUtc()
        .toIso8601String(),
    'sourceWatermarkUtc': sourceWatermarkUtc?.toUtc().toIso8601String(),
    'latestDataAtUtc': latestDataAtUtc?.toUtc().toIso8601String(),
    'changeToken': changeToken,
    'lastError': lastError,
    'lastCompletedPhase': lastCompletedPhase?.name,
    'pendingOutboxCount': pendingOutboxCount,
    'preferredSourceId': preferredSourceId,
  };
}

class OutboxEvent {
  const OutboxEvent({
    required this.id,
    required this.idempotencyKey,
    required this.schemaVersion,
    required this.payloadHash,
    required this.createdAtUtc,
    this.attemptCount = 0,
    this.lastAttemptAtUtc,
    this.deadLettered = false,
  });

  final String id;
  final String idempotencyKey;
  final int schemaVersion;
  final String payloadHash;
  final DateTime createdAtUtc;
  final int attemptCount;
  final DateTime? lastAttemptAtUtc;
  final bool deadLettered;

  factory OutboxEvent.fromJson(Map<String, dynamic> json) => OutboxEvent(
    id: json['id'] as String,
    idempotencyKey: json['idempotencyKey'] as String,
    schemaVersion: json['schemaVersion'] as int,
    payloadHash: json['payloadHash'] as String,
    createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
    attemptCount: json['attemptCount'] as int? ?? 0,
    lastAttemptAtUtc: json['lastAttemptAtUtc'] == null
        ? null
        : DateTime.parse(json['lastAttemptAtUtc'] as String),
    deadLettered: json['deadLettered'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'idempotencyKey': idempotencyKey,
    'schemaVersion': schemaVersion,
    'payloadHash': payloadHash,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'attemptCount': attemptCount,
    'lastAttemptAtUtc': lastAttemptAtUtc?.toUtc().toIso8601String(),
    'deadLettered': deadLettered,
  };
}

DateTime? _parseTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
