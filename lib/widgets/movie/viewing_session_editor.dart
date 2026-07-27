import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';

/// 记录 / 编辑一次观影会话的底部弹窗。
/// 确认返回填好的 [ViewingSession]，取消返回 null。
Future<ViewingSession?> showViewingSessionEditor(
  BuildContext context, {
  required String movieId,
  ViewingSession? existing,
  bool defaultIsRewatch = false,
}) {
  return showModalBottomSheet<ViewingSession>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ViewingSessionEditor(
      movieId: movieId,
      existing: existing,
      defaultIsRewatch: defaultIsRewatch,
    ),
  );
}

class _ViewingSessionEditor extends StatefulWidget {
  final String movieId;
  final ViewingSession? existing;
  final bool defaultIsRewatch;

  const _ViewingSessionEditor({
    required this.movieId,
    this.existing,
    this.defaultIsRewatch = false,
  });

  @override
  State<_ViewingSessionEditor> createState() => _ViewingSessionEditorState();
}

class _ViewingSessionEditorState extends State<_ViewingSessionEditor> {
  late DateTime _watchedAt;
  late WatchMood _mood;
  late bool _isRewatch;
  late double? _rating;
  late final TextEditingController _withController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _watchedAt = e?.watchedAt ?? DateTime.now();
    _mood = e?.mood ?? WatchMood.none;
    _isRewatch = e?.isRewatch ?? widget.defaultIsRewatch;
    _rating = e?.rating;
    _withController = TextEditingController(text: e?.watchedWith ?? '');
    _noteController = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _withController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _watchedAt,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _watchedAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _watchedAt.hour,
          _watchedAt.minute,
        );
      });
    }
  }

  void _submit() {
    final session =
        (widget.existing ??
                ViewingSession(
                  id: '',
                  movieId: widget.movieId,
                  watchedAt: _watchedAt,
                ))
            .copyWith(
              movieId: widget.movieId,
              watchedAt: _watchedAt,
              mood: _mood,
              watchedWith: _withController.text.trim(),
              note: _noteController.text.trim(),
              isRewatch: _isRewatch,
              rating: _rating,
              clearRating: _rating == null,
            );
    Navigator.of(context).pop(session);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXLarge),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingLarge,
                AppTheme.spacingMedium,
                AppTheme.spacingSmall,
                0,
              ),
              child: Row(
                children: [
                  Text(
                    widget.existing == null ? '记录一次观影' : '编辑观影记录',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingLarge,
                  AppTheme.spacingSmall,
                  AppTheme.spacingLarge,
                  AppTheme.spacingLarge,
                ),
                children: [
                  _label(context, '观看日期'),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMedium,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 18,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: AppTheme.spacingMedium),
                          Text(
                            DateFormat('yyyy 年 M 月 d 日').format(_watchedAt),
                            style: TextStyle(
                              fontSize: 15,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingLarge),

                  _label(context, '心情'),
                  Wrap(
                    spacing: AppTheme.spacingSmall,
                    runSpacing: AppTheme.spacingSmall,
                    children: [
                      for (final mood in WatchMood.values)
                        if (mood != WatchMood.none) _moodChip(context, mood),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingLarge),

                  _label(context, '我的评分'),
                  _buildStars(colorScheme),
                  const SizedBox(height: AppTheme.spacingLarge),

                  _label(context, '和谁一起看'),
                  TextField(
                    controller: _withController,
                    decoration: InputDecoration(
                      hintText: '例如：一个人 / 和家人 / 朋友',
                      isDense: true,
                      prefixIcon: const Icon(Icons.people_outline, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                      ),
                    ),
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: AppTheme.spacingLarge),

                  _label(context, '一句私语'),
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: '这次观影的想法...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                      ),
                    ),
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: AppTheme.spacingMedium),

                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '这是一次重看',
                      style: TextStyle(
                        fontSize: 15,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    value: _isRewatch,
                    activeThumbColor: AppTheme.accent,
                    onChanged: (v) => setState(() => _isRewatch = v),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(
                AppTheme.spacingLarge,
                0,
                AppTheme.spacingLarge,
                AppTheme.spacingMedium,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check),
                  label: Text(widget.existing == null ? '保存记录' : '保存修改'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _moodChip(BuildContext context, WatchMood mood) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _mood == mood;
    return GestureDetector(
      onTap: () => setState(() => _mood = selected ? WatchMood.none : mood),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: AppTheme.spacingSmall,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: selected
                ? AppTheme.accent
                : colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          '${mood.emoji ?? ''} ${mood.label}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildStars(ColorScheme colorScheme) {
    final current = _rating ?? 0;
    return Row(
      children: List.generate(5, (index) {
        final starValue = (index + 1).toDouble();
        final filled = current >= starValue;
        return GestureDetector(
          onTap: () => setState(() {
            _rating = _rating == starValue ? null : starValue;
          }),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              filled ? Icons.star : Icons.star_border,
              size: 34,
              color: filled
                  ? Colors.amber
                  : colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        );
      }),
    );
  }
}
