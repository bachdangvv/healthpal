import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/user_health_runtime.dart';
import '../../../theme/healthpal_theme.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import '../../history/data/health_history_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../dashboard/data/health_connect_repository.dart';
import '../../home/presentation/home_shell.dart';
import '../../training/data/exercise_repository.dart';
import '../../training/data/training_readiness_repository.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// A private screen is removed on logout, not kept in the back stack.
class AuthFlow extends StatefulWidget {
  const AuthFlow({
    super.key,
    required this.controller,
    required this.historyRepository,
    required this.profileRepository,
    required this.dashboardRepository,
    required this.trainingReadinessRepository,
    required this.exerciseRepository,
    this.runtimeFactory,
  });

  final AuthController controller;
  final HealthHistoryRepository historyRepository;
  final ProfileRepository profileRepository;
  final HealthConnectRepository dashboardRepository;
  final TrainingReadinessRepository trainingReadinessRepository;
  final ExerciseRepository exerciseRepository;
  final UserHealthRuntimeFactory? runtimeFactory;

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  bool _showRegister = false;
  UserHealthRuntime? _runtime;
  bool _bindingRuntime = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onAuthChanged);
    final user = widget.controller.user;
    if (user != null) unawaited(_ensureRuntime());
  }

  @override
  void didUpdateWidget(covariant AuthFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onAuthChanged);
      widget.controller.addListener(_onAuthChanged);
    }
  }

  void _onAuthChanged() {
    final user = widget.controller.user;
    if (user == null) {
      unawaited(_disposeRuntime());
    } else {
      unawaited(_ensureRuntime());
    }
    if (!mounted) return;
    setState(() {
      if (user != null) _showRegister = false;
    });
  }

  Future<void> _ensureRuntime() async {
    final factory = widget.runtimeFactory;
    if (factory == null) return;
    if (_bindingRuntime) return;
    _bindingRuntime = true;
    try {
      while (mounted) {
        final user = widget.controller.user;
        if (user == null) {
          await _disposeRuntime();
          return;
        }
        if (_runtime?.userId == user.id) return;
        await _disposeRuntime();
        final runtime = factory.create(user);
        if (widget.controller.user?.id != user.id) {
          await runtime.dispose();
          continue;
        }
        _runtime = runtime;
        unawaited(runtime.coordinator.reconcileScheduler());
        unawaited(runtime.coordinator.syncNow());
        return;
      }
    } finally {
      _bindingRuntime = false;
      if (mounted) setState(() {});
      final user = widget.controller.user;
      if (user != null && _runtime?.userId != user.id) {
        unawaited(_ensureRuntime());
      }
    }
  }

  Future<void> _disposeRuntime() async {
    final runtime = _runtime;
    _runtime = null;
    if (runtime != null) await runtime.dispose();
  }

  void _showRegistration(bool value) {
    if (widget.controller.isBusy) return;
    widget.controller.clearError();
    setState(() => _showRegister = value);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAuthChanged);
    unawaited(_disposeRuntime());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.controller;
    final user = auth.user;
    if (auth.isRestoring || _bindingRuntime) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(key: Key('auth-restoring')),
        ),
      );
    }
    if (user == null && auth.error?.code == AuthFailure.network) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Không thể kết nối máy chủ. Vui lòng thử lại.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HealthPalColors.secondary),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('auth-retry-restore'),
                  onPressed: auth.restoreSession,
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final waitingRuntime =
        user != null &&
        widget.runtimeFactory != null &&
        _runtime?.userId != user.id;
    if (waitingRuntime) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(key: Key('auth-restoring')),
        ),
      );
    }
    final history = _runtime?.history ?? widget.historyRepository;
    final dashboard = _runtime?.dashboard ?? widget.dashboardRepository;
    return PopScope(
      canPop: !_showRegister && !auth.isBusy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _showRegister && !auth.isBusy) _showRegistration(false);
      },
      child: user != null
          ? KeyedSubtree(
              key: ValueKey(user.id),
              child: HomeShell(
                key: const Key('history-screen'),
                authController: auth,
                historyRepository: history,
                profileRepository: widget.profileRepository,
                dashboardRepository: dashboard,
                trainingReadinessRepository: widget.trainingReadinessRepository,
                exerciseRepository: widget.exerciseRepository,
                user: user,
                onForegroundSync: _runtime == null
                    ? null
                    : () => _runtime!.coordinator.syncNow(),
                onSyncSettingsChanged: _runtime == null
                    ? null
                    : () async {
                        await _runtime!.coordinator.reconcileScheduler();
                        await _runtime!.coordinator.syncNow();
                      },
              ),
            )
          : _showRegister
          ? RegisterScreen(
              key: const Key('register-screen'),
              controller: auth,
              onLogin: () => _showRegistration(false),
            )
          : LoginScreen(
              key: const Key('login-screen'),
              controller: auth,
              onRegister: () => _showRegistration(true),
            ),
    );
  }
}
