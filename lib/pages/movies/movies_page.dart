import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/collection_provider.dart';
import 'package:random_movie/providers/movie_provider.dart';
import 'package:random_movie/widgets/collection/collection_icon.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/movie/movie_card.dart';

/// 片库页面
class MoviesPage extends StatefulWidget {
  const MoviesPage({super.key});

  @override
  State<MoviesPage> createState() => _MoviesPageState();
}

class _MoviesPageState extends State<MoviesPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _query = '';
  bool _requestedCollections = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedCollections) return;
    _requestedCollections = true;
    context.read<CollectionProvider>().ensureLoaded();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      context.read<MovieProvider>().loadMoreLibrary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: CustomScrollView(
        key: const PageStorageKey('movies-grid'),
        controller: _scrollController,
        scrollCacheExtent: ScrollCacheExtent.pixels(
          MediaQuery.of(context).size.height * 0.9,
        ),
        slivers: [
          // --- 悬浮常驻搜索框（无顶栏 / 无标题）---
          SliverPersistentHeader(
            pinned: true,
            delegate: _LibrarySearchHeader(
              topInset: topInset,
              colorScheme: colorScheme,
              controller: _searchController,
              onChanged: (value) {
                final wasEmpty = _query.isEmpty;
                final isEmpty = value.isEmpty;
                if (wasEmpty != isEmpty) {
                  setState(() => _query = value);
                } else {
                  _query = value;
                }
                context.read<MovieProvider>().setSearchQueryDebounced(value);
              },
              onClear: () async {
                _searchController.clear();
                setState(() => _query = '');
                await context.read<MovieProvider>().setSearchQuery('');
              },
            ),
          ),

          // --- 合集横条（搜索时隐藏，聚焦结果）---
          if (_query.isEmpty)
            SliverToBoxAdapter(child: _buildCollectionStrip(context)),

          // --- 吸顶筛选头（带数量）---
          SliverPersistentHeader(
            pinned: true,
            delegate: _LibraryFilterHeader(
              colorScheme: colorScheme,
              textTheme: textTheme,
              onFilterChanged: (filter) =>
                  context.read<MovieProvider>().setLibraryFilter(filter),
            ),
          ),

          // --- 海报网格 ---
          Selector<
            MovieProvider,
            ({
              List<Movie> movies,
              bool hasLoadedLibrary,
              bool isLibraryLoading,
              bool isLibraryLoadingMore,
              bool hasMoreLibrary,
              String? error,
              String searchQuery,
              LibraryFilter filter,
            })
          >(
            selector: (_, provider) => (
              movies: provider.movies,
              hasLoadedLibrary: provider.hasLoadedLibrary,
              isLibraryLoading: provider.isLibraryLoading,
              isLibraryLoadingMore: provider.isLibraryLoadingMore,
              hasMoreLibrary: provider.hasMoreLibrary,
              error: provider.error,
              searchQuery: provider.searchQuery,
              filter: provider.libraryFilter,
            ),
            builder: (context, state, _) {
              final movies = state.movies;

              if ((!state.hasLoadedLibrary || state.isLibraryLoading) &&
                  movies.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: LoadingState(message: '加载中...'),
                );
              }

              if (state.error != null && movies.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(
                    message: state.error!,
                    onRetry: context.read<MovieProvider>().refreshLibrary,
                  ),
                );
              }

              if (movies.isEmpty) {
                final emptyLabel = switch (state.filter) {
                  LibraryFilter.watched => '还没有已看的电影',
                  LibraryFilter.unwatched => '所有电影都看过啦',
                  LibraryFilter.all =>
                    state.searchQuery.isEmpty ? '片库还是空的' : '没有找到匹配的电影',
                };
                final emptySubtitle = switch (state.filter) {
                  LibraryFilter.watched => '看完电影后标记一下吧',
                  LibraryFilter.unwatched => '添加新电影继续探索',
                  LibraryFilter.all =>
                    state.searchQuery.isEmpty ? '添加你的第一部电影吧' : '试试其他搜索词',
                };

                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: emptyLabel,
                    subtitle: emptySubtitle,
                    icon: Icons.movie_outlined,
                    onAction:
                        state.filter == LibraryFilter.all &&
                            state.searchQuery.isEmpty
                        ? () => _navigateToAddMovie(context)
                        : null,
                    actionLabel: '添加电影',
                  ),
                );
              }

              final itemCount =
                  state.hasMoreLibrary || state.isLibraryLoadingMore
                  ? movies.length + 1
                  : movies.length;

              return SliverPadding(
                padding: const EdgeInsets.only(
                  top: AppTheme.spacingSmall,
                  left: AppTheme.spacingMedium,
                  right: AppTheme.spacingMedium,
                  bottom: 88,
                ),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.60,
                    crossAxisSpacing: AppTheme.spacingMedium,
                    mainAxisSpacing: AppTheme.spacingMedium,
                  ),
                  itemCount: itemCount,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false,
                  itemBuilder: (context, index) {
                    if (index >= movies.length) {
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }

                    final movie = movies[index];
                    return MovieCard(
                      key: ValueKey(movie.id),
                      movie: movie,
                      onTap: () => context.push('/movies/detail/${movie.id}'),
                      onDelete: () => _confirmDelete(
                        context,
                        context.read<MovieProvider>(),
                        movie,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAddMovie(context),
        icon: const Icon(Icons.add),
        label: const Text('添加'),
      ),
    );
  }

  /// 片库顶部合集入口：横向滚动的合集卡片 + 「管理」入口。
  Widget _buildCollectionStrip(BuildContext context) {
    return Selector<CollectionProvider, List<MovieCollection>>(
      selector: (_, p) => [...p.manualCollections, ...p.smartCollections],
      builder: (context, collections, _) {
        return SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMedium,
              vertical: AppTheme.spacingSmall,
            ),
            itemCount: collections.length + 1,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppTheme.spacingSmall),
            itemBuilder: (context, index) {
              // 首位固定「我的合集」入口按钮（取代原右上角图标）。
              if (index == 0) {
                return _MyCollectionsEntry(
                  onTap: () => context.push('/collections'),
                );
              }
              final collection = collections[index - 1];
              return _CollectionStripCard(
                collection: collection,
                onTap: () =>
                    context.push('/collections/detail', extra: collection),
              );
            },
          ),
        );
      },
    );
  }

  void _navigateToAddMovie(BuildContext context) {
    context.push('/movies/add');
  }

  void _confirmDelete(
    BuildContext context,
    MovieProvider provider,
    Movie movie,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => AlertDialog(
        elevation: 24,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
        title: Text(
          '确认删除',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        content: Text(
          '确定要从片库中删除《${movie.title}》吗？',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              '取消',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              provider.deleteMovie(movie.id);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
            child: const Text(
              '删除',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// 悬浮常驻搜索框的吸顶头 —— 占据状态栏安全区 + 圆角搜索框，滚动时始终悬浮顶部。
class _LibrarySearchHeader extends SliverPersistentHeaderDelegate {
  _LibrarySearchHeader({
    required this.topInset,
    required this.colorScheme,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final double topInset;
  final ColorScheme colorScheme;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  static const double _zone = 64;

  @override
  double get minExtent => topInset + _zone;

  @override
  double get maxExtent => topInset + _zone;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: topInset,
          left: AppTheme.spacingMedium,
          right: AppTheme.spacingMedium,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LibrarySearchField(
              controller: controller,
              onChanged: onChanged,
              onClear: onClear,
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LibrarySearchHeader oldDelegate) {
    return oldDelegate.topInset != topInset ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.controller != controller;
  }
}

/// 常驻搜索框 —— MD3 圆角填充样式；自管清除按钮，避免吸顶重建时丢失焦点。
class _LibrarySearchField extends StatefulWidget {
  const _LibrarySearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_LibrarySearchField> createState() => _LibrarySearchFieldState();
}

class _LibrarySearchFieldState extends State<_LibrarySearchField> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_syncHasText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncHasText);
    super.dispose();
  }

  void _syncHasText() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
      decoration: InputDecoration(
        hintText: '搜索片库',
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        prefixIcon: Icon(
          Icons.search,
          size: 22,
          color: colorScheme.onSurfaceVariant,
        ),
        suffixIcon: _hasText
            ? IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: colorScheme.onSurfaceVariant,
                tooltip: '清除',
                onPressed: widget.onClear,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

/// 吸顶筛选头 —— 「全部 / 未看 / 已看」带全局数量的胶囊，滚动时常驻顶部。
class _LibraryFilterHeader extends SliverPersistentHeaderDelegate {
  _LibraryFilterHeader({
    required this.colorScheme,
    required this.textTheme,
    required this.onFilterChanged,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final ValueChanged<LibraryFilter> onFilterChanged;

  static const double _height = 56;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Selector<MovieProvider, (LibraryFilter, int, int)>(
        selector: (_, p) => (p.libraryFilter, p.totalCount, p.watchedCount),
        builder: (context, data, _) {
          final (filter, total, watched) = data;
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMedium,
              vertical: AppTheme.spacingSmall,
            ),
            children: [
              _chip(LibraryFilter.all, '全部', total, filter),
              const SizedBox(width: AppTheme.spacingSmall),
              _chip(LibraryFilter.unwatched, '未看', total - watched, filter),
              const SizedBox(width: AppTheme.spacingSmall),
              _chip(LibraryFilter.watched, '已看', watched, filter),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(
    LibraryFilter filter,
    String label,
    int count,
    LibraryFilter current,
  ) {
    final selected = filter == current;
    final bg = selected ? AppTheme.accent : colorScheme.surfaceContainerHighest;
    final fg = selected ? Colors.white : colorScheme.onSurfaceVariant;

    return Center(
      child: GestureDetector(
        onTap: () => onFilterChanged(filter),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: textTheme.bodySmall?.copyWith(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : colorScheme.onSurface.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LibraryFilterHeader oldDelegate) {
    return oldDelegate.colorScheme != colorScheme ||
        oldDelegate.textTheme != textTheme;
  }
}

/// 片库顶部横向合集卡片：海报底图 + 图标 + 名称 + 数量。
class _CollectionStripCard extends StatelessWidget {
  const _CollectionStripCard({required this.collection, required this.onTap});

  final MovieCollection collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final posters = collection.previewPosters;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 132,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (posters.isEmpty)
                ColoredBox(color: colorScheme.surfaceContainerHighest)
              else
                Row(
                  children: [
                    for (var i = 0; i < posters.length && i < 3; i++)
                      Expanded(
                        child: CachedNetworkImage(
                          imageUrl: posters[i],
                          httpHeaders: ApiConfig.imageHeaders,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          maxWidthDiskCache: 160,
                          fadeInDuration: Duration.zero,
                          placeholder: (_, _) => ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (_, _, _) => ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                  ],
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black26, Colors.black87],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingSmall),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      collectionIcon(collection.iconKey),
                      size: 18,
                      color: Colors.white,
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          collection.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${collection.memberCount} 部',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 合集横条最左侧的「我的合集」入口按钮（取代原顶栏右上角图标）。
class _MyCollectionsEntry extends StatelessWidget {
  const _MyCollectionsEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.collections_bookmark_rounded,
              size: 24,
              color: AppTheme.accent,
            ),
            SizedBox(height: 6),
            Text(
              '我的合集',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
