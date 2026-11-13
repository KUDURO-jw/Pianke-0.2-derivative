// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:random_movie/providers/app_notifier.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/services.dart';
import 'package:random_movie/services/app_error_log.dart';
import 'package:random_movie/config/design_tokens.dart';

/// Library filter mode: all / watched / unwatched.
enum LibraryFilter { all, watched, unwatched }

class MovieProvider extends AppNotifier {
  static const int initialLibraryPageSize = 12;
  static const int warmedLibraryTargetSize = 24;
  static const int libraryPageSize = 48;
  static const int historyPageSize = 20;

  final StorageService _storageService;
  final MovieScraperService _scraperService;
  final bool _ownsScraper;

  final Map<String, Movie> _movieCache = {};
  final Map<HistoryMonthKey, HistoryMonthData> _historyCalendarCache = {};
  List<Movie> _libraryMovies = [];
  List<SessionEntry> _sessionEntries = [];
  ViewingStats _viewingStats = const ViewingStats();
  bool _isBusy = false;
  int _busyOperations = 0;
  bool _isLibraryLoading = false;
  bool _isLibraryLoadingMore = false;
  bool _isLibraryWarming = false;
  bool _hasMoreLibrary = true;
  int _libraryRefreshRevision = 0;
  bool _isHistoryLoading = false;
  bool _isHistoryLoadingMore = false;
  bool _isHistoryCalendarLoading = false;
  bool _hasMoreHistory = true;
  int _historyPage = 0;
  int _historyRevision = 0;
  int _calendarRevision = 0;
  int _calendarGeneration = 0;
  bool _hasLoadedLibrary = false;
  bool _hasLoadedHistory = false;
  bool _hasLoadedHistoryCalendar = false;
  int _totalCount = 0;
  int _watchedCount = 0;
  LibraryFilter _libraryFilter = LibraryFilter.all;
  HistoryViewMode _historyViewMode = HistoryViewMode.list;
  HistoryMonthKey _visibleHistoryMonth = HistoryMonthKey.fromDate(
    DateTime.now(),
  );
  String? _error;
  String? _libraryError;
  String? _historyError;
  String? _calendarError;
  String? get libraryError => _libraryError;
  String? get historyError => _historyError;
  String? get calendarError => _calendarError;
  String _searchQuery = '';
  Timer? _searchDebounce;

  /// 「已从界面移除、但还没真正删库」的影片 id。
  ///
  /// 可撤销删除的实现方式：先让条目从列表消失（即时反馈），
  /// 5 秒内不撤销才真正 `deleteMovie`。这样撤销只是把它从集合里去掉，
  /// 不涉及任何数据库回滚——也正因为如此，撤销必定是完整的。
  final Set<String> _hiddenMovieIds = {};

  List<Movie> get movies => _libraryMovies
      .where((movie) => !_hiddenMovieIds.contains(movie.id))
      .toList(growable: false);
  List<Movie> get allMovies => movies;

  /// 从界面隐藏一条影片（撤销删除的「先隐藏」步骤）。
  void hideMovie(String movieId) {
    if (_hiddenMovieIds.add(movieId)) notifyListeners();
  }

  /// 恢复被隐藏的影片（用户点了「撤销」）。
  void restoreMovie(String movieId) {
    if (_hiddenMovieIds.remove(movieId)) notifyListeners();
  }

  /// 该影片当前是否处于「待删除」状态。
  bool isMovieHidden(String movieId) => _hiddenMovieIds.contains(movieId);
  List<SessionEntry> get sessionEntries => _sessionEntries;
  ViewingStats get viewingStats => _viewingStats;
  bool get isLoading => _isBusy;
  bool get isLibraryLoading => _isLibraryLoading;
  bool get isLibraryLoadingMore => _isLibraryLoadingMore;
  bool get hasMoreLibrary => _hasMoreLibrary;
  bool get isHistoryLoading => _isHistoryLoading;
  bool get isHistoryLoadingMore => _isHistoryLoadingMore;
  bool get isHistoryCalendarLoading => _isHistoryCalendarLoading;
  bool get hasMoreHistory => _hasMoreHistory;
  bool get hasLoadedLibrary => _hasLoadedLibrary;
  bool get hasLoadedHistory => _hasLoadedHistory;
  bool get hasLoadedHistoryCalendar => _hasLoadedHistoryCalendar;
  int get totalCount => _totalCount;
  int get watchedCount => _watchedCount;
  int get unwatchedCount => _totalCount - _watchedCount;
  LibraryFilter get libraryFilter => _libraryFilter;
  HistoryViewMode get historyViewMode => _historyViewMode;
  HistoryMonthKey get visibleHistoryMonth => _visibleHistoryMonth;
  HistoryMonthData? get visibleHistoryMonthData =>
      _historyCalendarCache[_visibleHistoryMonth];
  String? get error => _error;
  String get searchQuery => _searchQuery;

  MovieProvider({StorageService? storage, MovieScraperService? scraper})
    : _storageService = storage ?? StorageService(),
      _ownsScraper = scraper == null,
      _scraperService = scraper ?? MovieScraperService();

  /// 仅供测试：用给定影片直接构造，跳过数据库读取。
  ///
  /// 用于验证「待删除隐藏集合」这类纯内存行为，不需要真库。
  MovieProvider.forTesting({required List<Movie> movies})
    : _storageService = StorageService(),
      _ownsScraper = false,
      _scraperService = MovieScraperService() {
    _libraryMovies = List<Movie>.of(movies);
    _cacheMovies(movies);
    _hasLoadedLibrary = true;
  }

  void _cacheMovies(Iterable<Movie> movies) {
    if (isDisposed) return;
    for (final movie in movies) {
      _movieCache.remove(movie.id);
      _movieCache[movie.id] = movie;
      if (_movieCache.length > 512) _movieCache.remove(_movieCache.keys.first);
    }
  }

  Movie? peekMovieById(String id) => _movieCache[id];

  Future<Movie?> getMovieById(String id, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _movieCache[id];
      if (cached != null) return cached;
    }

    final movie = await _storageService.getMovieById(id);
    if (movie != null) {
      _cacheMovies([movie]);
    } else {
      _movieCache.remove(id);
    }
    return movie;
  }

  Future<List<Movie>> getMoviesByIds(Iterable<String> ids) async {
    final movies = await _storageService.getMoviesByIds(ids);
    _cacheMovies(movies);
    return movies;
  }

  Future<List<String>> getAllMovieIds({bool unwatchedOnly = false}) {
    return _storageService.queryMovieIds(unwatchedOnly: unwatchedOnly);
  }

  Future<int> getMovieCount({bool unwatchedOnly = false}) {
    return _storageService.countMovies(unwatchedOnly: unwatchedOnly);
  }

  Future<void> loadMovies() => refreshLibrary();

  Future<void> ensureLibraryLoaded() async {
    if (_hasLoadedLibrary || _isLibraryLoading) return;
    await refreshLibrary();
  }

  Future<void> ensureHistoryLoaded() async {
    if (_hasLoadedHistory || _isHistoryLoading) return;
    await refreshWatchedHistory();
  }

  Future<void> refreshLibrary() {
    final initial = !_hasLoadedLibrary && _searchQuery.trim().isEmpty;
    return _refreshLibrary(
      limit: initial ? initialLibraryPageSize : libraryPageSize,
      warm: initial,
    );
  }

  Future<void> _refreshLibrary({required int limit, bool warm = false}) async {
    if (isDisposed) return;
    final revision = ++_libraryRefreshRevision;
    _searchDebounce?.cancel();
    _isLibraryLoading = true;
    _isLibraryLoadingMore = false;
    _isLibraryWarming = false;
    _libraryError = null;
    if (_hasLoadedLibrary) notifyListeners();
    try {
      final results = await Future.wait<Object>([
        _storageService.queryMovies(
          limit: limit,
          offset: 0,
          searchQuery: _searchQuery,
          watchedOnly: _libraryFilter == LibraryFilter.watched,
          unwatchedOnly: _libraryFilter == LibraryFilter.unwatched,
        ),
        _storageService.countMovies(),
        _storageService.countMovies(watchedOnly: true),
      ]);
      if (isDisposed || revision != _libraryRefreshRevision) return;
      _libraryMovies = results[0] as List<Movie>;
      _totalCount = results[1] as int;
      _watchedCount = results[2] as int;
      _hasMoreLibrary = _libraryMovies.length == limit;
      _cacheMovies(_libraryMovies);
      if (warm && _hasMoreLibrary) _scheduleLibraryWarmUp(revision);
    } catch (error) {
      if (revision == _libraryRefreshRevision) _libraryError = '加载片库失败: $error';
    } finally {
      if (revision == _libraryRefreshRevision) {
        _hasLoadedLibrary = true;
        _isLibraryLoading = false;
        notifyListeners();
      }
    }
  }

  void _scheduleLibraryWarmUp(int refreshRevision) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isDisposed || refreshRevision != _libraryRefreshRevision) return;
      unawaited(warmUpLibraryAfterFirstFrame(refreshRevision: refreshRevision));
    });
  }

  Future<void> warmUpLibraryAfterFirstFrame({int? refreshRevision}) async {
    final activeRevision = refreshRevision ?? _libraryRefreshRevision;
    if (isDisposed || activeRevision != _libraryRefreshRevision) {
      return;
    }
    if (_searchQuery.trim().isNotEmpty ||
        _isLibraryLoading ||
        _isLibraryLoadingMore ||
        _isLibraryWarming ||
        !_hasMoreLibrary) {
      return;
    }

    final currentCount = _libraryMovies.length;
    final extraLimit = warmedLibraryTargetSize - currentCount;
    if (extraLimit <= 0) return;

    _isLibraryWarming = true;
    try {
      final movies = await _storageService.queryMovies(
        limit: extraLimit,
        offset: currentCount,
        searchQuery: _searchQuery,
        watchedOnly: _libraryFilter == LibraryFilter.watched,
        unwatchedOnly: _libraryFilter == LibraryFilter.unwatched,
      );
      if (isDisposed || activeRevision != _libraryRefreshRevision) {
        return;
      }
      if (movies.isEmpty) {
        _hasMoreLibrary = false;
        notifyListeners();
      } else {
        _libraryMovies = [..._libraryMovies, ...movies];
        _hasMoreLibrary = movies.length == extraLimit;
        _cacheMovies(movies);
        notifyListeners();
      }
    } catch (_) {
    } finally {
      if (activeRevision == _libraryRefreshRevision) {
        _isLibraryWarming = false;
      }
    }
  }

  Future<void> loadMoreLibrary() async {
    if (isDisposed ||
        _isLibraryLoading ||
        _isLibraryLoadingMore ||
        _isLibraryWarming ||
        !_hasMoreLibrary) {
      return;
    }

    final revision = _libraryRefreshRevision;
    _isLibraryLoadingMore = true;
    _libraryError = null;
    notifyListeners();

    try {
      final movies = await _storageService.queryMovies(
        limit: libraryPageSize,
        offset: _libraryMovies.length,
        searchQuery: _searchQuery,
        watchedOnly: _libraryFilter == LibraryFilter.watched,
        unwatchedOnly: _libraryFilter == LibraryFilter.unwatched,
      );
      if (isDisposed || revision != _libraryRefreshRevision) return;
      if (movies.isEmpty) {
        _hasMoreLibrary = false;
      } else {
        _libraryMovies = [..._libraryMovies, ...movies];
        _hasMoreLibrary = movies.length == libraryPageSize;
        _cacheMovies(movies);
      }
    } catch (error) {
      if (revision == _libraryRefreshRevision) {
        _libraryError = '加载更多影片失败: $error';
      }
    } finally {
      if (revision == _libraryRefreshRevision) {
        _isLibraryLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshWatchedHistory() =>
      _refreshHistory(limit: historyPageSize);

  Future<void> _refreshHistory({required int limit}) async {
    if (isDisposed) return;
    final revision = ++_historyRevision;
    _isHistoryLoading = true;
    _isHistoryLoadingMore = false;
    _historyError = null;
    if (_hasLoadedHistory) notifyListeners();
    try {
      final sessions = await _storageService.querySessions(
        limit: limit,
        offset: 0,
      );
      final entries = await _hydrateSessions(sessions);
      final stats = await _storageService.queryViewingStats();
      if (isDisposed || revision != _historyRevision) return;
      _sessionEntries = entries;
      _cacheMovies(entries.map((entry) => entry.movie));
      _viewingStats = stats;
      _historyPage = sessions.isEmpty
          ? 0
          : (sessions.length - 1) ~/ historyPageSize;
      _hasMoreHistory = sessions.length == limit;
    } catch (error) {
      if (revision == _historyRevision) _historyError = '加载观影记录失败: $error';
    } finally {
      if (revision == _historyRevision) {
        _hasLoadedHistory = true;
        _isHistoryLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreWatchedHistory() async {
    if (isDisposed ||
        _isHistoryLoading ||
        _isHistoryLoadingMore ||
        !_hasMoreHistory) {
      return;
    }
    final revision = _historyRevision;
    _isHistoryLoadingMore = true;
    _historyError = null;
    notifyListeners();
    try {
      final nextPage = _historyPage + 1;
      final sessions = await _storageService.querySessions(
        limit: historyPageSize,
        offset: nextPage * historyPageSize,
      );
      final entries = await _hydrateSessions(sessions);
      if (isDisposed || revision != _historyRevision) return;
      _sessionEntries = [..._sessionEntries, ...entries];
      _cacheMovies(entries.map((entry) => entry.movie));
      if (sessions.isNotEmpty) _historyPage = nextPage;
      _hasMoreHistory = sessions.length == historyPageSize;
    } catch (error) {
      if (revision == _historyRevision) _historyError = '加载更多观影记录失败: $error';
    } finally {
      if (revision == _historyRevision) {
        _isHistoryLoadingMore = false;
        notifyListeners();
      }
    }
  }

  /// 为一页会话补齐影片数据，跳过影片已被删除的孤儿会话。
  Future<List<SessionEntry>> _hydrateSessions(
    List<ViewingSession> sessions,
  ) async {
    if (sessions.isEmpty) return const [];
    final movieIds = sessions.map((s) => s.movieId).toSet();
    final movies = await _storageService.getMoviesByIds(movieIds);
    final movieById = {for (final movie in movies) movie.id: movie};
    final entries = <SessionEntry>[];
    for (final session in sessions) {
      final movie = movieById[session.movieId];
      if (movie == null) continue;
      entries.add(SessionEntry(session: session, movie: movie));
    }
    return entries;
  }

  Future<void> ensureHistoryCalendarLoaded() async {
    if (_hasLoadedHistoryCalendar || _isHistoryCalendarLoading) return;
    await refreshHistoryCalendarMonth();
  }

  Future<void> refreshHistoryCalendarMonth({
    HistoryMonthKey? month,
    bool forceRefresh = false,
  }) async {
    if (isDisposed) return;
    final target = month ?? _visibleHistoryMonth;
    final revision = ++_calendarRevision;
    final generation = _calendarGeneration;
    final cached = _historyCalendarCache[target];
    if (!forceRefresh && cached != null) {
      _hasLoadedHistoryCalendar = true;
      _isHistoryCalendarLoading = false;
      _calendarError = null;
      notifyListeners();
      return;
    }
    _isHistoryCalendarLoading = true;
    _calendarError = null;
    notifyListeners();
    try {
      // 两个来源合并：
      // 1. 电影 / 手动记录的观影会话（原有逻辑）
      // 2. 电视剧逐集勾选时写入的分集日期（本次新增）
      //
      // 不用 Future.wait：两个 Future 返回不同类型，会被推断成
      // List<Object>，后续强转虽然能过分析器，但类型一旦对不上就是
      // 运行时崩溃。这里分开 await，类型由编译器保证。
      final movies = await _storageService.queryWatchedMoviesByMonth(
        target.firstDay,
      );
      final seriesEpisodes = await _storageService.querySeriesEpisodesByMonth(
        target.firstDay,
      );
      if (isDisposed ||
          generation != _calendarGeneration ||
          revision != _calendarRevision) {
        return;
      }
      _cacheHistoryMonth(
        target,
        _buildHistoryMonthData(target, movies, seriesEpisodes),
      );
      if (revision == _calendarRevision) _hasLoadedHistoryCalendar = true;
    } catch (error) {
      if (revision == _calendarRevision) _calendarError = '加载观影日历失败: $error';
    } finally {
      if (revision == _calendarRevision) {
        _isHistoryCalendarLoading = false;
        notifyListeners();
      }
    }
    if (!isDisposed && revision == _calendarRevision) {
      unawaited(_warmHistoryCalendarAdjacentMonths(target));
    }
  }

  void _cacheHistoryMonth(HistoryMonthKey month, HistoryMonthData data) {
    _historyCalendarCache.remove(month);
    _historyCalendarCache[month] = data;
    // Visible month plus a small working set; browsing years must stay bounded.
    while (_historyCalendarCache.length > 9) {
      final oldest = _historyCalendarCache.keys.firstWhere(
        (key) => key != _visibleHistoryMonth,
      );
      _historyCalendarCache.remove(oldest);
    }
  }

  Future<void> setVisibleHistoryMonth(HistoryMonthKey month) async {
    if (_visibleHistoryMonth == month) return;
    _visibleHistoryMonth = month;
    notifyListeners();
    await refreshHistoryCalendarMonth(month: month);
  }

  Future<void> jumpToCurrentHistoryMonth() async {
    final currentMonth = HistoryMonthKey.fromDate(DateTime.now());
    if (_visibleHistoryMonth != currentMonth) {
      await setVisibleHistoryMonth(currentMonth);
      return;
    }

    if (_historyCalendarCache.containsKey(currentMonth)) {
      _hasLoadedHistoryCalendar = true;
      _isHistoryCalendarLoading = false;
      notifyListeners();
      return;
    }

    await refreshHistoryCalendarMonth(month: currentMonth, forceRefresh: true);
  }

  void setHistoryViewMode(HistoryViewMode mode) {
    if (_historyViewMode == mode) return;
    _historyViewMode = mode;
    notifyListeners();
    if (mode == HistoryViewMode.calendar) {
      unawaited(ensureHistoryCalendarLoaded());
    }
  }

  void setSearchQueryDebounced(String query) {
    if (isDisposed || _searchQuery == query) return;
    ++_libraryRefreshRevision;
    _isLibraryLoading = true;
    _isLibraryLoadingMore = false;
    _isLibraryWarming = false;
    _searchQuery = query;
    _libraryError = null;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(Motion.debounce, refreshLibrary);
    notifyListeners();
  }

  Future<void> setSearchQuery(String query) async {
    _searchQuery = query;
    _searchDebounce?.cancel();
    await refreshLibrary();
  }

  /// Switch between all / watched / unwatched filter and reload.
  Future<void> setLibraryFilter(LibraryFilter filter) async {
    if (_libraryFilter == filter) return;
    _libraryFilter = filter;
    await refreshLibrary();
  }

  Future<void> refreshAfterSync() async {
    _movieCache.clear();
    await _reloadVisibleCollections();
    await _refreshVisibleHistoryCalendarIfNeeded();
  }

  Future<void> _reloadVisibleCollections() async {
    await Future.wait([
      _refreshLibrary(
        limit: math.max(_libraryMovies.length, initialLibraryPageSize),
      ),
      if (_hasLoadedHistory || _isHistoryLoading)
        _refreshHistory(
          limit: math.max(
            (_historyPage + 1) * historyPageSize,
            historyPageSize,
          ),
        ),
    ]);
  }

  Future<void> addManualMovie({
    required String title,
    String? year,
    String? director,
    String? cast,
  }) async {
    if (title.trim().isEmpty) {
      _error = '影片名称不能为空';
      notifyListeners();
      return;
    }

    _busyOperations++;
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      final movie = Movie(
        id: '',
        title: title.trim(),
        year: year ?? '',
        director: director ?? '',
        cast: cast ?? '',
      );
      final savedMovie = await _storageService.addMovie(movie);
      _cacheMovies([savedMovie]);
      await _reloadVisibleCollections();
      await _refreshVisibleHistoryCalendarIfNeeded();
    } catch (error) {
      _error = '添加失败: $error';
      notifyListeners();
    } finally {
      _busyOperations--;
      _isBusy = _busyOperations > 0;
      notifyListeners();
    }
  }

  Future<Movie?> fetchMoviePreview(String doubanUrl) async {
    if (doubanUrl.trim().isEmpty) {
      _error = '请输入豆瓣链接';
      notifyListeners();
      return null;
    }

    _busyOperations++;
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      return await _scraperService.scrapeMovie(doubanUrl.trim());
    } on ScraperException catch (error) {
      _error = error.message;
      return null;
    } catch (error) {
      _error = '爬取失败: $error';
      return null;
    } finally {
      _busyOperations--;
      _isBusy = _busyOperations > 0;
      notifyListeners();
    }
  }

  /// 豆瓣关键词搜索，返回轻量 Movie（点选后再抓完整详情）。
  /// [start] 为分页偏移（每页 15），用于滚动加载下一页。
  Future<List<Movie>> searchDoubanMovies(String query, {int start = 0}) async {
    final results = await _scraperService.searchMovies(query, start: start);
    return results
        .map(
          (r) => Movie(
            id: r.id.startsWith('douban_') ? r.id : 'douban_${r.id}',
            title: r.title,
            year: r.year,
            rating: r.rating,
            poster: r.cover,
            doubanUrl: r.url,
          ),
        )
        .toList();
  }

  Future<List<Movie>> fetchDoulistPreview(
    String doulistUrl, {
    void Function(DoulistScrapeProgress progress)? onProgress,
  }) async {
    if (doulistUrl.trim().isEmpty) {
      _error = '请输入片单链接';
      notifyListeners();
      return [];
    }

    _busyOperations++;
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      return await _scraperService.scrapeDoulist(
        doulistUrl.trim(),
        onProgress: onProgress,
      );
    } on ScraperException catch (error) {
      _error = error.message;
      return [];
    } catch (error) {
      _error = '爬取失败: $error';
      return [];
    } finally {
      _busyOperations--;
      _isBusy = _busyOperations > 0;
      notifyListeners();
    }
  }

  Future<Movie?> addScrapedMovie(Movie movie) async {
    _busyOperations++;
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      final savedMovie = await _storageService.addMovie(movie);
      _cacheMovies([savedMovie]);
      await _reloadVisibleCollections();
      await _refreshVisibleHistoryCalendarIfNeeded();
      return savedMovie;
    } on DuplicateMovieException {
      _error = '《${movie.title}》已在片库中';
      return null;
    } catch (error, stack) {
      // 这类失败会被界面接住并显示，不算未捕获异常，全局处理器收不到。
      // 显式记进诊断日志，用户导出时才能看到真正原因
      // （例如主键冲突导致的添加失败）。
      AppErrorLog.recordHandled(
        'addMovie',
        error,
        stack: stack,
        detail: 'title=${movie.title} id=${movie.id}',
      );
      _error = '保存失败: $error';
      return null;
    } finally {
      _busyOperations--;
      _isBusy = _busyOperations > 0;
      notifyListeners();
    }
  }

  Future<({int added, int skipped, List<Movie> failed})> addScrapedMovies(
    List<Movie> movies,
  ) async {
    _busyOperations++;
    _isBusy = true;
    _error = null;
    notifyListeners();

    var added = 0;
    var skipped = 0;
    final failed = <Movie>[];

    try {
      for (final movie in movies) {
        try {
          final savedMovie = await _storageService.addMovie(movie);
          _cacheMovies([savedMovie]);
          added++;
        } on DuplicateMovieException {
          skipped++;
        } catch (error, stack) {
          // 这里原本是 catch (_) 完全吞掉，用户只看到「有 N 部失败」，
          // 不知道是网络、主键冲突还是别的原因。记进诊断日志。
          AppErrorLog.recordHandled(
            'addScrapedMovies',
            error,
            stack: stack,
            detail: 'title=${movie.title} id=${movie.id}',
          );
          failed.add(movie);
        }
      }

      await _reloadVisibleCollections();
      await _refreshVisibleHistoryCalendarIfNeeded();
      return (
        added: added,
        skipped: skipped,
        failed: List<Movie>.unmodifiable(failed),
      );
    } finally {
      _busyOperations--;
      _isBusy = _busyOperations > 0;
      notifyListeners();
    }
  }

  Future<void> updateMovie(Movie movie) async {
    _error = null;

    try {
      await _storageService.updateMovie(movie);
      _cacheMovies([movie]);
      await _reloadVisibleCollections();
      await _refreshVisibleHistoryCalendarIfNeeded();
    } catch (error, stack) {
      AppErrorLog.recordHandled(
        'updateMovie',
        error,
        stack: stack,
        detail: 'id=${movie.id}',
      );
      _error = '更新失败: $error';
      notifyListeners();
    }
  }

  Future<void> deleteMovie(String movieId) async {
    _error = null;
    try {
      await _storageService.deleteMovie(movieId);
      _movieCache.remove(movieId);
      // 删库成功后隐藏标记必须清掉，否则同 id 的影片重新导入时就永远不显示。
      _hiddenMovieIds.remove(movieId);
      await _reloadVisibleCollections();
      await _refreshVisibleHistoryCalendarIfNeeded();
    } catch (error, stack) {
      AppErrorLog.recordHandled(
        'deleteMovie',
        error,
        stack: stack,
        detail: 'id=$movieId',
      );
      // 删库失败：把它放回界面，别让用户以为已经删掉了。
      _hiddenMovieIds.remove(movieId);
      _error = '删除失败: $error';
      notifyListeners();
    }
  }

  /// 切换「看过」。
  ///
  /// 方向判定统一走 [WatchStatus.isWatched]，与片库、抽片页保持一致，
  /// 避免剧集「分集已看完」却被判成未看而重复新增会话。
  ///
  /// 取消已看时会同时清空观影会话与剧集分集的已看标记，
  /// 否则剧集的分集状态会残留，导致界面显示与数据不一致。
  Future<void> toggleWatched(String movieId) async {
    final movie = await getMovieById(movieId, forceRefresh: true);
    if (movie == null) return;

    if (WatchStatus.isWatched(movie)) {
      await _storageService.deleteSessionsByMovie(movieId);
      final clearedEpisodes = movie.episodes
          .map((episode) => episode.copyWith(watched: false))
          .toList(growable: false);
      await _storageService.updateMovie(
        movie.copyWith(
          watched: false,
          clearWatchedAt: true,
          episodes: clearedEpisodes,
        ),
      );
    } else {
      await _storageService.addSession(
        ViewingSession(id: '', movieId: movieId, watchedAt: DateTime.now()),
      );
    }
    await _afterSessionChange(movieId);
  }

  /// 新增一次观影会话。
  Future<ViewingSession?> addViewingSession(ViewingSession session) async {
    _error = null;
    try {
      final stored = await _storageService.addSession(session);
      await _afterSessionChange(session.movieId);
      return stored;
    } catch (error) {
      _error = '记录失败: $error';
      notifyListeners();
      return null;
    }
  }

  /// 更新一次观影会话。
  Future<void> updateViewingSession(ViewingSession session) async {
    _error = null;
    try {
      await _storageService.updateSession(session);
      await _afterSessionChange(session.movieId);
    } catch (error) {
      _error = '更新失败: $error';
      notifyListeners();
    }
  }

  /// 删除一次观影会话。
  Future<void> deleteViewingSession(String sessionId, String movieId) async {
    _error = null;
    try {
      await _storageService.deleteSession(sessionId);
      await _afterSessionChange(movieId);
    } catch (error) {
      _error = '删除失败: $error';
      notifyListeners();
    }
  }

  /// 查询某部影片的全部观影会话。
  Future<List<ViewingSession>> sessionsForMovie(String movieId) {
    return _storageService.querySessionsByMovie(movieId);
  }

  /// 会话变更后刷新片库/观影/日历，并刷新该影片缓存。
  Future<void> _afterSessionChange(String movieId) async {
    final refreshed = await _storageService.getMovieById(movieId);
    if (refreshed != null) {
      _cacheMovies([refreshed]);
    } else {
      _movieCache.remove(movieId);
    }
    await _reloadVisibleCollections();
    await _refreshVisibleHistoryCalendarIfNeeded();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  HistoryMonthData _buildHistoryMonthData(
    HistoryMonthKey month,
    List<Movie> movies, [
    List<({Movie movie, List<int> episodeNumbers})> seriesEpisodes = const [],
  ]) {
    // day → 该天的影片（保持插入顺序，先电影后剧集）
    final grouped = <int, List<Movie>>{};
    // day → 该天的剧集集号明细
    final episodesByDay = <int, Map<String, List<int>>>{};

    void addMovie(int day, Movie movie) {
      final list = grouped.putIfAbsent(day, () => <Movie>[]);
      // 同一部剧可能同时有观影会话和分集日期，
      // 只保留一条，避免日历里同一部片出现两次。
      if (!list.any((m) => m.id == movie.id)) list.add(movie);
    }

    for (final movie in movies) {
      final watchDate = movie.watchedAt ?? movie.createdAt;
      addMovie(watchDate.day, movie);
    }

    // 剧集按「每一集的日期」归到对应那天。
    // 同一天勾了第 5、6、7 集，就在那一天记下 [5,6,7]。
    //
    // 必须校验年月：movie.episodes 里含该剧所有分集的全部日期，
    // 可能横跨多个月。若只按 `day` 分组，去年同一天看的那集会
    // 被错误地算进本月。
    for (final entry in seriesEpisodes) {
      final movie = entry.movie;
      final byDay = <int, List<int>>{};
      for (final episode in movie.episodes) {
        final at = episode.watchedAt;
        if (!episode.watched || at == null) continue;
        if (at.year != month.year || at.month != month.month) continue;
        byDay.putIfAbsent(at.day, () => <int>[]).add(episode.number);
      }
      for (final dayEntry in byDay.entries) {
        addMovie(dayEntry.key, movie);
        final numbers = episodesByDay.putIfAbsent(dayEntry.key, () => {});
        numbers.putIfAbsent(movie.id, () => <int>[]).addAll(dayEntry.value);
      }
    }

    final summaries = <int, HistoryDaySummary>{};
    for (final entry in grouped.entries) {
      final dayEpisodes = episodesByDay[entry.key] ?? const <String, List<int>>{};
      // 集号去重并排序，防止同一集被重复计入。
      final normalized = <String, List<int>>{
        for (final e in dayEpisodes.entries)
          e.key: (e.value.toSet().toList()..sort()),
      };
      summaries[entry.key] = HistoryDaySummary(
        date: DateTime(month.year, month.month, entry.key),
        movies: List<Movie>.unmodifiable(entry.value),
        episodeNumbersByMovieId: Map<String, List<int>>.unmodifiable(normalized),
      );
    }

    return HistoryMonthData(
      month: month,
      summariesByDay: Map<int, HistoryDaySummary>.unmodifiable(summaries),
    );
  }

  Future<void> _warmHistoryCalendarAdjacentMonths(HistoryMonthKey month) async {
    final generation = _calendarGeneration;
    final revision = _calendarRevision;
    for (final candidate in [month.previous(), month.next()]) {
      if (isDisposed ||
          generation != _calendarGeneration ||
          revision != _calendarRevision) {
        return;
      }
      if (_historyCalendarCache.containsKey(candidate)) continue;
      try {
        final movies = await _storageService.queryWatchedMoviesByMonth(
          candidate.firstDay,
        );
        if (isDisposed ||
            generation != _calendarGeneration ||
            revision != _calendarRevision) {
          return;
        }
        _cacheHistoryMonth(
          candidate,
          _buildHistoryMonthData(candidate, movies),
        );
      } catch (_) {}
    }
  }

  void _invalidateHistoryCalendarCache() {
    ++_calendarGeneration;
    ++_calendarRevision;
    _historyCalendarCache.clear();
    _hasLoadedHistoryCalendar = false;
  }

  Future<void> _refreshVisibleHistoryCalendarIfNeeded() async {
    final visible = _hasLoadedHistoryCalendar || _isHistoryCalendarLoading;
    _invalidateHistoryCalendarCache();
    if (visible) await refreshHistoryCalendarMonth(forceRefresh: true);
  }

  @override
  void dispose() {
    ++_libraryRefreshRevision;
    ++_historyRevision;
    ++_calendarRevision;
    ++_calendarGeneration;
    _searchDebounce?.cancel();
    _movieCache.clear();
    _historyCalendarCache.clear();
    if (_ownsScraper) _scraperService.dispose();
    super.dispose();
  }
}
