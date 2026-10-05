import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/healthpal_theme.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_user.dart';
import '../../dashboard/data/health_connect_repository.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../history/data/health_history_repository.dart';
import '../../history/presentation/history_analytics_screen.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_settings_screen.dart';
import '../../training/data/exercise_repository.dart';
import '../../training/data/training_readiness_repository.dart';
import '../../training/presentation/training_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.authController,
    required this.historyRepository,
    required this.profileRepository,
    required this.dashboardRepository,
    required this.trainingReadinessRepository,
    required this.exerciseRepository,
    required this.user,
    this.onForegroundSync,
    this.onSyncSettingsChanged,
  });

  final AuthController authController;
  final HealthHistoryRepository historyRepository;
  final ProfileRepository profileRepository;
  final HealthConnectRepository dashboardRepository;
  final TrainingReadinessRepository trainingReadinessRepository;
  final ExerciseRepository exerciseRepository;
  final AuthUser user;
  final Future<void> Function()? onForegroundSync;
  final Future<void> Function()? onSyncSettingsChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _syncGeneration = 0;
  DateTime? _lastResumeSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_runForegroundSync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_runForegroundSync(debounce: true));
  }

  Future<void> _runForegroundSync({bool debounce = false}) async {
    final now = DateTime.now();
    if (debounce &&
        _lastResumeSync != null &&
        now.difference(_lastResumeSync!) < const Duration(seconds: 30)) {
      return;
    }
    _lastResumeSync = now;
    await widget.onForegroundSync?.call();
    if (mounted) setState(() => _syncGeneration++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardScreen(
            authController: widget.authController,
            repository: widget.dashboardRepository,
            profileRepository: widget.profileRepository,
            user: widget.user,
            syncGeneration: _syncGeneration,
          ),
          TrainingScreen(
            readinessRepository: widget.trainingReadinessRepository,
            exerciseRepository: widget.exerciseRepository,
          ),
          HistoryAnalyticsScreen(
            authController: widget.authController,
            repository: widget.historyRepository,
            user: widget.user,
            syncGeneration: _syncGeneration,
            onOpenProfile: () => setState(() => _selectedIndex = 3),
          ),
          ProfileSettingsScreen(
            authController: widget.authController,
            repository: widget.profileRepository,
            user: widget.user,
            healthConnect: widget.dashboardRepository,
            onProfileChanged: () async {
              if (mounted) setState(() => _syncGeneration++);
            },
            onSyncSettingsChanged: () async {
              await widget.onSyncSettingsChanged?.call();
              if (mounted) setState(() => _syncGeneration++);
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        key: const Key('home-navigation'),
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _navItem(
              0,
              Icons.dashboard_outlined,
              Icons.dashboard_rounded,
              'Tổng quan',
            ),
            _navItem(
              1,
              Icons.fitness_center_outlined,
              Icons.fitness_center_rounded,
              'Tập luyện',
            ),
            _navItem(
              2,
              Icons.insights_outlined,
              Icons.insights_rounded,
              'Lịch sử',
            ),
            _navItem(3, Icons.person_outline, Icons.person_rounded, 'Hồ sơ'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    int index,
    IconData icon,
    IconData selectedIcon,
    String label,
  ) {
    final selected = _selectedIndex == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          key: Key(
            'nav-${switch (index) {
              0 => 'dashboard',
              1 => 'training',
              2 => 'history',
              _ => 'profile',
            }}',
          ),
          onTap: () => setState(() => _selectedIndex = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : HealthPalColors.secondary,
                  size: 22,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : HealthPalColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
