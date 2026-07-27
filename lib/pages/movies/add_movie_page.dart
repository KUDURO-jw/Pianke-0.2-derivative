import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/movie.dart';
import 'package:random_movie/providers/movie_provider.dart';
import 'package:random_movie/services/movie_scraper_service.dart'
    show ScraperException;
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/movie/movie_card.dart';

/// 添加电影页面
class AddMoviePage extends StatefulWidget {
  const AddMoviePage({super.key});

  @override
  State<AddMoviePage> createState() => _AddMoviePageState();
}

class _AddMoviePageState extends State<AddMoviePage>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final AnimationController _placeholderController;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _directorController = TextEditingController();

  // ===== 搜索 tab =====
  static const int _searchPageSize = 15;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _searchScrollController = ScrollController();
  List<Movie> _searchResults = [];
  final Set<String> _searchSeenIds = {};
  final Set<String> _addingIds = {};
  final Set<String> _addedIds = {};
  String _searchQuery = '';
  int _searchStart = 0;
  bool _searchLoading = false;
  bool _searchLoadingMore = false;
  bool _searchHasMore = false;
  bool _searchDone = false;
  String? _searchError;

  Movie? _previewMovie;
  List<Movie>? _previewMovies;
  bool _isLoading = false;
  bool _isDoulistLoading = false;
  int _doulistCompleted = 0;
  int _doulistTotal = 0;
  String? _doulistCurrentTitle;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchScrollController.addListener(_onSearchScroll);
    _placeholderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _placeholderController.dispose();
    _urlController.dispose();
    _titleController.dispose();
    _yearController.dispose();
    _directorController.dispose();
    _searchController.dispose();
    _searchScrollController
      ..removeListener(_onSearchScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加电影'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.55),
          indicatorColor: colorScheme.primary,
          tabs: const [
            Tab(text: '搜索', icon: Icon(Icons.search)),
            Tab(text: '豆瓣链接', icon: Icon(Icons.link)),
            Tab(text: '手动添加', icon: Icon(Icons.edit)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSearchTab(), _buildDoubanTab(), _buildManualTab()],
      ),
    );
  }

  // ==================== 搜索 tab ====================

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingMedium,
            AppTheme.spacingMedium,
            AppTheme.spacingMedium,
            AppTheme.spacingSmall,
          ),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索电影 / 剧集名',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchResults = [];
                          _searchSeenIds.clear();
                          _addedIds.clear();
                          _searchDone = false;
                          _searchError = null;
                          _searchHasMore = false;
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _runSearch(),
          ),
        ),
        Expanded(child: _buildSearchResults()),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_searchLoading) {
      return const LoadingState(message: '搜索中...');
    }
    if (_searchError != null && _searchResults.isEmpty) {
      return ErrorState(message: _searchError!, onRetry: _runSearch);
    }
    if (!_searchDone) {
      return const EmptyState(
        title: '搜索豆瓣电影',
        subtitle: '输入片名后回车即可搜索，点击结果加入片库。',
        icon: Icons.search,
      );
    }
    if (_searchResults.isEmpty) {
      return const EmptyState(
        title: '没有找到相关影片',
        subtitle: '换个关键词试试。',
        icon: Icons.search_off,
      );
    }

    final itemCount = _searchResults.length + (_searchLoadingMore ? 2 : 0);
    return GridView.builder(
      controller: _searchScrollController,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingMedium,
        AppTheme.spacingSmall,
        AppTheme.spacingMedium,
        AppTheme.spacingLarge,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.60,
        crossAxisSpacing: AppTheme.spacingMedium,
        mainAxisSpacing: AppTheme.spacingMedium,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= _searchResults.length) {
          return _buildMoviePlaceholderCard();
        }
        final movie = _searchResults[index];
        return Stack(
          children: [
            MovieCard(movie: movie, showWatchedBadge: false, onTap: null),
            Positioned(
              right: 10,
              bottom: 44,
              child: _buildSearchAddButton(movie),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchAddButton(Movie movie) {
    final added = _addedIds.contains(movie.id);
    final adding = _addingIds.contains(movie.id);

    if (added) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
      );
    }

    return GestureDetector(
      onTap: adding ? null : () => _addFromSearch(movie),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: adding
            ? const Padding(
                padding: EdgeInsets.all(7),
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_rounded, color: Colors.white, size: 22),
      ),
    );
  }

  void _onSearchScroll() {
    if (!_searchScrollController.hasClients) return;
    final position = _searchScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMoreSearch();
    }
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showError('请输入搜索关键词');
      return;
    }
    FocusScope.of(context).unfocus();
    final provider = context.read<MovieProvider>();
    setState(() {
      _searchQuery = query;
      _searchLoading = true;
      _searchError = null;
      _searchResults = [];
      _searchSeenIds.clear();
      _addedIds.clear();
      _searchStart = 0;
      _searchHasMore = false;
      _searchDone = true;
    });

    try {
      final results = await provider.searchDoubanMovies(query, start: 0);
      if (!mounted) return;
      final fresh = results
          .where((m) => _searchSeenIds.add(m.id))
          .toList(growable: false);
      final existing = await provider.getMoviesByIds(
        fresh.map((m) => m.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        _searchResults = fresh;
        _addedIds.addAll(existing.map((m) => m.id));
        _searchStart = _searchPageSize;
        _searchHasMore = results.length >= _searchPageSize;
      });
    } on ScraperException catch (error) {
      if (mounted) setState(() => _searchError = error.message);
    } catch (error) {
      if (mounted) setState(() => _searchError = '搜索失败: $error');
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _loadMoreSearch() async {
    if (_searchLoading || _searchLoadingMore || !_searchHasMore) return;
    setState(() => _searchLoadingMore = true);
    final provider = context.read<MovieProvider>();

    try {
      final results = await provider.searchDoubanMovies(
        _searchQuery,
        start: _searchStart,
      );
      if (!mounted) return;
      final fresh = results
          .where((m) => _searchSeenIds.add(m.id))
          .toList(growable: false);
      final existing = await provider.getMoviesByIds(
        fresh.map((m) => m.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        _searchResults = [..._searchResults, ...fresh];
        _addedIds.addAll(existing.map((m) => m.id));
        _searchStart += _searchPageSize;
        _searchHasMore = results.length >= _searchPageSize && fresh.isNotEmpty;
      });
    } catch (_) {
      // 分页出错就停止继续加载，不打断已有结果。
    } finally {
      if (mounted) setState(() => _searchLoadingMore = false);
    }
  }

  Future<void> _addFromSearch(Movie movie) async {
    if (_addingIds.contains(movie.id) || _addedIds.contains(movie.id)) return;
    setState(() => _addingIds.add(movie.id));
    final provider = context.read<MovieProvider>();

    try {
      // Keep search adds on the same full-detail path as Douban link adds.
      var toAdd = movie;
      final full = await provider.fetchMoviePreview(movie.doubanUrl);
      if (!mounted) return;
      if (full == null) {
        _showError(provider.error ?? 'Failed to fetch movie details');
        return;
      }
      toAdd = full;

      final saved = await provider.addScrapedMovie(toAdd);
      if (!mounted) return;
      if (saved != null) {
        setState(() {
          _addedIds
            ..add(movie.id)
            ..add(saved.id);
        });
        _showSuccess('已添加 ${toAdd.title}');
      } else {
        _showError(provider.error ?? '《${movie.title}》可能已在片库中');
      }
    } finally {
      if (mounted) setState(() => _addingIds.remove(movie.id));
    }
  }

  Widget _buildDoubanTab() {
    final textTheme = Theme.of(context).textTheme;
    final hasPreviewMovie = _previewMovie != null;
    final hasPreviewMovies =
        _previewMovies != null && _previewMovies!.isNotEmpty;
    final showDoulistSection = hasPreviewMovies || _isDoulistLoading;

    return CustomScrollView(
      key: const PageStorageKey('add-movie-douban-tab'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          sliver: SliverList.list(
            children: [
              SoftCard(
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '豆瓣导入',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingXSmall),
                    Text(
                      '支持电影链接、豆瓣 App 跳转链接和片单链接，如果失败请多尝试两次。',
                      style: textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: AppTheme.spacingMedium),
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        hintText: '粘贴豆瓣电影或片单链接',
                        prefixIcon: const Icon(Icons.link),
                        suffixIcon:
                            _urlController.text.isNotEmpty && !_isLoading
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () {
                                  _urlController.clear();
                                  setState(() {
                                    _isDoulistLoading = false;
                                    _doulistCompleted = 0;
                                    _doulistTotal = 0;
                                    _doulistCurrentTitle = null;
                                    _previewMovie = null;
                                    _previewMovies = null;
                                  });
                                },
                              )
                            : null,
                      ),
                      keyboardType: TextInputType.url,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppTheme.spacingLarge),
                    PrimaryButton(
                      label: _buildFetchButtonLabel(),
                      icon: Icons.search,
                      isLoading: _isLoading,
                      onPressed: _isLoading ? null : () => _scrapeFromUrl(),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: AppTheme.spacingMedium),
                      _buildScrapeProgressCard(),
                    ],
                  ],
                ),
              ),
              if (_isLoading && !_isDoulistLoading && !hasPreviewMovie) ...[
                const SizedBox(height: AppTheme.spacingLarge),
                _buildSectionHeader(title: '预览生成中', subtitle: '正在解析单片详情，请稍候。'),
                const SizedBox(height: AppTheme.spacingMedium),
                Center(
                  child: SizedBox(
                    width: 180,
                    height: 320,
                    child: _buildMoviePlaceholderCard(),
                  ),
                ),
              ],
              if (hasPreviewMovie) ...[
                const SizedBox(height: AppTheme.spacingLarge),
                _buildSectionHeader(title: '单片预览', subtitle: '确认信息后可直接加入片库。'),
                const SizedBox(height: AppTheme.spacingMedium),
                Center(
                  child: SizedBox(
                    width: 180,
                    height: 320,
                    child: MovieCard(movie: _previewMovie!, onTap: null),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingMedium),
                PrimaryButton(
                  label: '添加到片库',
                  icon: Icons.add,
                  onPressed: () => _addMovie(_previewMovie!),
                ),
                const SizedBox(height: AppTheme.spacingMedium),
              ],
              if (showDoulistSection) ...[
                const SizedBox(height: AppTheme.spacingLarge),
                _buildDoulistSectionHeader(),
                const SizedBox(height: AppTheme.spacingMedium),
              ],
            ],
          ),
        ),
        if (showDoulistSection)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingMedium,
              0,
              AppTheme.spacingMedium,
              AppTheme.spacingLarge,
            ),
            sliver: SliverGrid.builder(
              itemCount: _gridItemCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.60,
                crossAxisSpacing: AppTheme.spacingMedium,
                mainAxisSpacing: AppTheme.spacingMedium,
              ),
              itemBuilder: (context, index) {
                if (index >= (_previewMovies?.length ?? 0)) {
                  return _buildMoviePlaceholderCard();
                }

                final movie = _previewMovies![index];
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    MovieCard(movie: movie, onTap: () => _addMovie(movie)),
                    Positioned.fill(
                      child: Center(
                        child: GestureDetector(
                          onTap: () => _addMovie(movie),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accent.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  int get _gridItemCount {
    final previewCount = _previewMovies?.length ?? 0;
    return previewCount + _loadingPlaceholderCount;
  }

  int get _loadingPlaceholderCount {
    if (!_isDoulistLoading) return 0;

    if (_doulistTotal <= 0) {
      return 4;
    }

    final remaining = _doulistTotal - _doulistCompleted;
    if (remaining <= 0) return 0;
    return remaining > 4 ? 4 : remaining;
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppTheme.spacingXSmall),
              Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.62),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppTheme.spacingMedium),
          trailing,
        ],
      ],
    );
  }

  Widget _buildDoulistSectionHeader() {
    final title = _isDoulistLoading && _doulistTotal > 0
        ? '已获取 ${_previewMovies?.length ?? 0}/$_doulistTotal 部影片'
        : '找到 ${_previewMovies?.length ?? 0} 部电影';
    final subtitle = _isDoulistLoading
        ? '真实卡片会先显示，未完成的条目用占位卡补齐。'
        : '支持逐部添加，也可以一次性加入片库。';

    return _buildSectionHeader(
      title: title,
      subtitle: subtitle,
      trailing: PrimaryButton(
        label: '全部添加',
        icon: Icons.add,
        isFullWidth: false,
        onPressed: _isLoading || (_previewMovies?.isEmpty ?? true)
            ? null
            : () => _addAllMovies(_previewMovies!),
      ),
    );
  }

  Widget _buildMoviePlaceholderCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _placeholderController,
      builder: (context, child) {
        final surface = Color.lerp(
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurface.withValues(alpha: 0.08),
          _placeholderController.value,
        )!;
        final highlight = Color.lerp(
          colorScheme.onSurface.withValues(alpha: 0.06),
          colorScheme.onSurface.withValues(alpha: 0.14),
          _placeholderController.value,
        )!;

        return SoftContainer(
          padding: const EdgeInsets.all(8),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [surface, highlight, surface],
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.movie_creation_outlined,
                        size: 28,
                        color: colorScheme.onSurface.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildPlaceholderBar(
                widthFactor: 0.82,
                height: 15,
                color: highlight,
              ),
              const SizedBox(height: 8),
              _buildPlaceholderBar(
                widthFactor: 0.52,
                height: 11,
                color: surface,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: null,
                  minHeight: 6,
                  backgroundColor: colorScheme.onSurface.withValues(
                    alpha: 0.08,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(highlight),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderBar({
    required double widthFactor,
    required double height,
    required Color color,
  }) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildManualTab() {
    return SingleChildScrollView(
      key: const PageStorageKey('add-movie-manual-tab'),
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: '电影名称 *',
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          TextField(
            controller: _yearController,
            decoration: const InputDecoration(
              hintText: '年份（可选）',
              prefixIcon: Icon(Icons.calendar_today),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          TextField(
            controller: _directorController,
            decoration: const InputDecoration(
              hintText: '导演（可选）',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          PrimaryButton(
            label: '添加电影',
            icon: Icons.add,
            onPressed: () => _addManualMovie(),
          ),
        ],
      ),
    );
  }

  Future<void> _scrapeFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showError('请输入链接');
      return;
    }

    FocusScope.of(context).unfocus();
    final isDoulistUrl = url.contains('/doulist/');
    setState(() {
      _isLoading = true;
      _isDoulistLoading = isDoulistUrl;
      _doulistCompleted = 0;
      _doulistTotal = 0;
      _doulistCurrentTitle = null;
      _previewMovie = null;
      _previewMovies = null;
    });

    try {
      final provider = context.read<MovieProvider>();
      if (url.contains('/subject/') || url.contains('/dispatch/movie/')) {
        final movie = await provider.fetchMoviePreview(url);
        if (!mounted) return;
        if (movie != null) {
          setState(() => _previewMovie = movie);
        } else if (provider.error != null) {
          _showError(provider.error!);
        }
      } else if (url.contains('/doulist/')) {
        final movies = await provider.fetchDoulistPreview(
          url,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _doulistCompleted = progress.completed;
              _doulistTotal = progress.total;
              _doulistCurrentTitle = progress.currentTitle;
              _previewMovies = progress.movies;
            });
          },
        );
        if (!mounted) return;
        if (movies.isNotEmpty) {
          setState(() => _previewMovies = movies);
        } else if (provider.error != null) {
          _showError(provider.error!);
        }
      } else {
        _showError('无效的链接格式');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isDoulistLoading = false;
        });
      }
    }
  }

  String _buildFetchButtonLabel() {
    if (!_isLoading) {
      return '获取电影信息';
    }

    if (_isDoulistLoading && _doulistTotal > 0) {
      return '获取中 $_doulistCompleted/$_doulistTotal';
    }

    return '获取中...';
  }

  Widget _buildScrapeProgressCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progressValue = _doulistTotal > 0
        ? _doulistCompleted / _doulistTotal
        : null;

    return SoftCard(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isDoulistLoading ? '正在抓取片单详情' : '正在解析单片详情',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          Text(
            _isDoulistLoading
                ? (_doulistTotal > 0
                      ? '已完成 $_doulistCompleted / $_doulistTotal，结果会陆续显示在下方'
                      : '正在解析片单入口并准备抓取详情...')
                : '正在解析豆瓣页面结构化数据...',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          if ((_doulistCurrentTitle ?? '').isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              '最近完成：$_doulistCurrentTitle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addManualMovie() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showError('请输入电影名称');
      return;
    }

    final provider = context.read<MovieProvider>();
    await provider.addManualMovie(
      title: title,
      year: _yearController.text.trim(),
      director: _directorController.text.trim(),
    );

    if (!mounted) return;
    if (provider.error == null) {
      context.pop();
      _showSuccess('已添加 $title');
    } else {
      _showError(provider.error!);
    }
  }

  Future<void> _addMovie(Movie movie) async {
    final provider = context.read<MovieProvider>();
    final saved = await provider.addScrapedMovie(movie);
    if (!mounted) return;

    if (saved != null) {
      _showSuccess('已添加 ${movie.title}');
      setState(() => _previewMovie = null);
    } else if (provider.error != null) {
      _showError(provider.error!);
    }
  }

  Future<void> _addAllMovies(List<Movie> movies) async {
    final provider = context.read<MovieProvider>();
    final result = await provider.addScrapedMovies(movies);
    if (!mounted) return;

    if (result.added > 0 && result.skipped > 0) {
      _showSuccess('已添加 ${result.added} 部，${result.skipped} 部已存在');
    } else if (result.added > 0) {
      _showSuccess('成功添加 ${result.added} 部电影');
    } else {
      _showError('所有电影均已在片库中');
    }

    if (result.added > 0 && result.skipped == 0) {
      context.pop();
    }
  }

  void _showError(String message) {
    AppToast.error(context, message);
  }

  void _showSuccess(String message) {
    AppToast.success(context, message);
  }
}
