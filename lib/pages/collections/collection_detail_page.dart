// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/services/services.dart';
import 'package:random_movie/services/local_data_guard.dart';
import 'package:random_movie/widgets/collection/collection_icon.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/movie/movie_card.dart';
import 'package:random_movie/router/movie_detail_arguments.dart';
import 'package:random_movie/widgets/movie/selectable_movie_grid.dart';

/// 合集详情：展示合集内影片，支持编辑成员（手动合集）与「从本合集抽片」。
class CollectionDetailPage extends StatefulWidget {
  final MovieCollection collection;
  final StorageService? storage;

  const CollectionDetailPage({
    super.key,
    required this.collection,
    this.storage,
  });

  @override
  State<CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<CollectionDetailPage> {
  late final StorageService _storageService;

  bool _loading = true;
  bool _saving = false;
  bool _refreshing = false;
  int _loadRevision = 0;
  String? _error;
  List<Movie> _movies = const [];

  MovieCollection get _collection => widget.collection;
  bool get _canEdit => !_collection.isSmart;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storage ?? StorageService();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final revision = ++_loadRevision;
    setState(() {
      _loading = _movies.isEmpty;
      _refreshing = true;
      _error = null;
    });
    try {
      final provider = context.read<CollectionProvider>();
      final ids = await provider.memberIdsOf(_collection);
      final movies = await _storageService.getMoviesByIds(ids);
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _movies = movies;
        _loading = false;
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _error = '加载失败: $error';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _drawFromCollection() async {
    final ids = _movies.map((m) => m.id).toList();
    if (ids.isEmpty) return;
    context.push('/draw-from', extra: (movieIds: ids, title: _collection.name));
  }

  Future<void> _manageMembers() async {
    final selectedIds = _movies.map((m) => m.id).toSet();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberPickerSheet(
        initialSelected: selectedIds,
        storage: _storageService,
      ),
    );
    if (result == null || !mounted || _saving) return;

    final before = _movies.map((m) => m.id).toSet();
    final toAdd = result.difference(before);
    final toRemove = before.difference(result);
    if (toAdd.isEmpty && toRemove.isEmpty) return;

    await _saveMembers(add: toAdd, remove: toRemove);
  }

  Future<void> _saveMembers({
    required Iterable<String> add,
    required Iterable<String> remove,
  }) async {
    if (!mounted || _saving) return;
    LocalDataGuard.hold(this);
    setState(() => _saving = true);
    try {
      await context.read<CollectionProvider>().updateMembers(
        _collection.id,
        add: add,
        remove: remove,
      );
      if (!mounted) return;
      await _load();
      if (mounted) AppToast.success(context, '合集已更新');
    } catch (_) {
      if (mounted) AppToast.error(context, '保存失败，未更改合集，请重试');
    } finally {
      LocalDataGuard.release(this);
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeMember(Movie movie) =>
      _saveMembers(add: const [], remove: [movie.id]);

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
              onPressed: _saving || _refreshing ? null : _manageMembers,
            ),
        ],
      ),
      floatingActionButton:
          _movies.isEmpty || _loading || _saving || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _drawFromCollection,
              icon: const Icon(Icons.casino),
              label: const Text('从本合集抽片'),
            ),
      body: Column(
        children: [
          if (_saving || (_refreshing && _movies.isNotEmpty))
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null && _movies.isNotEmpty)
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新失败，点击重试'),
            ),
          Expanded(child: _buildBody(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading) {
      return const LoadingState(message: '加载中…');
    }
    if (_error != null && _movies.isEmpty) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_movies.isEmpty) {
      return EmptyState(
        title: '合集里还没有影片',
        subtitle: _canEdit ? '点右上角把喜欢的影片加进来' : '片库丰富后会自动归类到这里',
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
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: MediaQuery.textScalerOf(context).scale(14) > 19
                  ? 0.48
                  : 0.60,
              crossAxisSpacing: AppTheme.spacingMedium,
              mainAxisSpacing: AppTheme.spacingMedium,
            ),
            itemCount: _movies.length,
            itemBuilder: (context, index) {
              final movie = _movies[index];
              return GestureDetector(
                onLongPress: _canEdit && !_saving
                    ? () => _confirmRemove(movie)
                    : null,
                child: MovieCard(
                  key: ValueKey(movie.id),
                  movie: movie,
                  posterHeroTag: 'collection:${_collection.id}:${movie.id}',
                  onTap: () async {
                    await context.push(
                      '/movies/detail/${movie.id}',
                      extra: MovieDetailArguments(
                        movie,
                        posterTag: 'collection:${_collection.id}:${movie.id}',
                      ),
                    );
                    if (mounted && context.mounted) {
                      _load();
                      context.read<CollectionProvider>().refresh();
                    }
                  },
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
              decoration: ShapeDecoration(
                color: AppTheme.accent.withValues(alpha: 0.14),
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  side: BorderSide.none,
                ),
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
        shape: RoundedSuperellipseBorder(
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
  final StorageService storage;

  const _MemberPickerSheet({
    required this.initialSelected,
    required this.storage,
  });

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  StorageService get _storageService => widget.storage;
  final TextEditingController _searchController = TextEditingController();

  late Set<String> _selected;
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  int _revision = 0;
  bool _loadingMore = false;
  bool _hasMore = false;
  String _query = '';
  List<Movie> _visible = const [];

  @override
  void initState() {
    super.initState();
    LocalDataGuard.hold(this);
    _scrollController.addListener(_onScroll);
    _selected = {...widget.initialSelected};
    _load();
  }

  @override
  void dispose() {
    LocalDataGuard.release(this);
    ++_revision;
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final movies = await _storageService.queryMovies(
        limit: 48,
        offset: 0,
        searchQuery: _query,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _visible = movies;
        _hasMore = movies.length == 48;
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = '无法加载片库，请重试');
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 320) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final revision = _revision;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final movies = await _storageService.queryMovies(
        limit: 48,
        offset: _visible.length,
        searchQuery: _query,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _visible = [..._visible, ...movies];
        _hasMore = movies.length == 48;
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = '加载更多失败，请重试');
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _search(String query) {
    _query = query.trim();
    ++_revision;
    _debounce?.cancel();
    setState(() {
      _loading = true;
      _loadingMore = false;
      _visible = [];
    });
    _debounce = Timer(const Duration(milliseconds: 250), _load);
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
        decoration: ShapeDecoration(
          color: colorScheme.surfaceContainerLow,
          shape: RoundedSuperellipseBorder(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusXLarge),
            ),
            side: BorderSide.none,
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
                  hintText: '搜索片库…',
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
                  : _error != null && _visible.isEmpty
                  ? ErrorState(message: _error!, onRetry: _load)
                  : _visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingXLarge),
                      child: Text(
                        _searchController.text.trim().isEmpty
                            ? '片库里还没有影片'
                            : '没有找到匹配的影片',
                      ),
                    )
                  : SelectableMovieGrid(
                      movies: _visible,
                      controller: _scrollController,
                      hasMore: _hasMore && _error == null,
                      isLoadingMore: _loadingMore,
                      selectedIds: _selected,
                      onToggle: _toggle,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMedium,
                        vertical: AppTheme.spacingSmall,
                      ),
                    ),
            ),
            if (_error != null && _visible.isNotEmpty)
              TextButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_error!),
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
                onPressed: _loading || (_error != null && _visible.isEmpty)
                    ? null
                    : () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
