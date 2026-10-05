import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../src/rust/types.dart' as rust;
import '../../health_connect/application/canonicalizer.dart';
import '../../health_connect/domain/health_records.dart';
import '../domain/fatigue_assessment.dart';
import 'assessment_request_factory.dart';
import 'fatigue_engine.dart';

class FatigueAssessmentRunner {
  FatigueAssessmentRunner({
    FatigueEngine? engine,
    this.factory = const AssessmentRequestFactory(),
  }) : engine = engine ?? const NativeFatigueEngine();

  final FatigueEngine engine;
  final AssessmentRequestFactory factory;
  static const _uuid = Uuid();
  bool _validated = false;

  Future<void> ensureReady() async {
    await engine.ensureInitialized();
    if (_validated) return;
    final info = engine.modelInfo();
    if (info.modelVersion != AppConfig.fatigueModelVersion) {
      throw rust.AssessmentException(
        kind: 'model',
        code: 'model_version_mismatch',
        message: 'expected ${AppConfig.fatigueModelVersion}',
      );
    }
    if ((info.threshold - AppConfig.fatigueDecisionThreshold).abs() > 1e-12) {
      throw rust.AssessmentException(
        kind: 'model',
        code: 'threshold_mismatch',
        message: 'frozen V4 threshold mismatch',
      );
    }
    _validated = true;
  }

  Future<FatigueAssessment> run({
    required CanonicalIngestion canonical,
    required DateTime evaluationTimeUtc,
    required PermissionSnapshot permissions,
    required AssessmentCreatedBy createdBy,
    DateTime? dataWatermarkUtc,
    DateTime? previousAssessmentWatermarkUtc,
    int? timezoneOffsetMinutes,
  }) async {
    await ensureReady();
    final offset =
        timezoneOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes;
    final request = factory.fromCanonical(
      canonical: canonical,
      evaluationTimeUtc: evaluationTimeUtc,
      timezoneOffsetMinutes: offset,
      permissions: permissions,
      dataWatermarkUtc: dataWatermarkUtc,
      previousAssessmentWatermarkUtc: previousAssessmentWatermarkUtc,
    );
    final result = engine.assess(request);
    final local = evaluationTimeUtc.toUtc().add(Duration(minutes: offset));
    return FatigueAssessment(
      id: _uuid.v4(),
      evaluatedAtUtc: evaluationTimeUtc.toUtc(),
      localDate: DateTime(local.year, local.month, local.day),
      modelVersion: result.modelVersion,
      baseProbability: result.baseProbability,
      calibratedProbability: result.calibratedProbability,
      threshold: result.threshold,
      status: FatigueAssessmentStatus.values.byName(result.status.name),
      coverageHours: result.coverageHours,
      latestSampleAtUtc: result.latestSampleAtUtc,
      dataFreshnessMinutes: result.dataFreshnessMinutes,
      missingReasons: result.missingReasons,
      featureVectorHash: result.featureVectorHash,
      createdBy: createdBy,
    );
  }
}
