// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/collection_provider.dart';
import 'package:random_movie/providers/movie_provider.dart';
import 'package:random_movie/widgets/collection/collection_icon.dart';
import 'package:random_movie/widgets/common/app_components.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/movie/movie_card.dart';
import 'package:random_movie/router/movie_detail_arguments.dart';

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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.pageSurface,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: DockMetrics.insetOf(context)),
        child: FloatingActionButton.extended(
          onPressed: () => _navigateToAddMovie(context),
          icon: const Icon(Icons.add_rounded, size: 22),
          label: const Text('添加'),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('movies-grid'),
          controller: _scrollController,
          scrollCacheExtent: ScrollCacheExtent.pixels(
            MediaQuery.of(context).size.height * 0.9,
          ),
          slivers: [
            // ── 页面头部：大标题 + 搜索 + 分段控件 ──
            // 用 SliverToBoxAdapter 而非 pinned header：
            // 滚动时让标题自然收起，只保留吸顶的分段控件，减少重绘。
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PageHeader(
                      title: '片库',
                      padding: EdgeInsets.fromLTRB(
                        Spacing.page,
                        8,
                        Spacing.page,
                        8,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.page,
                      ),
                      child: AppSearchField(
                        controller: _searchController,
                        hint: '搜索片库',
                        hasText: _query.isNotEmpty,
                        onChanged: (value) {
                          final wasEmpty = _query.isEmpty;
                          final isEmpty = value.isEmpty;
                          if (wasEmpty != isEmpty) {
                            setState(() => _query = value);
                          } else {
                            _query = value;
                          }
                          context.read<MovieProvider>().setSearchQueryDebounced(
                            value,
                          );
                        },
                        onClear: () async {
                          _searchController.clear();
                          setState(() => _query = '');
                          await context.read<MovieProvider>().setSearchQuery(
                            '',
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),

                    // 合集横条（搜索时隐藏）
                    if (_query.isEmpty) _buildCollectionStrip(context),
                  ],
                ),
              ),
            ),

            // ── 吸顶分段筛选 ──
            SliverPersistentHeader(
              pinned: true,
              delegate: _LibraryFilterHeader(
                height: 60 + (MediaQuery.textScalerOf(context).scale(13) - 13),
                colorScheme: scheme,
                textTheme: Theme.of(context).textTheme,
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
                    child: LoadingState(message: '加载中…'),
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
                    LibraryFilter.watched => '还没有已看的影片',
                    LibraryFilter.unwatched => '所有影片都看过啦',
                    LibraryFilter.all =>
                      state.searchQuery.isEmpty ? '片库还是空的' : '没有找到匹配的影片',
                  };
                  final emptySubtitle = switch (state.filter) {
                    LibraryFilter.watched => '看完影片后标记一下吧',
                    LibraryFilter.unwatched => '添加新影片继续探索',
                    LibraryFilter.all =>
                      state.searchQuery.isEmpty ? '添加你的第一部影片吧' : '试试其他搜索词',
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
                      actionLabel: '添加影片',
                    ),
                  );
                }

                final itemCount =
                    state.hasMoreLibrary || state.isLibraryLoadingMore
                    ? movies.length + 1
                    : movies.length;

                return SliverPadding(
                  padding: EdgeInsets.only(
                    top: Spacing.md,
                    left: Spacing.page,
                    right: Spacing.page,
                    bottom: DockMetrics.insetOf(context) + 24,
                  ),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      // 高密度屏幕（如 3200×1440）上等比放大卡片宽度。
                      maxCrossAxisExtent: 190,
                      childAspectRatio:
                          MediaQuery.textScalerOf(context).scale(14) > 19
                          ? 0.48
                          : 0.58,
                      crossAxisSpacing: Spacing.md,
                      mainAxisSpacing: Spacing.lg,
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
                        posterHeroTag: 'library:${movie.id}',
                        onTap: () => context.push(
                          '/movies/detail/${movie.id}',
                          extra: MovieDetailArguments(
                            movie,
                            posterTag: 'library:${movie.id}',
                          ),
                        ),
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
      ),
    );
  }

  /// 片库顶部合集入口：横向滚动的合集卡片 + 「管理」入口。
  Widget _buildCollectionStrip(BuildContext context) {
    return Selector<
      CollectionProvider,
      ({bool hasManual, List<MovieCollection> collections})
    >(
      selector: (_, p) => (
        hasManual: p.manualCollections.isNotEmpty,
        collections: [...p.manualCollections, ...p.smartCollections],
      ),
      builder: (context, state, _) {
        final collections = state.collections;
        if (!state.hasManual) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.page),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => context.push('/collections'),
                icon: const Icon(Icons.collections_bookmark_outlined, size: 18),
                label: const Text('我的合集'),
              ),
            ),
          );
        }
        return SizedBox(
          height: 88 + (MediaQuery.textScalerOf(context).scale(12) - 12) * 2,
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
        shape: RoundedSuperellipseBorder(
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

/// 吸顶筛选头 —— 「全部 / 未看 / 已看」带全局数量的胶囊，滚动时常驻顶部。
class _LibraryFilterHeader extends SliverPersistentHeaderDelegate {
  _LibraryFilterHeader({
    required this.height,
    required this.colorScheme,
    required this.textTheme,
    required this.onFilterChanged,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final ValueChanged<LibraryFilter> onFilterChanged;

  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.page,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        // 吸顶时用页面底色垫底，避免内容从下方透出来
        color: colorScheme.pageSurface,
      ),
      child: Selector<MovieProvider, (LibraryFilter, int, int)>(
        selector: (_, p) => (p.libraryFilter, p.totalCount, p.watchedCount),
        builder: (context, data, _) {
          final (filter, total, watched) = data;
          return SegmentedSwitch(
            labels: const ['全部', '未看', '已看'],
            counts: [total, total - watched, watched],
            selectedIndex: switch (filter) {
              LibraryFilter.all => 0,
              LibraryFilter.unwatched => 1,
              LibraryFilter.watched => 2,
            },
            onChanged: (i) => onFilterChanged(switch (i) {
              0 => LibraryFilter.all,
              1 => LibraryFilter.unwatched,
              _ => LibraryFilter.watched,
            }),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LibraryFilterHeader oldDelegate) {
    return oldDelegate.colorScheme != colorScheme ||
        oldDelegate.textTheme != textTheme ||
        oldDelegate.height != height;
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
        child: ClipRSuperellipse(
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
    final scheme = Theme.of(context).colorScheme;
    return ContinuousSurface(
      radius: Radii.md,
      level: SurfaceLevel.block,
      onTap: onTap,
      border: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SizedBox(
        width: 88,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.collections_bookmark_rounded,
              size: 24,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              '我的合集',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TypeScale.caption,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
