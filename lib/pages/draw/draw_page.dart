// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/services/services.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/draw/draw_filter_panel.dart';
import 'package:random_movie/services/draw_candidate_report.dart';
import 'package:random_movie/widgets/movie/draw_shuffle_card.dart';
import 'package:random_movie/widgets/movie/movie_card.dart';
import 'package:random_movie/router/movie_detail_arguments.dart';
import 'package:random_movie/widgets/movie/selectable_movie_grid.dart';
import 'package:random_movie/widgets/movie/viewing_session_editor.dart';

enum DrawPhase { selecting, animating, picking, result }

/// 抽片页面：选片 + 模式 + 筛选 -> 动画/三选一 -> 结果
class DrawPage extends StatefulWidget {
  /// 预置候选影片 id（如「从本合集抽片」）。为空则默认全库未看。
  final List<String>? presetMovieIds;

  /// 预置来源名称（合集名），用于 AppBar 提示。
  final String? presetTitle;
  final StorageService? storage;

  const DrawPage({
    super.key,
    this.presetMovieIds,
    this.presetTitle,
    this.storage,
  });

  @override
  State<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage> {
  static const int _pageSize = 48;

  late final StorageService _storageService;
  final ScrollController _scrollController = ScrollController();

  DrawPhase _phase = DrawPhase.selecting;
  DrawMode _mode = DrawMode.pureRandom;
  DrawFilter _filter = DrawFilter.none;
  MovieFacets _facets = const MovieFacets();
  List<MovieTag> _tags = const [];

  final DrawSelectionState _selectionState = DrawSelectionState();
  final Map<DrawMode, bool> _unwatchedOnlyByMode = {
    for (final mode in DrawMode.values) mode: false,
  };
  final Map<String, Movie> _movieCache = {};
  List<Movie> _loadedMovies = [];
  List<Movie> _candidates = [];
  DrawResultData? _result;
  List<Movie> _threeOptions = [];
  String? _recordId;

  bool _isInitialLoading = true;
  bool _initialLoadFailed = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  int _totalCount = 0;
  int _selectionRevision = 0;
  bool _selectionLoading = false;
  String? _selectionError;
  String? _reportKey;
  Future<DrawCandidateReport>? _reportFuture;

  Set<String> get _selectedIds => _selectionState.selectedIds(_mode);

  Timer? _shuffleTimer;
  int _displayIndex = 0;
  int _shuffleCount = 0;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storage ?? StorageService();
    _scrollController.addListener(_handleScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _shuffleTimer?.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_phase != DrawPhase.selecting || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMoreMovies();
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isInitialLoading = true;
      _initialLoadFailed = false;
    });

    try {
      final preset = widget.presetMovieIds;
      if (preset != null) {
        // 预置候选（合集抽片）：只载入这些影片，默认全选
        final scopedPreset = DrawSelection.restrictToScope(preset);
        final movies = await _storageService.getMoviesByIds(scopedPreset);
        _loadedMovies = movies;
        _totalCount = movies.map((movie) => movie.id).toSet().length;
        _page = 0;
        _hasMore = false;
        _selectionState.replaceAllModes(movies.map((m) => m.id));
        _cacheMovies(movies);
        await _loadAuxData(defaultSelection: null);
        return;
      }

      // 核心：先载入片库（计数 + 首页），保证辅助查询失败时也能正常显示影片。
      final totalCount = await _storageService.countMovies();
      final firstPage = await _storageService.queryMovies(
        limit: _pageSize,
        offset: 0,
      );
      _loadedMovies = firstPage;
      _totalCount = totalCount;
      _page = 0;
      _hasMore = firstPage.length < totalCount;
      _cacheMovies(firstPage);

      // 辅助数据 + 默认选中；状态查询失败时保持空选中，避免误判为未看。
      await _loadAuxData(defaultSelection: firstPage.map((m) => m.id));
    } catch (_) {
      _initialLoadFailed = true;
    } finally {
      if (mounted) {
        setState(() => _isInitialLoading = false);
      }
    }
  }

  /// 辅助数据（标签 / 维度 / 默认选中）——各自失败时降级，绝不阻塞主片库显示。
  Future<void> _loadAuxData({
    required Iterable<String>? defaultSelection,
  }) async {
    try {
      _tags = await _storageService.queryAllTags();
    } catch (_) {
      _tags = const [];
    }
    try {
      _facets = await _storageService.queryMovieFacets();
    } catch (_) {
      _facets = const MovieFacets();
    }
    // preset 情况已自行设定选中，跳过默认选中逻辑。
    if (defaultSelection == null) return;
    try {
      final unwatchedIds = await _storageService.queryMovieIds(
        unwatchedOnly: true,
      );
      _selectionState.replaceAllModes(
        DrawSelection.selectUnwatched(unwatchedIds, scope: _presetScopeIds),
      );
      for (final mode in DrawMode.values) {
        _unwatchedOnlyByMode[mode] = true;
      }
      _selectionError = null;
    } catch (_) {
      _selectionState.clearAll();
      _selectionError = '无法读取影片的已看状态，请重试后再抽片';
    }
  }

  Future<void> _loadMoreMovies() async {
    if (_isInitialLoading || _isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _page + 1;
      final movies = await _storageService.queryMovies(
        limit: _pageSize,
        offset: nextPage * _pageSize,
      );
      if (movies.isNotEmpty) {
        _loadedMovies = [..._loadedMovies, ...movies];
        _page = nextPage;
        _hasMore = _loadedMovies.length < _totalCount;
        _cacheMovies(movies);
      } else {
        _hasMore = false;
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _cacheMovies(Iterable<Movie> movies) {
    for (final movie in movies) {
      _movieCache[movie.id] = movie;
    }
  }

  Iterable<String>? get _presetScopeIds => widget.presetMovieIds == null
      ? null
      : DrawSelection.restrictToScope(widget.presetMovieIds!);

  Future<void> _selectAllMovies() async {
    await _replaceSelection(unwatchedOnly: false);
  }

  Future<void> _selectUnwatchedMovies() async {
    await _replaceSelection(unwatchedOnly: true);
  }

  Future<void> _replaceSelection({required bool unwatchedOnly}) async {
    final revision = ++_selectionRevision;
    final targetMode = _mode;
    setState(() {
      _selectionLoading = true;
      _selectionError = null;
    });
    try {
      final ids = await _storageService.queryMovieIds(
        unwatchedOnly: unwatchedOnly,
      );
      final allIds = _presetScopeIds == null
          ? await _storageService.queryMovieIds()
          : DrawSelection.restrictToScope(_presetScopeIds!);
      final scopedIds = unwatchedOnly
          ? DrawSelection.selectUnwatched(ids, scope: _presetScopeIds)
          : DrawSelection.selectAll(allIds);
      final visibleMovies = await _storageService.getMoviesByIds(allIds);
      if (!mounted || revision != _selectionRevision) return;

      setState(() {
        _selectionState.replace(targetMode, scopedIds);
        _unwatchedOnlyByMode[targetMode] = unwatchedOnly;
        _loadedMovies = visibleMovies;
        _cacheMovies(visibleMovies);
        _totalCount = visibleMovies.length;
        _hasMore = false;
        _page = 0;
        _selectionLoading = false;
      });
    } catch (_) {
      if (!mounted || revision != _selectionRevision) return;
      setState(() {
        _selectionLoading = false;
        _selectionError = '无法读取影片的已看状态，请重试后再筛选';
      });
    }
  }

  Future<void> _openFilterPanel() async {
    final result = await showDrawFilterPanel(
      context,
      initialFilter: _filter,
      facets: _facets,
      tags: _tags,
    );
    if (result != null && mounted) {
      setState(() => _filter = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle),
        automaticallyImplyLeading: _phase != DrawPhase.animating,
      ),
      body: switch (_phase) {
        DrawPhase.selecting => _buildSelectingPhase(context),
        DrawPhase.animating => _buildAnimatingPhase(context),
        DrawPhase.picking => _buildPickingPhase(context),
        DrawPhase.result => _buildResultPhase(context),
      },
    );
  }

  String get _appBarTitle {
    switch (_phase) {
      case DrawPhase.selecting:
        return widget.presetTitle != null
            ? '从《${widget.presetTitle}》抽'
            : '今晚看什么？';
      case DrawPhase.animating:
        return '抽取中…';
      case DrawPhase.picking:
        return '三选一';
      case DrawPhase.result:
        return '抽片结果';
    }
  }

  // ==================== 选片阶段 ====================

  Widget _buildSelectingPhase(BuildContext context) {
    if (_isInitialLoading) {
      return const LoadingState(message: '加载片库中…');
    }
    if (_initialLoadFailed) {
      return ErrorState(message: '无法读取本地片库，请重试', onRetry: _loadInitialData);
    }

    if (_totalCount == 0) {
      if (_unwatchedOnlyByMode[_mode] == true) {
        return EmptyState(
          title: '当前范围没有未看影片',
          subtitle: '可切回全部影片重新选择',
          icon: Icons.filter_alt_off,
          onAction: _selectAllMovies,
          actionLabel: '查看全部',
        );
      }
      if (widget.presetMovieIds != null) {
        return const EmptyState(
          title: '这个合集暂时没有可抽影片',
          subtitle: '返回合集添加影片后再试',
          icon: Icons.movie_outlined,
        );
      }
      return EmptyState(
        title: '片库是空的',
        subtitle: '先去添加几部影片吧',
        icon: Icons.movie_outlined,
        onAction: () => context.go('/movies/add'),
        actionLabel: '去添加',
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .34,
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildModeSelector(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingMedium,
                    0,
                    AppTheme.spacingMedium,
                    AppTheme.spacingSmall,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    children: [
                      Text(
                        '已选 ${_selectedIds.length} / 共 $_totalCount 部',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _selectionLoading
                                ? null
                                : _selectAllMovies,
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: _selectionLoading
                                ? null
                                : _selectUnwatchedMovies,
                            child: const Text('仅未看'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_selectionError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMedium,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _selectionError!,
                        style: TextStyle(
                          color: colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SelectableMovieGrid(
            storageKey: const PageStorageKey('draw-selection-grid'),
            controller: _scrollController,
            movies: _loadedMovies,
            selectedIds: _selectedIds,
            hasMore: _hasMore,
            isLoadingMore: _isLoadingMore,
            onToggle: (movie) {
              _selectionRevision++;
              setState(() {
                _selectionState.toggle(_mode, movie.id);
              });
            },
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(AppTheme.spacingMedium),
          child: _buildCandidateActions(),
        ),
      ],
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingMedium,
        AppTheme.spacingSmall,
        AppTheme.spacingMedium,
        AppTheme.spacingSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(13) + 25,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final mode in DrawMode.values) ...[
                  _ModeChip(
                    label: mode.label,
                    selected: _mode == mode,
                    onTap: () => setState(() => _mode = mode),
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _mode.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
              _FilterButton(
                activeCount: _filter.activeCount,
                onTap: _openFilterPanel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 抽取 ====================

  Future<DrawCandidateReport> _candidateReport() async {
    final ids = DrawSelection.restrictToScope(
      Set<String>.of(_selectedIds),
      scope: _presetScopeIds,
    );
    final filter = _filter;
    final onlyUnwatched = _unwatchedOnlyByMode[_mode] == true;
    var movies = await _storageService.getMoviesByIds(ids);
    if (onlyUnwatched) movies = WatchStatus.unwatchedMovies(movies);
    final tags = filter.tagIds.isEmpty
        ? null
        : (await _storageService.queryMovieIdsByTags(filter.tagIds)).toSet();
    return DrawCandidateReport.analyze(movies, filter, allowedByTags: tags);
  }

  Widget _buildCandidateActions() {
    final key =
        '${_mode.value}:${Object.hashAllUnordered(_selectedIds)}:${identityHashCode(_filter)}:${_unwatchedOnlyByMode[_mode]}:$_selectionRevision';
    if (_reportKey != key) {
      _reportKey = key;
      _reportFuture = _candidateReport();
    }
    return FutureBuilder<DrawCandidateReport>(
      future: _reportFuture,
      builder: (context, snapshot) {
        final ready =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        final count = ready ? snapshot.data?.count ?? 0 : 0;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .38,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_filter.isActive)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final option in activeDrawFilters(_filter))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InputChip(
                              label: Text(option.label),
                              onDeleted: () =>
                                  setState(() => _filter = option.removed),
                            ),
                          ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _filter = DrawFilter.none),
                          child: const Text('清空筛选'),
                        ),
                      ],
                    ),
                  ),
                Text(
                  snapshot.hasError
                      ? '候选读取失败'
                      : ready
                      ? '符合条件 $count 部'
                      : '正在统计候选…',
                ),
                if (snapshot.hasError)
                  TextButton(
                    onPressed: () => setState(() => _reportKey = null),
                    child: const Text('重试'),
                  ),
                if (ready && count == 0 && _selectedIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      snapshot.data!.explanations.join('；'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 6),
                PrimaryButton(
                  label: _selectedIds.isEmpty
                      ? '请先选择影片'
                      : ready && count == 0
                      ? '没有符合条件的影片'
                      : '${_mode.label} · 开始${ready ? '（$count 部）' : ''}',
                  icon: Icons.casino,
                  onPressed: ready && count > 0 && !_selectionLoading
                      ? _startDraw
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startDraw() async {
    // Re-read the selected set immediately before drawing to avoid stale state.
    final selectedIds = DrawSelection.restrictToScope(
      _selectedIds,
      scope: _presetScopeIds,
    );
    var selected = await _storageService.getMoviesByIds(selectedIds);
    if (_unwatchedOnlyByMode[_mode] == true) {
      selected = WatchStatus.unwatchedMovies(selected);
      _selectionState.replace(_mode, selected.map((movie) => movie.id));
    }
    Set<String>? allowedByTags;
    if (_filter.tagIds.isNotEmpty) {
      allowedByTags = (await _storageService.queryMovieIdsByTags(
        _filter.tagIds,
      )).toSet();
    }
    final filtered = DrawService.smartFilter(
      selected,
      _filter,
      allowedMovieIds: allowedByTags,
    );

    if (filtered.isEmpty) {
      if (!mounted) return;
      AppToast.error(context, _filter.isActive ? '没有符合筛选条件的影片' : '没有可用的候选影片');
      return;
    }

    _candidates = filtered;
    _cacheMovies(_candidates);

    final drawContext = await _buildDrawContext();
    if (!mounted) return;

    if (_mode == DrawMode.threePickOne) {
      _threeOptions = DrawService.threePickOne(
        _candidates,
        mode: _mode,
        context: drawContext,
      );
      setState(() => _phase = DrawPhase.picking);
      return;
    }

    _result = DrawService.draw(_candidates, mode: _mode, context: drawContext);

    setState(() {
      _phase = DrawPhase.animating;
      _shuffleCount = 0;
      _displayIndex = 0;
    });

    _startShuffleAnimation();
  }

  Future<DrawContext> _buildDrawContext() async {
    if (_mode != DrawMode.fair) return DrawContext.empty;
    final results = await Future.wait([
      _storageService.queryRecentlyDrawnMovieIds(),
      _storageService.queryRecentlyWatchedMovieIds(),
    ]);
    return DrawContext(
      recentlyDrawnIds: results[0],
      recentlyWatchedIds: results[1],
    );
  }

  void _startShuffleAnimation() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _onAnimationComplete();
      return;
    }
    const int fastCount = 20;

    _shuffleTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _shuffleCount++;
      if (_shuffleCount <= fastCount) {
        if (!mounted) return;
        setState(() {
          _displayIndex = (_displayIndex + 1) % _candidates.length;
        });
      } else {
        timer.cancel();
        _startSlowPhase(0);
      }
    });
  }

  void _startSlowPhase(int step) {
    const int slowSteps = 4;
    if (step >= slowSteps) {
      setState(() {
        _displayIndex = _candidates.indexOf(_result!.selectedMovie);
        if (_displayIndex == -1) {
          _displayIndex = 0;
        }
      });
      Future.delayed(const Duration(milliseconds: 500), _onAnimationComplete);
      return;
    }

    final delay = Duration(milliseconds: 200 + step * 100);
    Future.delayed(delay, () {
      if (!mounted) return;
      setState(() {
        _displayIndex = (_displayIndex + 1) % _candidates.length;
      });
      _startSlowPhase(step + 1);
    });
  }

  Future<void> _onAnimationComplete() async {
    if (!mounted || _result == null) return;
    await _recordDraw(_result!);
    if (!mounted) return;
    setState(() => _phase = DrawPhase.result);
  }

  /// 写入一条 pending 记录，记下 id 以便后续标记 accepted/skipped。
  Future<void> _recordDraw(DrawResultData result) async {
    final record = DrawService.buildSoloRecord(
      result: result,
      candidateCount: _candidates.length,
    );
    _recordId = record.id;
    await context.read<DrawHistoryProvider>().addRecord(record);
  }

  // ==================== 三选一阶段 ====================

  Widget _buildPickingPhase(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLarge),
      child: Column(
        children: [
          const SizedBox(height: AppTheme.spacingSmall),
          Icon(Icons.looks_3_rounded, size: 42, color: AppTheme.accent),
          const SizedBox(height: AppTheme.spacingSmall),
          Text(
            '三选一',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '抽出了这 ${_threeOptions.length} 部，可以先看详情再决定',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          for (var index = 0; index < _threeOptions.length; index++) ...[
            _PickCard(
              optionIndex: index + 1,
              totalCount: _threeOptions.length,
              movie: _threeOptions[index],
              onPick: () => _onPickOne(_threeOptions[index]),
              onDetail: () =>
                  context.push('/movies/detail/${_threeOptions[index].id}'),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
          ],
          const SizedBox(height: AppTheme.spacingMedium),
          SecondaryButton(
            label: '都不要，重抽',
            icon: Icons.refresh,
            onPressed: _retry,
          ),
          const SizedBox(height: AppTheme.spacingLarge),
        ],
      ),
    );
  }

  Future<void> _onPickOne(Movie movie) async {
    final index = _candidates.indexOf(movie);
    _result = DrawResultData(
      selectedMovie: movie,
      seed: DateTime.now().microsecondsSinceEpoch,
      index: index < 0 ? 0 : index,
    );
    await _recordDraw(_result!);
    if (!mounted) return;
    setState(() => _phase = DrawPhase.result);
  }

  // ==================== 动画阶段 ====================

  Widget _buildAnimatingPhase(BuildContext context) {
    final currentMovie = _candidates[_displayIndex % _candidates.length];
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 80),
            child: DrawShuffleCard(
              movie: currentMovie,
              shuffleCount: _shuffleCount,
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          Text(
            '抽取中…',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 结果阶段 ====================

  Widget _buildResultPhase(BuildContext context) {
    final result = _result!;
    final movie = result.selectedMovie;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingLarge,
        vertical: AppTheme.spacingLarge,
      ),
      child: Column(
        children: [
          const SizedBox(height: AppTheme.spacingLarge),
          Icon(Icons.celebration, size: 48, color: AppTheme.accent),
          const SizedBox(height: AppTheme.spacingSmall),
          Text(
            '就决定是它了！',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '已写入抽片历史，接下来可以接受、跳过或补记观影',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          SizedBox(
            width: 200,
            height: 330,
            child: MovieCard(
              movie: movie,
              posterHeroTag: 'draw-result:${movie.id}',
              showWatchedBadge: false,
              onTap: () => context.push(
                '/movies/detail/${movie.id}',
                extra: MovieDetailArguments(
                  movie,
                  posterTag: 'draw-result:${movie.id}',
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          _buildResultMeta(context, movie),
          const SizedBox(height: AppTheme.spacingXLarge),
          PrimaryButton(
            label: '就看这个',
            icon: Icons.check_circle_outline,
            onPressed: () => _acceptResult(context),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          SecondaryButton(
            label: '跳过，再抽一次',
            icon: Icons.skip_next,
            onPressed: () => _skipResult(context),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: WatchStatus.isWatched(movie) ? '再记录一次' : '记录观影',
                  icon: Icons.edit_note_rounded,
                  onPressed: () => _recordViewing(context, movie),
                ),
              ),
              const SizedBox(width: AppTheme.spacingMedium),
              Expanded(
                child: SecondaryButton(
                  label: '查看详情',
                  icon: Icons.info_outline,
                  onPressed: () => context.push('/movies/detail/${movie.id}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXLarge),
        ],
      ),
    );
  }

  Future<void> _acceptResult(BuildContext context) async {
    final router = GoRouter.of(context);
    final provider = context.read<DrawHistoryProvider>();
    if (_recordId != null) {
      await provider.updateOutcome(_recordId!, DrawOutcome.accepted);
    }
    if (!mounted) return;
    router.pop();
  }

  Widget _buildResultMeta(BuildContext context, Movie movie) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = <String>[
      if (movie.year.isNotEmpty) movie.year,
      if (movie.durationMinutes != null) '${movie.durationMinutes} 分钟',
      if (movie.rating > 0) '★ ${movie.rating.toStringAsFixed(1)}',
      if (movie.region.isNotEmpty) movie.region,
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppTheme.spacingSmall,
      runSpacing: AppTheme.spacingSmall,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: ShapeDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide.none,
                ),
              ),
              child: Text(item, style: const TextStyle(fontSize: 12)),
            ),
          )
          .toList(),
    );
  }

  Future<void> _skipResult(BuildContext context) async {
    final provider = context.read<DrawHistoryProvider>();
    if (_recordId != null) {
      await provider.updateOutcome(_recordId!, DrawOutcome.skipped);
    }
    if (!mounted) return;
    _retry();
  }

  void _retry() {
    setState(() {
      _phase = DrawPhase.selecting;
      _result = null;
      _threeOptions = [];
      _recordId = null;
      _shuffleCount = 0;
      _displayIndex = 0;
    });
  }

  Future<void> _recordViewing(BuildContext context, Movie movie) async {
    final movieProvider = context.read<MovieProvider>();
    final draft = await showViewingSessionEditor(
      context,
      movieId: movie.id,
      defaultIsRewatch: WatchStatus.isWatched(movie),
    );
    if (draft == null || !mounted) return;

    final saved = await movieProvider.addViewingSession(draft);
    if (saved == null || !mounted || _result == null) return;

    final updatedMovie =
        await movieProvider.getMovieById(movie.id, forceRefresh: true) ??
        movie.copyWith(watched: true, watchedAt: draft.watchedAt);
    if (!mounted || _result == null) return;

    setState(() {
      _movieCache[updatedMovie.id] = updatedMovie;
      _result = DrawResultData(
        selectedMovie: updatedMovie,
        seed: _result!.seed,
        index: _result!.index,
      );
    });
    if (!mounted) return;
    AppToast.success(this.context, '已记录《${movie.title}》的观影');
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
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
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
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
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _FilterButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = activeCount > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: 6,
        ),
        decoration: ShapeDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            side: BorderSide(
              color: active
                  ? AppTheme.accent
                  : colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune,
              size: 16,
              color: active ? AppTheme.accent : colorScheme.onSurface,
            ),
            const SizedBox(width: 4),
            Text(
              active ? '筛选 · $activeCount' : '筛选',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? AppTheme.accent : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  final int optionIndex;
  final int totalCount;
  final Movie movie;
  final VoidCallback onPick;
  final VoidCallback onDetail;

  const _PickCard({
    required this.optionIndex,
    required this.totalCount,
    required this.movie,
    required this.onPick,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final meta = [
      if (movie.year.isNotEmpty) movie.year,
      if (movie.durationMinutes != null) '${movie.durationMinutes} 分钟',
      if (movie.rating > 0) '★ ${movie.rating.toStringAsFixed(1)}',
    ].join(' · ');

    return GestureDetector(
      onTap: onPick,
      child: SoftContainer(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: 78,
                  height: 112,
                  child: _PosterOnly(movie: movie, onTap: onDetail),
                ),
                Positioned(
                  left: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: ShapeDecoration(
                      color: AppTheme.accent,
                      shadows: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.28),
                          blurRadius: 8,
                        ),
                      ],
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide.none,
                      ),
                    ),
                    child: Text(
                      '$optionIndex/$totalCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppTheme.spacingSmall),
                  Row(
                    children: [
                      PrimaryButton(
                        label: '选它',
                        icon: Icons.check,
                        isFullWidth: false,
                        onPressed: onPick,
                      ),
                      const SizedBox(width: AppTheme.spacingSmall),
                      IconButton(
                        tooltip: '查看详情',
                        onPressed: onDetail,
                        icon: const Icon(Icons.info_outline_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterOnly extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;

  const _PosterOnly({required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: movie.poster.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: movie.poster,
                httpHeaders: ApiConfig.imageHeaders,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) =>
                    ColoredBox(color: colorScheme.surfaceContainerHighest),
                errorWidget: (_, _, _) => ColoredBox(
                  color: colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.movie, size: 28),
                ),
              )
            : ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.movie,
                  size: 28,
                  color: colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
      ),
    );
  }
}
