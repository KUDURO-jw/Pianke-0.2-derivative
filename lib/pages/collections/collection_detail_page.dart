import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/services/services.dart';
import 'package:random_movie/widgets/collection/collection_icon.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/movie/movie_card.dart';
import 'package:random_movie/widgets/movie/selectable_movie_grid.dart';

/// 合集详情：展示合集内影片，支持编辑成员（手动合集）与「从本合集抽片」。
class CollectionDetailPage extends StatefulWidget {
  final MovieCollection collection;

  const CollectionDetailPage({super.key, required this.collection});

  @override
  State<CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<CollectionDetailPage> {
  final StorageService _storageService = StorageService();

  bool _loading = true;
  String? _error;
  List<Movie> _movies = const [];

  MovieCollection get _collection => widget.collection;
  bool get _canEdit => !_collection.isSmart;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = context.read<CollectionProvider>();
      final ids = await provider.memberIdsOf(_collection);
      final movies = await _storageService.getMoviesByIds(ids);
      if (!mounted) return;
      setState(() {
        _movies = movies;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $error';
        _loading = false;
      });
    }
  }

  Future<void> _drawFromCollection() async {
    final ids = _movies.map((m) => m.id).toList();
    if (ids.isEmpty) return;
    context.push('/draw-from', extra: (movieIds: ids, title: _collection.name));
  }

  Future<void> _manageMembers() async {
    final provider = context.read<CollectionProvider>();
    final selectedIds = _movies.map((m) => m.id).toSet();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberPickerSheet(initialSelected: selectedIds),
    );
    if (result == null) return;

    final before = _movies.map((m) => m.id).toSet();
    final toAdd = result.difference(before);
    final toRemove = before.difference(result);
    if (toAdd.isEmpty && toRemove.isEmpty) return;

    for (final id in toAdd) {
      await provider.addMovieToCollection(_collection.id, id);
    }
    for (final id in toRemove) {
      await provider.removeMovieFromCollection(_collection.id, id);
    }
    await _load();
  }

  Future<void> _removeMember(Movie movie) async {
    final provider = context.read<CollectionProvider>();
    await provider.removeMovieFromCollection(_collection.id, movie.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(collectionIcon(_collection.iconKey), size: 20),
            const SizedBox(width: AppTheme.spacingSmall),
            Expanded(
              child: Text(
                _collection.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: '管理影片',
              onPressed: _manageMembers,
            ),
        ],
      ),
      floatingActionButton: _movies.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _drawFromCollection,
              icon: const Icon(Icons.casino),
              label: const Text('从本合集抽片'),
            ),
      body: _buildBody(colorScheme),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading) {
      return const LoadingState(message: '加载中...');
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_movies.isEmpty) {
      return EmptyState(
        title: '合集里还没有影片',
        subtitle: _canEdit ? '点右上角把喜欢的电影加进来' : '片库丰富后会自动归类到这里',
        icon: Icons.movie_outlined,
        onAction: _canEdit ? _manageMembers : null,
        actionLabel: '添加影片',
      );
    }

    return Column(
      children: [
        _buildCollectionDrawBanner(colorScheme),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingMedium,
            AppTheme.spacingSmall,
            AppTheme.spacingMedium,
            0,
          ),
          child: Row(
            children: [
              Text(
                '共 ${_movies.length} 部',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              if (_canEdit) ...[
                const Spacer(),
                Text(
                  '长按可移出合集',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingMedium,
              AppTheme.spacingSmall,
              AppTheme.spacingMedium,
              100,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.60,
              crossAxisSpacing: AppTheme.spacingMedium,
              mainAxisSpacing: AppTheme.spacingMedium,
            ),
            itemCount: _movies.length,
            itemBuilder: (context, index) {
              final movie = _movies[index];
              return GestureDetector(
                onLongPress: _canEdit ? () => _confirmRemove(movie) : null,
                child: MovieCard(
                  key: ValueKey(movie.id),
                  movie: movie,
                  onTap: () => context.push('/movies/detail/${movie.id}'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionDrawBanner(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingMedium,
        AppTheme.spacingMedium,
        AppTheme.spacingMedium,
        AppTheme.spacingSmall,
      ),
      child: SoftCard(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: const Icon(Icons.casino_rounded, color: AppTheme.accent),
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '从「${_collection.name}」抽片',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_movies.length} 部候选，适合按场景快速决定今晚看什么',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingSmall),
            IconButton.filledTonal(
              onPressed: _drawFromCollection,
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: '开始抽片',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(Movie movie) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: const Text('移出合集'),
        content: Text('把《${movie.title}》从「${_collection.name}」移出？影片仍保留在片库。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
            child: const Text(
              '移出',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _removeMember(movie);
    }
  }
}

/// 成员选择底部弹窗：从整个片库中勾选合集影片。
class _MemberPickerSheet extends StatefulWidget {
  final Set<String> initialSelected;

  const _MemberPickerSheet({required this.initialSelected});

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  final StorageService _storageService = StorageService();
  final TextEditingController _searchController = TextEditingController();

  late Set<String> _selected;
  bool _loading = true;
  List<Movie> _all = const [];
  List<Movie> _visible = const [];

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelected};
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // 拉取整库（MVP 规模为数百部，一次性加载足够）。
      final movies = await _storageService.queryMovies(
        limit: 100000,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _all = movies;
        _visible = movies;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _search(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _visible = q.isEmpty
          ? _all
          : _all
                .where((m) => m.title.toLowerCase().contains(q))
                .toList(growable: false);
    });
  }

  void _toggle(Movie movie) {
    setState(() {
      if (_selected.contains(movie.id)) {
        _selected.remove(movie.id);
      } else {
        _selected.add(movie.id);
      }
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
                    '选择影片',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  Text(
                    '已选 ${_selected.length}',
                    style: TextStyle(fontSize: 13, color: AppTheme.accent),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLarge,
                vertical: AppTheme.spacingSmall,
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索片库...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
                onChanged: _search,
              ),
            ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(AppTheme.spacingXLarge),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _visible.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppTheme.spacingXLarge),
                      child: Text('片库里还没有影片'),
                    )
                  : SelectableMovieGrid(
                      movies: _visible,
                      selectedIds: _selected,
                      onToggle: _toggle,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMedium,
                        vertical: AppTheme.spacingSmall,
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(
                AppTheme.spacingLarge,
                AppTheme.spacingSmall,
                AppTheme.spacingLarge,
                AppTheme.spacingMedium,
              ),
              child: PrimaryButton(
                label: '完成',
                icon: Icons.check,
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
