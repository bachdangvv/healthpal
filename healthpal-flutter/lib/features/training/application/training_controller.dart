import 'package:flutter/foundation.dart';

import '../data/training_readiness_repository.dart';
import '../domain/training_models.dart';
import 'training_readiness_rule_engine.dart';

class TrainingController extends ChangeNotifier {
  TrainingController({
    required this.repository,
    this.ruleEngine = const TrainingReadinessRuleEngine(),
  });

  final TrainingReadinessRepository repository;
  final TrainingReadinessRuleEngine ruleEngine;

  TrainingReadinessResult? result;
  bool isLoading = false;
  Object? error;

  Future<void> load() async {
    if (isLoading) return;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final input = await repository.fetchInput();
      result = ruleEngine.evaluate(input);
    } catch (exception) {
      error = exception;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
