// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/local_data_guard.dart';

/// 记录 / 编辑一次观影会话的底部弹窗。
/// 确认返回填好的 [ViewingSession]，取消返回 null。
Future<ViewingSession?> showViewingSessionEditor(
  BuildContext context, {
  required String movieId,
  ViewingSession? existing,
  bool defaultIsRewatch = false,
  DateTime? initialDate,
}) async {
  final owner = Object();
  LocalDataGuard.hold(owner);
  try {
    return await showModalBottomSheet<ViewingSession>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ViewingSessionEditor(
        movieId: movieId,
        existing: existing,
        defaultIsRewatch: defaultIsRewatch,
        initialDate: initialDate,
      ),
    );
  } finally {
    LocalDataGuard.release(owner);
  }
}

class _ViewingSessionEditor extends StatefulWidget {
  final String movieId;
  final ViewingSession? existing;
  final bool defaultIsRewatch;
  final DateTime? initialDate;

  const _ViewingSessionEditor({
    required this.movieId,
    this.existing,
    this.defaultIsRewatch = false,
    this.initialDate,
  });

  @override
  State<_ViewingSessionEditor> createState() => _ViewingSessionEditorState();
}

/// 「和谁一起看」的快捷选项。
///
/// [label] 会原样写进 `ViewingSession.watchedWith`，与历史数据格式保持一致，
/// 都是纯文本，因此旧的自由输入记录无需迁移即可正常回显。
enum WatchCompanion {
  alone('alone', '一个人', '👤'),
  family('family', '和家人', '👨‍👩‍👧'),
  friends('friends', '朋友', '🍻');

  const WatchCompanion(this.id, this.label, this.emoji);

  final String id;
  final String label;
  final String emoji;
}

class _ViewingSessionEditorState extends State<_ViewingSessionEditor> {
  late DateTime _watchedAt;
  late WatchMood _mood;
  late bool _isRewatch;
  late double? _rating;
  late final TextEditingController _withController;
  late final TextEditingController _noteController;

  /// 当前选中的快捷选项；null 表示未选或选了「其他」。
  WatchCompanion? _companion;

  /// 是否展开自定义输入框（点「其他」或历史数据不是预设项时）。
  bool _showCustomCompanion = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _watchedAt = e?.watchedAt ?? widget.initialDate ?? DateTime.now();
    _mood = e?.mood ?? WatchMood.none;
    _isRewatch = e?.isRewatch ?? widget.defaultIsRewatch;
    _rating = e?.rating;
    _noteController = TextEditingController(text: e?.note ?? '');

    // 回显：历史数据若是三个预设之一则点亮对应芯片，
    // 否则（自由文本）自动展开自定义输入框，保证老记录不丢。
    //
    // 新建记录默认选中「一个人」：观影绝大多数是独自进行，
    // 预选后用户不点也能直接保存。编辑旧记录时不做改动，
    // 保持原值（包括原值为空的情况）。
    final existingWith = e?.watchedWith ?? '';
    _withController = TextEditingController(text: existingWith);
    final matched = _matchCompanion(existingWith);
    _companion = matched;
    _showCustomCompanion = existingWith.isNotEmpty && matched == null;
    if (e == null) {
      _companion = WatchCompanion.alone;
    }
  }

  /// 把历史文本匹配回预设选项；同时兼容存 id 和存中文标签两种写法。
  static WatchCompanion? _matchCompanion(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    for (final option in WatchCompanion.values) {
      if (value == option.label || value == option.id) return option;
    }
    return null;
  }

  /// 当前应当写入 `watchedWith` 的文本。
  String get _resolvedCompanion {
    if (_showCustomCompanion) return _withController.text.trim();
    return _companion?.label ?? '';
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
              watchedWith: _resolvedCompanion,
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
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
        child: Material(
          color: colorScheme.surfaceContainerLow,
          shape: RoundedSuperellipseBorder(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusXLarge),
            ),
            side: BorderSide.none,
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
                    Expanded(
                      child: Text(
                        widget.existing == null ? '记录一次观影' : '编辑观影记录',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
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
                    _label(context, '观影日期'),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusMedium,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingMedium,
                          vertical: 14,
                        ),
                        decoration: ShapeDecoration(
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMedium,
                            ),
                            side: BorderSide(
                              color: colorScheme.outline.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
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
                    Wrap(
                      spacing: AppTheme.spacingSmall,
                      runSpacing: AppTheme.spacingSmall,
                      children: [
                        for (final option in WatchCompanion.values)
                          _companionChip(context, option),
                        _customCompanionChip(context),
                      ],
                    ),
                    if (_showCustomCompanion) ...[
                      const SizedBox(height: AppTheme.spacingSmall),
                      TextField(
                        controller: _withController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: '例如：和同事 / 团建 / 和猫',
                          isDense: true,
                          prefixIcon: const Icon(Icons.edit_outlined, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMedium,
                            ),
                          ),
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                    ],
                    const SizedBox(height: AppTheme.spacingLarge),

                    _label(context, '一句私语'),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: '这次观影的想法…',
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
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: AppTheme.spacingSmall,
        ),
        decoration: ShapeDecoration(
          color: selected
              ? AppTheme.accent
              : colorScheme.surfaceContainerHighest,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            side: BorderSide(
              color: selected
                  ? AppTheme.accent
                  : colorScheme.outline.withValues(alpha: 0.2),
            ),
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

  /// 「和谁一起看」的预设芯片，点击即选中；再次点击取消。
  Widget _companionChip(BuildContext context, WatchCompanion option) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = !_showCustomCompanion && _companion == option;
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _companion = null;
        } else {
          _companion = option;
          _showCustomCompanion = false;
          // 从「其他」切回预设时清空输入框，避免切换后残留看不见的文本。
          _withController.clear();
        }
      }),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: AppTheme.spacingSmall,
        ),
        decoration: ShapeDecoration(
          color: selected
              ? AppTheme.accent
              : colorScheme.surfaceContainerHighest,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            side: BorderSide(
              color: selected
                  ? AppTheme.accent
                  : colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
        ),
        child: Text(
          '${option.emoji} ${option.label}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// 「其他」芯片：选中后展开自由输入，避免把功能做窄。
  Widget _customCompanionChip(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _showCustomCompanion;
    return GestureDetector(
      onTap: () => setState(() {
        if (selected && _withController.text.trim().isEmpty) {
          _showCustomCompanion = false;
        } else if (selected) {
          _showCustomCompanion = false;
          _withController.clear();
        } else {
          _companion = null;
          _showCustomCompanion = true;
        }
      }),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: AppTheme.spacingSmall,
        ),
        decoration: ShapeDecoration(
          color: selected
              ? AppTheme.accent
              : colorScheme.surfaceContainerHighest,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            side: BorderSide(
              color: selected
                  ? AppTheme.accent
                  : colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
        ),
        child: Text(
          '✏️ 其他',
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
