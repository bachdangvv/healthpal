import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/healthpal_theme.dart';
import '../../../theme/healthpal_brand.dart';
import '../../assessment/domain/fatigue_assessment.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_user.dart';
import '../application/history_controller.dart';
import '../data/health_history_repository.dart';
import '../domain/daily_health_summary.dart';
import 'history_chart.dart';

class HistoryAnalyticsScreen extends StatefulWidget {
  const HistoryAnalyticsScreen({
    super.key,
    required this.authController,
    required this.repository,
    required this.user,
    this.syncGeneration = 0,
    this.onOpenProfile,
  });

  final AuthController authController;
  final HealthHistoryRepository repository;
  final AuthUser user;
  final int syncGeneration;
  final VoidCallback? onOpenProfile;

  @override
  State<HistoryAnalyticsScreen> createState() => _HistoryAnalyticsScreenState();
}

class _HistoryAnalyticsScreenState extends State<HistoryAnalyticsScreen> {
  late HistoryController _history;
  bool _confirmingLogout = false;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _history = HistoryController(repository: widget.repository)
      ..addListener(_onHistoryChanged);
    unawaited(_history.load());
  }

  @override
  void didUpdateWidget(covariant HistoryAnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _history
        ..removeListener(_onHistoryChanged)
        ..dispose();
      _createController();
    } else if (oldWidget.syncGeneration != widget.syncGeneration) {
      unawaited(_history.load());
    }
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _history
      ..removeListener(_onHistoryChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _confirmLogout() async {
    if (_confirmingLogout || widget.authController.isBusy) return;
    _confirmingLogout = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text(
          'Bạn có thể đăng nhập lại bằng tài khoản này trong phiên chạy hiện tại.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel-logout'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm-logout'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    _confirmingLogout = false;
    if (!mounted || confirmed != true) return;
    final success = await widget.authController.signOut();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa thể đăng xuất. Vui lòng thử lại.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: HealthPalColors.background,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 270,
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
                onRefresh: _history.retry,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      sliver: SliverToBoxAdapter(child: _buildHeader()),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(child: _buildPeriodSelector()),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 18),
                      sliver: SliverToBoxAdapter(child: _buildMetricSelector()),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      sliver: SliverToBoxAdapter(child: _buildContent()),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 22)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lịch sử sức khỏe',
                style: TextStyle(
                  fontSize: 30,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Quan sát thay đổi của cơ thể theo thời gian.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: HealthPalColors.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<_AccountAction>(
          key: const Key('history-account-menu'),
          tooltip: 'Tài khoản',
          onSelected: (action) {
            if (action == _AccountAction.logout) unawaited(_confirmLogout());
            if (action == _AccountAction.profile) widget.onOpenProfile?.call();
          },
          itemBuilder: (context) => [
            PopupMenuItem<_AccountAction>(
              enabled: false,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      style: const TextStyle(
                        color: HealthPalColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.user.email,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HealthPalColors.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<_AccountAction>(
              key: Key('history-menu-profile'),
              value: _AccountAction.profile,
              child: Row(
                children: [
                  Icon(CupertinoIcons.person_crop_circle, size: 20),
                  SizedBox(width: 12),
                  Text('Hồ sơ'),
                ],
              ),
            ),
            const PopupMenuItem<_AccountAction>(
              key: Key('history-menu-logout'),
              value: _AccountAction.logout,
              child: Row(
                children: [
                  Icon(CupertinoIcons.square_arrow_right, size: 20),
                  SizedBox(width: 12),
                  Text('Đăng xuất'),
                ],
              ),
            ),
          ],
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              shape: BoxShape.circle,
            ),
            child: const HealthPalLogo(size: 48, borderRadius: 24),
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    Widget option(HistoryPeriod period, String text, Key key) {
      final selected = _history.period == period;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: InkWell(
            key: key,
            onTap: _history.isLoading ? null : () => _history.setPeriod(period),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x0D12162E),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? HealthPalColors.ink
                      : HealthPalColors.secondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDECF3).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          option(
            HistoryPeriod.sevenDays,
            '7 ngày',
            const Key('history-period-7'),
          ),
          option(
            HistoryPeriod.thirtyDays,
            '30 ngày',
            const Key('history-period-30'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricSelector() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        key: const Key('history-metric-list'),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: HistoryMetric.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final metric = HistoryMetric.values[index];
          final selected = _history.metric == metric;
          return ChoiceChip(
            key: Key('history-metric-${metric.name}'),
            selected: selected,
            showCheckmark: false,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  metric.icon,
                  key: Key('history-metric-icon-${metric.name}'),
                  size: 16,
                  color: selected ? metric.color : HealthPalColors.secondary,
                ),
                const SizedBox(width: 6),
                Text(metric.label),
              ],
            ),
            onSelected: (_) => _history.setMetric(metric),
            selectedColor: metric.color.withValues(alpha: 0.14),
            backgroundColor: Colors.white.withValues(alpha: 0.8),
            side: BorderSide(
              color: selected
                  ? metric.color.withValues(alpha: 0.35)
                  : HealthPalColors.border,
            ),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? metric.color : HealthPalColors.secondary,
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_history.isLoading && _history.summaries.isEmpty) {
      return const SizedBox(
        height: 420,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_history.error != null) {
      return _StateCard(
        icon: CupertinoIcons.exclamationmark_triangle,
        title: 'Chưa tải được lịch sử',
        message: 'Vui lòng kiểm tra lại và thử lần nữa.',
        action: FilledButton(
          key: const Key('history-retry'),
          onPressed: _history.retry,
          child: const Text('Thử lại'),
        ),
      );
    }
    if (_history.summaries.isEmpty) {
      return const _StateCard(
        icon: CupertinoIcons.chart_bar,
        title: 'Chưa có dữ liệu',
        message: 'Lịch sử sức khỏe sẽ xuất hiện tại đây khi có dữ liệu.',
      );
    }

    return Column(
      key: Key('history-content-${_history.summaries.length}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildChartCard(),
        const SizedBox(height: 24),
        const Text(
          'Từng ngày',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 12),
        ..._history.summaries.map(_buildDayCard),
      ],
    );
  }

  Widget _buildChartCard() {
    final metric = _history.metric;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0712162E),
            blurRadius: 24,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: metric.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  metric.icon,
                  key: Key('history-chart-icon-${metric.name}'),
                  size: 18,
                  color: metric.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  metric.label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _history.period == HistoryPeriod.sevenDays
                    ? '7 ngày'
                    : '30 ngày',
                style: const TextStyle(
                  fontSize: 11,
                  color: HealthPalColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildSummary(metric),
          const SizedBox(height: 20),
          HistoryChart(
            summaries: _history.summaries,
            metric: metric,
            period: _history.period,
          ),
          if (metric == HistoryMetric.fatigue) ...[
            const SizedBox(height: 8),
            const _FatigueLegend(),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(HistoryMetric metric) {
    if (metric == HistoryMetric.fatigue) {
      int count(FatigueAssessmentStatus status) => _history.summaries
          .where((summary) => summary.fatigue?.status == status)
          .length;
      return Row(
        children: [
          Expanded(
            child: _SummaryValue(
              label: 'Chưa thấy tín hiệu',
              value: '${count(FatigueAssessmentStatus.noClearSignal)} ngày',
            ),
          ),
          Expanded(
            child: _SummaryValue(
              label: 'Có dấu hiệu',
              value: '${count(FatigueAssessmentStatus.signalDetected)} ngày',
            ),
          ),
        ],
      );
    }

    final values = _history.summaries
        .map((summary) => summary.valueFor(metric))
        .whereType<double>()
        .toList();
    final latest = _history.summaries
        .map((summary) => summary.valueFor(metric))
        .whereType<double>()
        .firstOrNull;
    final average = values.isEmpty
        ? null
        : values.reduce((left, right) => left + right) / values.length;

    return Row(
      children: [
        Expanded(
          child: _SummaryValue(
            label: 'Gần nhất',
            value: _formatValue(metric, latest),
          ),
        ),
        Expanded(
          child: _SummaryValue(
            label: 'Trung bình',
            value: _formatValue(metric, average),
          ),
        ),
        Expanded(
          child: _SummaryValue(
            label: 'Có dữ liệu',
            value: '${values.length} ngày',
          ),
        ),
      ],
    );
  }

  Widget _buildDayCard(DailyHealthSummary summary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('history-day-${_dateKey(summary.date)}'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showDayDetail(summary),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _fatigueColor(summary).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${summary.date.day}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _fatigueColor(summary),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _longDate(summary.date),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_sleep(summary.sleepMinutes)}  ·  ${_number(summary.steps)} bước'
                        '  ·  ${_fatigueLabel(summary)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _fatigueColor(summary),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: HealthPalColors.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDayDetail(DailyHealthSummary summary) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SingleChildScrollView(
        key: const Key('history-day-detail'),
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _longDate(summary.date),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _fatigueColor(summary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  _fatigueLabel(summary),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _fatigueColor(summary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _DetailRow(
              icon: CupertinoIcons.moon_fill,
              label: 'Giấc ngủ',
              value: _sleep(summary.sleepMinutes),
            ),
            _DetailRow(
              icon: CupertinoIcons.flame_fill,
              label: 'Số bước',
              value: '${_number(summary.steps)} bước',
            ),
            _DetailRow(
              icon: CupertinoIcons.heart_fill,
              label: 'Nhịp tim (min/avg/max)',
              value: summary.averageHeartRate == null
                  ? 'Chưa có dữ liệu'
                  : '${summary.minHeartRate?.round() ?? '-'} / ${summary.averageHeartRate!.round()} / ${summary.maxHeartRate?.round() ?? '-'} bpm',
            ),
            _DetailRow(
              icon: CupertinoIcons.heart_circle,
              label: 'Nhịp tim nghỉ',
              value: summary.restingHeartRate == null
                  ? 'Chưa có dữ liệu'
                  : '${summary.restingHeartRate} bpm',
            ),
            _DetailRow(
              icon: CupertinoIcons.sportscourt,
              label: 'Tập luyện',
              value:
                  '${summary.exerciseCount} buổi · ${summary.exerciseDurationMinutes} phút',
            ),
            if (summary.hrv != null)
              _DetailRow(
                icon: CupertinoIcons.waveform_path_ecg,
                label: 'HRV',
                value: '${summary.hrv} ms',
              ),
            _DetailRow(
              icon: CupertinoIcons.bolt_fill,
              label: 'Calories vận động',
              value: summary.activeCalories == null
                  ? 'Chưa có dữ liệu'
                  : '${summary.activeCalories!.round()} kcal',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Kết quả chỉ mang tính tham khảo và không phải chẩn đoán y tế.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: HealthPalColors.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatValue(HistoryMetric metric, double? value) {
    if (value == null) return 'Chưa có';
    if (metric == HistoryMetric.sleep) return '${value.toStringAsFixed(1)} giờ';
    if (metric == HistoryMetric.steps) return '${_number(value.round())} bước';
    return '${value.round()} ${metric.unit}';
  }

  String _sleep(int? minutes) {
    if (minutes == null) return 'Chưa có dữ liệu';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  String _number(int? value) {
    if (value == null) return '—';
    final text = value.toString();
    return text.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  }

  Color _fatigueColor(DailyHealthSummary summary) {
    return switch (summary.fatigue?.status) {
      FatigueAssessmentStatus.signalDetected => const Color(0xFFE04B59),
      FatigueAssessmentStatus.noClearSignal => const Color(0xFF2DA66E),
      _ => HealthPalColors.secondary,
    };
  }

  String _fatigueLabel(DailyHealthSummary summary) {
    return switch (summary.fatigue?.status) {
      FatigueAssessmentStatus.signalDetected => 'Có dấu hiệu mệt mỏi',
      FatigueAssessmentStatus.noClearSignal => 'Chưa thấy tín hiệu mệt mỏi',
      FatigueAssessmentStatus.insufficientData => 'Chưa đủ dữ liệu',
      FatigueAssessmentStatus.suppressedDuringExercise =>
        'Tạm hoãn vì đang hoặc vừa tập luyện',
      null => 'Chưa đủ dữ liệu',
    };
  }

  String _dateKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _longDate(DateTime value) {
    final now = DateTime.now();
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return 'Hôm nay, ${value.day}/${value.month}';
    }
    const weekdays = [
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7',
      'Chủ nhật',
    ];
    return '${weekdays[value.weekday - 1]}, ${value.day}/${value.month}';
  }
}

enum _AccountAction { profile, logout }

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: HealthPalColors.secondary,
          ),
        ),
      ],
    );
  }
}

class _FatigueLegend extends StatelessWidget {
  const _FatigueLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 6,
      children: [
        Text(
          'Chưa thấy tín hiệu mệt mỏi · Có dấu hiệu mệt mỏi',
          style: TextStyle(fontSize: 10, color: HealthPalColors.secondary),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8FB),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: HealthPalColors.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: HealthPalColors.secondary),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: HealthPalColors.secondary,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
