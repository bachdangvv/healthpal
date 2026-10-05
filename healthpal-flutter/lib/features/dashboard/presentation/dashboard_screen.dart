import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../theme/healthpal_brand.dart';
import '../../../theme/healthpal_theme.dart';
import '../../assessment/domain/fatigue_assessment.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_user.dart';
import '../../profile/data/profile_repository.dart';
import '../application/dashboard_controller.dart';
import '../data/health_connect_repository.dart';
import '../domain/dashboard_models.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.authController,
    required this.repository,
    required this.profileRepository,
    required this.user,
    this.syncGeneration = 0,
  });

  final AuthController authController;
  final HealthConnectRepository repository;
  final ProfileRepository profileRepository;
  final AuthUser user;
  final int syncGeneration;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late DashboardController _dashboard;
  int _dailyStepGoal = 8000;
  bool _experimentalFatigueConsent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dashboard = DashboardController(repository: widget.repository)
      ..addListener(_onChanged);
    widget.profileRepository.ensure(widget.user);
    unawaited(_dashboard.refresh());
    unawaited(_loadGoal());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh(userInitiated: false));
    }
  }

  Future<void> _loadGoal() async {
    try {
      final profile = await widget.profileRepository.fetch(widget.user.id);
      if (mounted) {
        setState(() {
          _dailyStepGoal = profile.dailyStepGoal;
          _experimentalFatigueConsent = profile.experimentalFatigueConsent;
        });
      }
    } catch (_) {
      // The default goal keeps the Dashboard usable when the profile is unavailable.
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _dashboard
        ..removeListener(_onChanged)
        ..dispose();
      _dashboard = DashboardController(repository: widget.repository)
        ..addListener(_onChanged);
      unawaited(_dashboard.refresh());
    } else if (oldWidget.syncGeneration != widget.syncGeneration) {
      unawaited(_dashboard.load());
      unawaited(_loadGoal());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dashboard
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _refresh({bool userInitiated = true}) async {
    await _dashboard.refresh(userInitiated: userInitiated);
    await _loadGoal();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _dashboard.snapshot;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 265,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.topRight,
                  colors: [Color(0xFFFFC4C5), Color(0xFFDCCEFF)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              key: const Key('dashboard-refresh'),
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    sliver: SliverToBoxAdapter(child: _header()),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverToBoxAdapter(child: _statusCard(snapshot)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    sliver: SliverToBoxAdapter(child: _buildContent(snapshot)),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final now = DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chào buổi sáng,',
                style: TextStyle(
                  fontSize: 13,
                  color: HealthPalColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Tổng quan sức khỏe · ${now.day}/${now.month}/${now.year}',
                style: const TextStyle(
                  fontSize: 12,
                  color: HealthPalColors.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            shape: BoxShape.circle,
          ),
          child: const HealthPalLogo(size: 48, borderRadius: 24),
        ),
      ],
    );
  }

  Widget _statusCard(HealthConnectSnapshot? snapshot) {
    final status = snapshot?.status;
    final busy = _dashboard.isLoading || _dashboard.isRequestingPermissions;
    final color = switch (status) {
      DashboardDataStatus.connected => const Color(0xFF2DA66E),
      DashboardDataStatus.missingPermissions => const Color(0xFFF0A52B),
      DashboardDataStatus.noData => const Color(0xFF7A72D8),
      DashboardDataStatus.needsSync => const Color(0xFFEA9B23),
      DashboardDataStatus.unavailable || null => const Color(0xFFE04B59),
    };
    final title = switch (status) {
      DashboardDataStatus.connected => 'Đã kết nối',
      DashboardDataStatus.missingPermissions => 'Thiếu quyền',
      DashboardDataStatus.noData => 'Không có dữ liệu',
      DashboardDataStatus.needsSync => 'Cần đồng bộ',
      DashboardDataStatus.unavailable || null => 'Health Connect chưa sẵn sàng',
    };
    return Container(
      key: const Key('dashboard-health-status'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0712162E),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(CupertinoIcons.chevron_right, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _statusDescription(snapshot),
            key: const Key('dashboard-status-description'),
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: HealthPalColors.secondary,
            ),
          ),
          if (snapshot?.lastSyncedAt != null) ...[
            const SizedBox(height: 5),
            Text(
              'Đồng bộ HealthPal lúc ${_time(snapshot!.lastSyncedAt!)}',
              style: const TextStyle(
                fontSize: 11,
                color: HealthPalColors.secondary,
              ),
            ),
          ],
          if (snapshot?.latestDataAt != null) ...[
            const SizedBox(height: 3),
            Text(
              'Dữ liệu mới nhất lúc ${_time(snapshot!.latestDataAt!)}',
              style: const TextStyle(
                fontSize: 11,
                color: HealthPalColors.secondary,
              ),
            ),
          ],
          if (status == DashboardDataStatus.missingPermissions) ...[
            const SizedBox(height: 10),
            Text(
              snapshot!.missingPermissions
                  .map((item) => item.label)
                  .join(' · '),
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('dashboard-request-permissions'),
                    onPressed: busy ? null : _dashboard.requestPermissions,
                    child: const Text('Cấp quyền'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('dashboard-open-settings'),
                  onPressed: busy ? null : _dashboard.openSettings,
                  child: const Text('Quản lý'),
                ),
              ],
            ),
          ] else if (status == DashboardDataStatus.unavailable) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('dashboard-sync'),
                    onPressed: busy ? null : _refresh,
                    child: const Text('Thử lại'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('dashboard-open-settings'),
                  onPressed: busy ? null : _dashboard.openSettings,
                  child: const Text('Quản lý'),
                ),
              ],
            ),
          ] else if (status != null) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('dashboard-sync-health-data'),
              onPressed: busy ? null : _refresh,
              icon: const Icon(CupertinoIcons.arrow_2_circlepath, size: 18),
              label: const Text('Đồng bộ dữ liệu sức khỏe'),
            ),
          ],
        ],
      ),
    );
  }

  String _statusDescription(HealthConnectSnapshot? snapshot) {
    return switch (snapshot?.status) {
      DashboardDataStatus.connected => 'Dữ liệu hôm nay đã được cập nhật.',
      DashboardDataStatus.missingPermissions =>
        'Cần cấp quyền đọc các chỉ số HealthPal sử dụng.',
      DashboardDataStatus.noData =>
        'Health Connect chưa có bản ghi sức khỏe cho hôm nay.',
      DashboardDataStatus.needsSync =>
        'Dữ liệu đã cũ, hãy đồng bộ để cập nhật Dashboard.',
      DashboardDataStatus.unavailable || null =>
        'Thiết bị chưa cung cấp Health Connect hoặc ứng dụng chưa sẵn sàng.',
    };
  }

  Widget _buildContent(HealthConnectSnapshot? snapshot) {
    if (_dashboard.isLoading && snapshot == null) {
      return const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final summary = snapshot?.summary;
    final incomplete =
        summary == null ||
        summary.sleepMinutes == null ||
        summary.restingHeartRate == null;
    return Column(
      key: const Key('dashboard-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (incomplete &&
            snapshot?.status != DashboardDataStatus.unavailable) ...[
          _notice(
            'Dữ liệu hôm nay chưa đầy đủ',
            'Một số chỉ số chưa được smartwatch hoặc Health Connect cung cấp.',
          ),
          const SizedBox(height: 12),
        ],
        _stepsCard(summary),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _metricCard(
                icon: CupertinoIcons.moon_fill,
                color: const Color(0xFF6656D9),
                title: 'Giấc ngủ',
                value: _sleep(summary?.sleepMinutes),
                unit: '',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                icon: CupertinoIcons.heart_fill,
                color: const Color(0xFFEC4565),
                title: 'Nhịp tim',
                value: _number(summary?.averageHeartRate),
                unit: 'bpm',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _metricCard(
                icon: CupertinoIcons.waveform_path_ecg,
                color: const Color(0xFF4B7BE5),
                title: 'Nhịp tim nghỉ',
                value: _number(summary?.restingHeartRate),
                unit: 'bpm',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                icon: CupertinoIcons.waveform_path_ecg,
                color: const Color(0xFF4B7BE5),
                title: 'HRV',
                value: _number(summary?.hrv),
                unit: 'ms',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _metricCard(
          icon: CupertinoIcons.flame_fill,
          color: const Color(0xFFEA9B23),
          title: 'Calories vận động (không dùng cho model)',
          value: _number(summary?.activeCalories),
          unit: 'kcal',
        ),
        const SizedBox(height: 12),
        _fatigueCard(snapshot),
      ],
    );
  }

  Widget _stepsCard(TodayHealthSummary? summary) {
    final steps = summary?.steps;
    final progress = steps == null
        ? null
        : (steps / _dailyStepGoal).clamp(0.0, 1.0);
    return _card(
      key: const Key('dashboard-steps-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(
            Icons.directions_walk_rounded,
            'Số bước',
            const Color(0xFFEE7A35),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  steps == null ? 'Chưa có dữ liệu' : _formatInt(steps),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (steps != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '/ ${_formatInt(_dailyStepGoal)} bước',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: HealthPalColors.secondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                color: const Color(0xFFEE7A35),
                backgroundColor: const Color(0xFFFFE8D7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String unit,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(icon, title, color),
          const SizedBox(height: 14),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (unit.isNotEmpty && value != 'Chưa có dữ liệu')
            Text(
              unit,
              style: const TextStyle(
                fontSize: 11,
                color: HealthPalColors.secondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _fatigueCard(HealthConnectSnapshot? snapshot) {
    if (!AppConfig.experimentalFatigueAssessment ||
        snapshot?.showExperimentalFatigue == false ||
        !_experimentalFatigueConsent) {
      return const SizedBox.shrink();
    }
    final assessment = snapshot?.fatigue;
    final status = assessment?.status;
    final label = assessment?.statusLabel ?? 'Chưa đủ dữ liệu';
    return _card(
      key: const Key('dashboard-fatigue-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(
            CupertinoIcons.waveform_path_ecg,
            'Tín hiệu mệt mỏi thử nghiệm',
            const Color(0xFFF05D7B),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            key: const Key('dashboard-fatigue-status'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (status == FatigueAssessmentStatus.insufficientData &&
              (assessment?.missingReasons.isNotEmpty ?? false)) ...[
            const SizedBox(height: 6),
            Text(
              assessment!.missingReasons.join(' · '),
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: HealthPalColors.secondary,
              ),
            ),
          ],
          if (status == FatigueAssessmentStatus.suppressedDuringExercise) ...[
            const SizedBox(height: 6),
            const Text(
              'HealthPal tạm hoãn đánh giá vì vừa có phiên tập luyện.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: HealthPalColors.secondary,
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Kết quả chỉ mang tính tham khảo. Không dùng làm chẩn đoán y tế.',
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: HealthPalColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String title, String message) => Container(
    key: const Key('dashboard-incomplete-notice'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(
          CupertinoIcons.info_circle_fill,
          size: 20,
          color: Color(0xFFEA9B23),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: HealthPalColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _card({required Widget child, Key? key}) => Container(
    key: key,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0712162E),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: child,
  );

  Widget _cardTitle(IconData icon, String title, Color color) => Row(
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  String _sleep(int? minutes) => minutes == null
      ? 'Chưa có dữ liệu'
      : '${minutes ~/ 60}h ${minutes % 60}m';

  String _number(double? value) =>
      value == null ? 'Chưa có dữ liệu' : value.round().toString();

  String _formatInt(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
