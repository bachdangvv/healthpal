import '../../../src/rust/api.dart' as rust;

abstract interface class FatigueEngine {
  Future<void> ensureInitialized();
  rust.ModelInfo modelInfo();
  rust.AssessmentResult assess(rust.AssessmentRequest request);
}

class NativeFatigueEngine implements FatigueEngine {
  const NativeFatigueEngine();

  @override
  Future<void> ensureInitialized() => rust.initHealthpalRust();

  @override
  rust.ModelInfo modelInfo() => rust.modelInfo();

  @override
  rust.AssessmentResult assess(rust.AssessmentRequest request) =>
      rust.assess(request: request);
}
