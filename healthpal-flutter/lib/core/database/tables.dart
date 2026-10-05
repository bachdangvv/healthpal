import 'package:drift/drift.dart';

class HealthRecordsRawIndex extends Table {
  TextColumn get userId => text()();
  TextColumn get recordId => text()();
  TextColumn get recordHash => text()();
  TextColumn get recordType => text()();
  TextColumn get sourceId => text()();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime()();
  DateTimeColumn get modifiedAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, recordId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, recordHash},
  ];
}

class HeartRateSamples extends Table {
  TextColumn get userId => text()();
  TextColumn get recordId => text()();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime()();
  IntColumn get zoneOffsetMinutes => integer()();
  RealColumn get bpm => real()();
  TextColumn get sourceId => text()();
  TextColumn get sourceName => text()();
  DateTimeColumn get modifiedAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, recordId};
}

class StepIntervals extends Table {
  TextColumn get userId => text()();
  TextColumn get recordId => text()();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime()();
  IntColumn get zoneOffsetMinutes => integer()();
  IntColumn get count => integer()();
  TextColumn get sourceId => text()();
  TextColumn get sourceName => text()();
  DateTimeColumn get modifiedAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, recordId};
}

class RestingHeartRateRecords extends Table {
  TextColumn get userId => text()();
  TextColumn get recordId => text()();
  DateTimeColumn get recordedAtUtc => dateTime()();
  IntColumn get zoneOffsetMinutes => integer()();
  DateTimeColumn get localDate => dateTime()();
  RealColumn get bpm => real()();
  TextColumn get sourceId => text()();
  TextColumn get sourceName => text()();
  DateTimeColumn get modifiedAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, recordId};
}

class SleepSessions extends Table {
  TextColumn get userId => text()();
  TextColumn get recordId => text()();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime()();
  IntColumn get zoneOffsetMinutes => integer()();
  DateTimeColumn get healthDay => dateTime()();
  IntColumn get asleepMinutesAggregate => integer().nullable()();
  TextColumn get sourceId => text()();
  TextColumn get sourceName => text()();
  DateTimeColumn get modifiedAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, recordId};
}

class SleepStages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text()();
  TextColumn get sessionRecordId => text()();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime()();
  TextColumn get stageType => text()();
}

class ExerciseSessions extends Table {
  TextColumn get userId => text()();
  TextColumn get recordId => text()();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime()();
  IntColumn get zoneOffsetMinutes => integer()();
  TextColumn get type => text()();
  TextColumn get title => text().nullable()();
  IntColumn get durationMinutes => integer()();
  RealColumn get calories => real().nullable()();
  TextColumn get sourceId => text()();
  TextColumn get sourceName => text()();
  DateTimeColumn get modifiedAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, recordId};
}

class ActiveCaloriesIntervals extends Table {
  TextColumn get userId => text()();
  TextColumn get recordId => text()();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime()();
  IntColumn get zoneOffsetMinutes => integer()();
  RealColumn get kilocalories => real()();
  TextColumn get sourceId => text()();
  TextColumn get sourceName => text()();
  DateTimeColumn get modifiedAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, recordId};
}

class HourlyHealthBins extends Table {
  TextColumn get userId => text()();
  DateTimeColumn get hourUtc => dateTime()();
  IntColumn get zoneOffsetMinutes => integer()();
  RealColumn get hrMean => real().nullable()();
  RealColumn get hrMin => real().nullable()();
  RealColumn get hrMax => real().nullable()();
  IntColumn get hrSampleCount => integer().withDefault(const Constant(0))();
  IntColumn get steps => integer().nullable()();
  RealColumn get activeCalories => real().nullable()();
  TextColumn get sourceId => text()();
  BoolColumn get coverageComplete =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, hourUtc, sourceId};
}

class DailyHealthSummaries extends Table {
  TextColumn get userId => text()();
  DateTimeColumn get localDate => dateTime()();
  TextColumn get timezone => text()();
  IntColumn get sleepMinutes => integer().nullable()();
  IntColumn get steps => integer().nullable()();
  RealColumn get averageHeartRate => real().nullable()();
  RealColumn get minHeartRate => real().nullable()();
  RealColumn get maxHeartRate => real().nullable()();
  RealColumn get restingHeartRate => real().nullable()();
  RealColumn get activeCalories => real().nullable()();
  IntColumn get exerciseCount => integer().withDefault(const Constant(0))();
  IntColumn get exerciseDurationMinutes =>
      integer().withDefault(const Constant(0))();
  TextColumn get coverageFlagsJson =>
      text().withDefault(const Constant('{}'))();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, localDate};
}

class FatigueAssessments extends Table {
  TextColumn get userId => text()();
  TextColumn get id => text()();
  DateTimeColumn get evaluatedAtUtc => dateTime()();
  DateTimeColumn get localDate => dateTime()();
  TextColumn get modelVersion => text()();
  RealColumn get baseProbability => real().nullable()();
  RealColumn get calibratedProbability => real().nullable()();
  RealColumn get threshold => real()();
  TextColumn get status => text()();
  IntColumn get coverageHours => integer()();
  DateTimeColumn get latestSampleAtUtc => dateTime().nullable()();
  IntColumn get dataFreshnessMinutes => integer().nullable()();
  TextColumn get missingReasonsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get featureVectorHash => text()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, evaluatedAtUtc, modelVersion},
  ];
}

class SyncStates extends Table {
  TextColumn get userId => text()();
  DateTimeColumn get lastSuccessfulSyncAtUtc => dateTime().nullable()();
  DateTimeColumn get sourceWatermarkUtc => dateTime().nullable()();
  DateTimeColumn get latestDataAtUtc => dateTime().nullable()();
  TextColumn get changeToken => text().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get lastCompletedPhase => text().nullable()();
  IntColumn get pendingOutboxCount =>
      integer().withDefault(const Constant(0))();
  TextColumn get preferredSourceId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class OutboxEvents extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get idempotencyKey => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get payloadJson => text()();
  TextColumn get payloadHash => text()();
  DateTimeColumn get createdAtUtc => dateTime()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAtUtc => dateTime().nullable()();
  BoolColumn get deadLettered => boolean().withDefault(const Constant(false))();
  DateTimeColumn get sentAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, idempotencyKey},
  ];
}

class CachedProfiles extends Table {
  TextColumn get userId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get cachedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}
