import 'package:flutter/material.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/services.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';

/// 抽片筛选面板（底部弹窗内容）。
///
/// 以 [showDrawFilterPanel] 打开，确认后返回新的 [DrawFilter]，取消返回 null。
class DrawFilterPanel extends StatefulWidget {
  final DrawFilter initialFilter;
  final MovieFacets facets;
  final List<MovieTag> tags;

  const DrawFilterPanel({
    super.key,
    required this.initialFilter,
    required this.facets,
    this.tags = const [],
  });

  @override
  State<DrawFilterPanel> createState() => _DrawFilterPanelState();
}

/// 打开筛选面板；返回新筛选，用户取消则返回 null。
Future<DrawFilter?> showDrawFilterPanel(
  BuildContext context, {
  required DrawFilter initialFilter,
  required MovieFacets facets,
  List<MovieTag> tags = const [],
}) {
  return showModalBottomSheet<DrawFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DrawFilterPanel(
      initialFilter: initialFilter,
      facets: facets,
      tags: tags,
    ),
  );
}

class _DrawFilterPanelState extends State<DrawFilterPanel> {
  static const int _durationMinMinutes = 60;
  static const int _durationMaxMinutes = 180;

  late DrawFilter _draft;
  late final TextEditingController _directorController;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialFilter;
    _directorController = TextEditingController(text: _draft.director);
  }

  @override
  void dispose() {
    _directorController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _draft = DrawFilter.none;
      _directorController.text = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.85),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXLarge),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingLarge,
                  AppTheme.spacingSmall,
                  AppTheme.spacingLarge,
                  AppTheme.spacingLarge,
                ),
                children: [
                  _buildDurationSection(context),
                  if (widget.facets.genres.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spacingLarge),
                    _buildGenreSection(context),
                  ],
                  const SizedBox(height: AppTheme.spacingLarge),
                  _buildDecadeSection(context),
                  if (widget.facets.regions.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spacingLarge),
                    _buildRegionSection(context),
                  ],
                  const SizedBox(height: AppTheme.spacingLarge),
                  _buildRatingSection(context),
                  const SizedBox(height: AppTheme.spacingLarge),
                  _buildDirectorSection(context),
                  if (widget.tags.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spacingLarge),
                    _buildTagSection(context),
                  ],
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
              child: Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: '重置',
                      icon: Icons.restart_alt,
                      onPressed: _draft.isActive ? _reset : null,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingMedium),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      label: '应用筛选',
                      icon: Icons.check,
                      onPressed: () => Navigator.of(context).pop(_draft),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingLarge,
        AppTheme.spacingMedium,
        AppTheme.spacingSmall,
        0,
      ),
      child: Row(
        children: [
          Text(
            '筛选候选',
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
    );
  }

  // ---------- 时长预算（亮点） ----------

  Widget _buildDurationSection(BuildContext context) {
    final value = _draft.maxDurationMinutes;
    final sliderValue = (value ?? _durationMaxMinutes).toDouble().clamp(
      _durationMinMinutes.toDouble(),
      _durationMaxMinutes.toDouble(),
    );

    return _Section(
      title: '时长预算',
      trailing: value == null ? '不限' : '≤ ${_formatDuration(value)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Slider(
            value: sliderValue,
            min: _durationMinMinutes.toDouble(),
            max: _durationMaxMinutes.toDouble(),
            divisions: 12,
            label: sliderValue.round() >= _durationMaxMinutes
                ? '不限'
                : _formatDuration(sliderValue.round()),
            activeColor: AppTheme.accent,
            onChanged: (v) {
              final minutes = v.round();
              setState(() {
                _draft = minutes >= _durationMaxMinutes
                    ? _draft.copyWith(clearMaxDuration: true)
                    : _draft.copyWith(maxDurationMinutes: minutes);
              });
            },
          ),
          Row(
            children: [
              _QuickChip(
                label: '2 小时内',
                selected: value == 120,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(maxDurationMinutes: 120),
                ),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
              _QuickChip(
                label: '3 小时内',
                selected: value == 180,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(maxDurationMinutes: 180),
                ),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
              _QuickChip(
                label: '不限',
                selected: value == null,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(clearMaxDuration: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 类型 ----------

  Widget _buildGenreSection(BuildContext context) {
    return _Section(
      title: '类型',
      trailing: _draft.genres.isEmpty ? null : '已选 ${_draft.genres.length}',
      child: Wrap(
        spacing: AppTheme.spacingSmall,
        runSpacing: AppTheme.spacingSmall,
        children: widget.facets.genres.map((genre) {
          final selected = _draft.genres.contains(genre);
          return _QuickChip(
            label: genre,
            selected: selected,
            onTap: () {
              setState(() {
                final next = Set<String>.from(_draft.genres);
                if (selected) {
                  next.remove(genre);
                } else {
                  next.add(genre);
                }
                _draft = _draft.copyWith(genres: next);
              });
            },
          );
        }).toList(),
      ),
    );
  }

  // ---------- 年代 ----------

  Widget _buildDecadeSection(BuildContext context) {
    final decades = _availableDecades();
    return _Section(
      title: '年代',
      child: Wrap(
        spacing: AppTheme.spacingSmall,
        runSpacing: AppTheme.spacingSmall,
        children: [
          for (final decade in decades)
            _QuickChip(
              label: decade.label,
              selected:
                  _draft.minYear == decade.minYear &&
                  _draft.maxYear == decade.maxYear,
              onTap: () {
                setState(() {
                  final isSelected =
                      _draft.minYear == decade.minYear &&
                      _draft.maxYear == decade.maxYear;
                  if (isSelected) {
                    _draft = _draft.copyWith(
                      clearMinYear: true,
                      clearMaxYear: true,
                    );
                  } else {
                    _draft = _draft.copyWith(
                      minYear: decade.minYear,
                      maxYear: decade.maxYear,
                    );
                  }
                });
              },
            ),
        ],
      ),
    );
  }

  // ---------- 地区 ----------

  Widget _buildRegionSection(BuildContext context) {
    return _Section(
      title: '地区',
      trailing: _draft.regions.isEmpty ? null : '已选 ${_draft.regions.length}',
      child: Wrap(
        spacing: AppTheme.spacingSmall,
        runSpacing: AppTheme.spacingSmall,
        children: widget.facets.regions.map((region) {
          final selected = _draft.regions.contains(region);
          return _QuickChip(
            label: region,
            selected: selected,
            onTap: () {
              setState(() {
                final next = Set<String>.from(_draft.regions);
                if (selected) {
                  next.remove(region);
                } else {
                  next.add(region);
                }
                _draft = _draft.copyWith(regions: next);
              });
            },
          );
        }).toList(),
      ),
    );
  }

  // ---------- 评分 ----------

  Widget _buildRatingSection(BuildContext context) {
    final minRating = _draft.minRating;
    return _Section(
      title: '最低评分',
      trailing: minRating == null ? '不限' : minRating.toStringAsFixed(1),
      child: Slider(
        value: minRating ?? 0,
        min: 0,
        max: 10,
        divisions: 20,
        label: (minRating ?? 0).toStringAsFixed(1),
        activeColor: AppTheme.accent,
        onChanged: (v) {
          setState(() {
            _draft = v <= 0
                ? _draft.copyWith(clearMinRating: true)
                : _draft.copyWith(
                    minRating: double.parse(v.toStringAsFixed(1)),
                  );
          });
        },
      ),
    );
  }

  // ---------- 标签 ----------

  Widget _buildTagSection(BuildContext context) {
    return _Section(
      title: '标签',
      trailing: _draft.tagIds.isEmpty ? null : '已选 ${_draft.tagIds.length}',
      child: Wrap(
        spacing: AppTheme.spacingSmall,
        runSpacing: AppTheme.spacingSmall,
        children: widget.tags.map((tag) {
          final selected = _draft.tagIds.contains(tag.id);
          return GestureDetector(
            onTap: () {
              setState(() {
                final next = Set<String>.from(_draft.tagIds);
                if (selected) {
                  next.remove(tag.id);
                } else {
                  next.add(tag.id);
                }
                _draft = _draft.copyWith(tagIds: next);
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMedium,
                vertical: AppTheme.spacingSmall,
              ),
              decoration: BoxDecoration(
                color: selected ? tag.color : tag.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                border: Border.all(color: tag.color),
              ),
              child: Text(
                tag.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : tag.color,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---------- 导演 ----------

  Widget _buildDirectorSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _Section(
      title: '导演',
      child: TextField(
        controller: _directorController,
        decoration: InputDecoration(
          hintText: '输入导演名关键词',
          isDense: true,
          prefixIcon: const Icon(Icons.person_search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
        ),
        style: TextStyle(color: colorScheme.onSurface),
        onChanged: (value) {
          _draft = _draft.copyWith(director: value);
        },
      ),
    );
  }

  // ---------- helpers ----------

  List<_Decade> _availableDecades() {
    final minYear = widget.facets.minYear;
    final maxYear = widget.facets.maxYear;
    final result = <_Decade>[];

    if (minYear != null && maxYear != null) {
      final startDecade = (maxYear ~/ 10) * 10;
      for (var d = startDecade; d >= 1990; d -= 10) {
        result.add(_Decade('${d}s', d, d + 9));
      }
      if (minYear < 1990) {
        result.add(const _Decade('90 年代以前', 0, 1989));
      }
    } else {
      // 无年代数据时给固定档位
      result.addAll(const [
        _Decade('2020s', 2020, 2029),
        _Decade('2010s', 2010, 2019),
        _Decade('2000s', 2000, 2009),
        _Decade('90 年代', 1990, 1999),
        _Decade('90 年代以前', 0, 1989),
      ]);
    }
    return result;
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins == 0 ? '$hours 小时' : '$hours 小时 $mins 分';
  }
}

class _Decade {
  final String label;
  final int minYear;
  final int maxYear;
  const _Decade(this.label, this.minYear, this.maxYear);
}

class _Section extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget child;

  const _Section({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        child,
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
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
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
