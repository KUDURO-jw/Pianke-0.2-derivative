// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/providers.dart';

/// 影片标签编辑器：展示 / 勾选个人标签，并可新建带颜色的标签。
///
/// 内嵌于影片详情页，改动即时落库（写 movie_tags 关联表）。
class MovieTagEditor extends StatefulWidget {
  final String movieId;

  const MovieTagEditor({super.key, required this.movieId});

  @override
  State<MovieTagEditor> createState() => _MovieTagEditorState();
}

class _MovieTagEditorState extends State<MovieTagEditor> {
  bool _loading = true;
  Set<String> _selectedTagIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<CollectionProvider>();
    await provider.ensureLoaded();
    final tags = await provider.tagsForMovie(widget.movieId);
    if (!mounted) return;
    setState(() {
      _selectedTagIds = tags.map((t) => t.id).toSet();
      _loading = false;
    });
  }

  Future<void> _toggle(MovieTag tag) async {
    setState(() {
      if (_selectedTagIds.contains(tag.id)) {
        _selectedTagIds.remove(tag.id);
      } else {
        _selectedTagIds.add(tag.id);
      }
    });
    await context.read<CollectionProvider>().setMovieTags(
      widget.movieId,
      _selectedTagIds,
    );
  }

  Future<void> _createTag() async {
    final result = await showDialog<({String name, int colorValue})>(
      context: context,
      builder: (_) => const _TagCreatorDialog(),
    );
    if (result == null || !mounted) return;

    final provider = context.read<CollectionProvider>();
    final created = await provider.createTag(result.name, result.colorValue);
    if (created == null || !mounted) return;
    setState(() => _selectedTagIds.add(created.id));
    await provider.setMovieTags(widget.movieId, _selectedTagIds);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.spacingSmall),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Consumer<CollectionProvider>(
      builder: (context, provider, _) {
        final tags = provider.allTags;
        return Wrap(
          spacing: AppTheme.spacingSmall,
          runSpacing: AppTheme.spacingSmall,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in tags)
              _TagChip(
                tag: tag,
                selected: _selectedTagIds.contains(tag.id),
                onTap: () => _toggle(tag),
              ),
            GestureDetector(
              onTap: _createTag,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMedium,
                  vertical: AppTheme.spacingSmall,
                ),
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    side: BorderSide(
                      color: colorScheme.outline.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '新标签',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TagChip extends StatelessWidget {
  final MovieTag tag;
  final bool selected;
  final VoidCallback onTap;

  const _TagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: AppTheme.spacingSmall,
        ),
        decoration: ShapeDecoration(
          color: selected ? tag.color : tag.color.withValues(alpha: 0.15),
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            side: BorderSide(color: tag.color),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              tag.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? Colors.white : tag.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新建标签弹窗：名称 + 调色板选色。
class _TagCreatorDialog extends StatefulWidget {
  const _TagCreatorDialog();

  @override
  State<_TagCreatorDialog> createState() => _TagCreatorDialogState();
}

class _TagCreatorDialogState extends State<_TagCreatorDialog> {
  final TextEditingController _controller = TextEditingController();
  int _colorValue = MovieTag.palette.first;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      title: const Text('新建标签'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 10,
            decoration: const InputDecoration(
              hintText: '标签名，如「治愈」「爆米花」',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final value in MovieTag.palette)
                GestureDetector(
                  onTap: () => setState(() => _colorValue = value),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorValue == value
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: _colorValue == value
                          ? [
                              BoxShadow(
                                color: Color(value).withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                    child: _colorValue == value
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop((name: name, colorValue: _colorValue));
          },
          style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
          child: const Text(
            '创建',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
