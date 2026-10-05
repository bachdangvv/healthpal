import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../theme/healthpal_theme.dart';
import '../../../theme/healthpal_brand.dart';
import '../application/exercise_library_controller.dart';
import '../application/training_controller.dart';
import '../data/exercise_repository.dart';
import '../data/training_readiness_repository.dart';
import '../domain/training_models.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({
    super.key,
    required this.readinessRepository,
    required this.exerciseRepository,
  });

  final TrainingReadinessRepository readinessRepository;
  final ExerciseRepository exerciseRepository;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  late final TrainingController _training;
  late final ExerciseLibraryController _library;

  @override
  void initState() {
    super.initState();
    _training = TrainingController(repository: widget.readinessRepository)
      ..addListener(_onChanged);
    _library = ExerciseLibraryController(repository: widget.exerciseRepository)
      ..addListener(_onChanged);
    unawaited(_training.load());
    unawaited(_library.load());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _training
      ..removeListener(_onChanged)
      ..dispose();
    _library
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _refresh() => _training.load();

  @override
  Widget build(BuildContext context) {
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
              key: const Key('training-refresh'),
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: Column(
                  key: const Key('training-screen'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    _readinessCard(),
                    const SizedBox(height: 24),
                    _librarySection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tập luyện',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Theo dõi mức sẵn sàng và tra cứu bài tập.',
              style: TextStyle(color: HealthPalColors.secondary, fontSize: 14),
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

  Widget _readinessCard() {
    final result = _training.result;
    final status = result?.status ?? TrainingReadinessStatus.insufficientData;
    final loading = _training.isLoading;
    final color = _statusColor(status);
    return Container(
      key: const Key('training-readiness-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0712162E),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.bolt_fill, color: color, size: 21),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Training Readiness',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                key: const Key('training-readiness-refresh'),
                tooltip: 'Làm mới',
                onPressed: loading ? null : _refresh,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.refresh, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    status.label,
                    key: const Key('training-readiness-status'),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            result?.suggestion ?? status.suggestion,
            key: const Key('training-readiness-suggestion'),
            style: const TextStyle(
              color: HealthPalColors.secondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 15),
          _inputSummary(result?.input),
          if (status == TrainingReadinessStatus.insufficientData) ...[
            const SizedBox(height: 12),
            const Text(
              'Cần có stress và thời lượng ngủ để đưa ra đánh giá. Kết quả chỉ mang tính tham khảo, không thay thế tư vấn y tế.',
              key: Key('training-readiness-disclaimer'),
              style: TextStyle(
                color: HealthPalColors.secondary,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inputSummary(TrainingReadinessInput? input) {
    String value(String? text) => text ?? 'Chưa có dữ liệu';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _metricPill('Stress', value(input?.stress?.label)),
        _metricPill('Giấc ngủ', value(_sleep(input?.sleepMinutes))),
        _metricPill(
          'Bước',
          value(input?.steps == null ? null : _formatInt(input!.steps!)),
        ),
        _metricPill(
          'Calories',
          value(
            input?.activeCalories == null
                ? null
                : '${input!.activeCalories!.round()} kcal',
          ),
        ),
      ],
    );
  }

  Widget _metricPill(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: HealthPalColors.background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '$label: $value',
      style: const TextStyle(fontSize: 11, color: HealthPalColors.secondary),
    ),
  );

  Widget _librarySection() => Column(
    key: const Key('training-library'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Exercise Library',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 5),
      const Text(
        'Thư viện tham khảo bài tập sẽ được bổ sung sau.',
        style: TextStyle(color: HealthPalColors.secondary, fontSize: 13),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const Key('training-search'),
        onChanged: _library.setQuery,
        decoration: const InputDecoration(
          hintText: 'Tìm bài tập',
          prefixIcon: Icon(CupertinoIcons.search),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: ExerciseMuscleGroup.values.length,
          separatorBuilder: (_, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final group = ExerciseMuscleGroup.values[index];
            return ChoiceChip(
              key: Key('training-group-${group.name}'),
              label: Text(group.label),
              selected: _library.group == group,
              onSelected: (_) => _library.setGroup(group),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      if (_library.isLoading)
        const Center(child: CircularProgressIndicator())
      else if (_library.exercises.isEmpty)
        _emptyLibrary()
      else
        ..._library.exercises.map(_exerciseCard),
    ],
  );

  Widget _emptyLibrary() => Container(
    key: const Key('training-empty-library'),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: HealthPalColors.border),
    ),
    child: const Column(
      children: [
        Icon(
          CupertinoIcons.square_stack_3d_up,
          size: 34,
          color: HealthPalColors.secondary,
        ),
        SizedBox(height: 10),
        Text(
          'Chưa có dữ liệu bài tập',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 5),
        Text(
          'Danh sách bài tập sẽ được bổ sung sau.',
          textAlign: TextAlign.center,
          style: TextStyle(color: HealthPalColors.secondary, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _exerciseCard(Exercise exercise) => Card(
    child: ListTile(
      title: Text(exercise.name),
      subtitle: Text(exercise.muscleGroup.label),
      trailing: IconButton(
        key: Key('training-favorite-${exercise.id}'),
        onPressed: () => _library.toggleFavorite(exercise),
        icon: Icon(
          _library.isFavorite(exercise)
              ? CupertinoIcons.heart_fill
              : CupertinoIcons.heart,
        ),
      ),
      onTap: () => _showExerciseDetails(exercise),
    ),
  );

  Future<void> _showExerciseDetails(
    Exercise exercise,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              exercise.name,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            if (exercise.englishName != null) ...[
              const SizedBox(height: 3),
              Text(
                exercise.englishName!,
                style: const TextStyle(color: HealthPalColors.secondary),
              ),
            ],
            const SizedBox(height: 16),
            Text('Nhóm cơ: ${exercise.muscleGroup.label}'),
            Text('Loại bài: ${exercise.exerciseType}'),
            Text('Dụng cụ: ${exercise.equipment}'),
            const SizedBox(height: 14),
            Text(exercise.instructions, style: const TextStyle(height: 1.5)),
          ],
        ),
      ),
    ),
  );

  Color _statusColor(TrainingReadinessStatus status) => switch (status) {
    TrainingReadinessStatus.ready => const Color(0xFF2DA66E),
    TrainingReadinessStatus.moderate => const Color(0xFFF0A52B),
    TrainingReadinessStatus.recovery => const Color(0xFFEA9B23),
    TrainingReadinessStatus.rest => const Color(0xFFE04B59),
    TrainingReadinessStatus.insufficientData => const Color(0xFF7A72D8),
  };

  String _sleep(int? minutes) => minutes == null
      ? 'Chưa có dữ liệu'
      : '${minutes ~/ 60}h ${minutes % 60}m';

  String _formatInt(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
}
