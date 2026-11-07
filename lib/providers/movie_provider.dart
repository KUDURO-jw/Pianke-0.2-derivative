import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/services.dart';

/// Library filter mode: all / watched / unwatched.
enum LibraryFilter { all, watched, unwatched }

class MovieProvider extends ChangeNotifier {
  static const int initialLibraryPageSize = 12;
  static const int warmedLibraryTargetSize = 24;
  static const int libraryPageSize = 48;
  static const int historyPageSize = 20;

  final StorageService _storageService = StorageService();
  final MovieScraperService _scraperService = MovieScraperService();

  final Map<String, Movie> _movieCache = {};
  final Map<HistoryMonthKey, HistoryMonthData> _historyCalendarCache = {};
  List<Movie> _libraryMovies = [];
  List<SessionEntry> _sessionEntries = [];
  ViewingStats _viewingStats = const ViewingStats();
  bool _isBusy = false;
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
  String _searchQuery = '';
  Timer? _searchDebounce;

  List<Movie> get movies => _libraryMovies;
  List<Movie> get allMovies => _libraryMovies;
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

  MovieProvider();

  void _cacheMovies(Iterable<Movie> movies) {
    for (final movie in movies) {
      _movieCache[movie.id] = movie;
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

  Future<void> refreshLibrary() async {
    final shouldNotifyLoading =
        _hasLoadedLibrary || _libraryMovies.isNotEmpty || _error != null;
    final refreshRevision = ++_libraryRefreshRevision;
    final useReducedInitialBatch =
        !_hasLoadedLibrary && _searchQuery.trim().isEmpty;
    final limit = useReducedInitialBatch
        ? initialLibraryPageSize
        : libraryPageSize;
    _searchDebounce?.cancel();
    _isLibraryLoading = true;
    _isLibraryWarming = false;
    _error = null;
    if (shouldNotifyLoading) {
      notifyListeners();
    }

    try {
      final watchedOnly = _libraryFilter == LibraryFilter.watched;
      final unwatchedOnly = _libraryFilter == LibraryFilter.unwatched;
      final results = await Future.wait<Object>([
        _storageService.queryMovies(
          limit: limit,
          offset: 0,
          searchQuery: _searchQuery,
          watchedOnly: watchedOnly,
          unwatchedOnly: unwatchedOnly,
        ),
        _storageService.countMovies(),
        _storageService.countMovies(watchedOnly: true),
      ]);
      if (refreshRevision != _libraryRefreshRevision) return;
      final movies = results[0] as List<Movie>;
      _totalCount = results[1] as int;
      _watchedCount = results[2] as int;
      _libraryMovies = movies;
      _hasMoreLibrary = movies.length == limit;
      _cacheMovies(movies);
      if (useReducedInitialBatch && movies.isNotEmpty && _hasMoreLibrary) {
        _scheduleLibraryWarmUp(refreshRevision);
      }
    } catch (error) {
      if (refreshRevision == _libraryRefreshRevision) {
        _error = '加载片库失败: $error';
      }
    } finally {
      if (refreshRevision == _libraryRefreshRevision) {
        _hasLoadedLibrary = true;
        _isLibraryLoading = false;
        notifyListeners();
      }
    }
  }

  void _scheduleLibraryWarmUp(int refreshRevision) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (refreshRevision != _libraryRefreshRevision) return;
      unawaited(warmUpLibraryAfterFirstFrame(refreshRevision: refreshRevision));
    });
  }

  Future<void> warmUpLibraryAfterFirstFrame({int? refreshRevision}) async {
    final activeRevision = refreshRevision ?? _libraryRefreshRevision;
    if (activeRevision != _libraryRefreshRevision) {
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
      if (activeRevision != _libraryRefreshRevision) {
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
    if (_isLibraryLoading ||
        _isLibraryLoadingMore ||
        _isLibraryWarming ||
        !_hasMoreLibrary) {
      return;
    }

    _isLibraryLoadingMore = true;
    notifyListeners();

    try {
      final movies = await _storageService.queryMovies(
        limit: libraryPageSize,
        offset: _libraryMovies.length,
        searchQuery: _searchQuery,
        watchedOnly: _libraryFilter == LibraryFilter.watched,
        unwatchedOnly: _libraryFilter == LibraryFilter.unwatched,
      );
      if (movies.isEmpty) {
        _hasMoreLibrary = false;
      } else {
        _libraryMovies = [..._libraryMovies, ...movies];
        _hasMoreLibrary = movies.length == libraryPageSize;
        _cacheMovies(movies);
      }
    } catch (error) {
      _error = '加载更多影片失败: $error';
    } finally {
      _isLibraryLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refreshWatchedHistory() async {
    final shouldNotifyLoading =
        _hasLoadedHistory || _sessionEntries.isNotEmpty || _error != null;
    _isHistoryLoading = true;
    _error = null;
    if (shouldNotifyLoading) {
      notifyListeners();
    }

    try {
      final sessions = await _storageService.querySessions(
        limit: historyPageSize,
        offset: 0,
      );
      _sessionEntries = await _hydrateSessions(sessions);
      _historyPage = 0;
      _hasMoreHistory = sessions.length == historyPageSize;
      _viewingStats = await _storageService.queryViewingStats();
    } catch (error) {
      _error = '加载观影记录失败: $error';
    } finally {
      _hasLoadedHistory = true;
      _isHistoryLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreWatchedHistory() async {
    if (_isHistoryLoading || _isHistoryLoadingMore || !_hasMoreHistory) return;

    _isHistoryLoadingMore = true;
    notifyListeners();

    try {
      final nextPage = _historyPage + 1;
      final sessions = await _storageService.querySessions(
        limit: historyPageSize,
        offset: nextPage * historyPageSize,
      );
      if (sessions.isEmpty) {
        _hasMoreHistory = false;
      } else {
        _sessionEntries = [
          ..._sessionEntries,
          ...await _hydrateSessions(sessions),
        ];
        _historyPage = nextPage;
        _hasMoreHistory = sessions.length == historyPageSize;
      }
    } catch (error) {
      _error = '加载更多观影记录失败: $error';
    } finally {
      _isHistoryLoadingMore = false;
      notifyListeners();
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
    _cacheMovies(movies);

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
    final targetMonth = month ?? _visibleHistoryMonth;
    if (_isHistoryCalendarLoading &&
        targetMonth == _visibleHistoryMonth &&
        !forceRefresh) {
      return;
    }
    if (!forceRefresh && _historyCalendarCache.containsKey(targetMonth)) {
      _hasLoadedHistoryCalendar = true;
      if (targetMonth == _visibleHistoryMonth) {
        notifyListeners();
      }
      unawaited(_warmHistoryCalendarAdjacentMonths(targetMonth));
      return;
    }

    if (targetMonth == _visibleHistoryMonth) {
      _isHistoryCalendarLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final movies = await _storageService.queryWatchedMoviesByMonth(
        targetMonth.firstDay,
      );
      _historyCalendarCache[targetMonth] = _buildHistoryMonthData(
        targetMonth,
        movies,
      );
      _hasLoadedHistoryCalendar = true;
      if (targetMonth == _visibleHistoryMonth) {
        _error = null;
      }
    } catch (error) {
      if (targetMonth == _visibleHistoryMonth) {
        _error = '加载观影日历失败: $error';
      }
    } finally {
      if (targetMonth == _visibleHistoryMonth) {
        _isHistoryCalendarLoading = false;
        notifyListeners();
      }
    }

    unawaited(_warmHistoryCalendarAdjacentMonths(targetMonth));
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
    _searchQuery = query;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), refreshLibrary);
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
    await _reloadVisibleCollections();
    await _refreshVisibleHistoryCalendarIfNeeded();
  }

  Future<void> _reloadVisibleCollections() async {
    final libraryLimit = math.max(
      _libraryMovies.length,
      initialLibraryPageSize,
    );
    final historyLimit = math.max(
      (_historyPage + 1) * historyPageSize,
      historyPageSize,
    );

    final results = await Future.wait<Object>([
      _storageService.queryMovies(
        limit: libraryLimit,
        offset: 0,
        searchQuery: _searchQuery,
        watchedOnly: _libraryFilter == LibraryFilter.watched,
        unwatchedOnly: _libraryFilter == LibraryFilter.unwatched,
      ),
      _storageService.countMovies(),
      _storageService.querySessions(limit: historyLimit, offset: 0),
      _storageService.countMovies(watchedOnly: true),
      _storageService.countSessions(),
      _storageService.queryViewingStats(),
    ]);

    final libraryMovies = results[0] as List<Movie>;
    final libraryCount = results[1] as int;
    final sessions = results[2] as List<ViewingSession>;
    final watchedMovieCount = results[3] as int;
    final sessionCount = results[4] as int;
    final stats = results[5] as ViewingStats;

    _libraryMovies = libraryMovies;
    _sessionEntries = await _hydrateSessions(sessions);
    _totalCount = libraryCount;
    _watchedCount = watchedMovieCount;
    _viewingStats = stats;
    _historyPage = sessions.isEmpty
        ? 0
        : ((sessions.length - 1) / historyPageSize).floor();
    _hasMoreLibrary = libraryMovies.length < libraryCount;
    _hasMoreHistory = sessions.length < sessionCount;
    _hasLoadedLibrary = true;
    _hasLoadedHistory = true;
    _cacheMovies(libraryMovies);
    notifyListeners();
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
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<Movie?> fetchMoviePreview(String doubanUrl) async {
    if (doubanUrl.trim().isEmpty) {
      _error = '请输入豆瓣链接';
      notifyListeners();
      return null;
    }

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
      _isBusy = false;
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
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<Movie?> addScrapedMovie(Movie movie) async {
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
    } catch (error) {
      _error = '保存失败: $error';
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<({int added, int skipped})> addScrapedMovies(
    List<Movie> movies,
  ) async {
    _isBusy = true;
    _error = null;
    notifyListeners();

    var added = 0;
    var skipped = 0;

    try {
      for (final movie in movies) {
        try {
          final savedMovie = await _storageService.addMovie(movie);
          _cacheMovies([savedMovie]);
          added++;
        } on DuplicateMovieException {
          skipped++;
        } catch (_) {}
      }

      await _reloadVisibleCollections();
      await _refreshVisibleHistoryCalendarIfNeeded();
      return (added: added, skipped: skipped);
    } finally {
      _isBusy = false;
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
    } catch (error) {
      _error = '更新失败: $error';
      notifyListeners();
    }
  }

  Future<void> deleteMovie(String movieId) async {
    _error = null;
    try {
      await _storageService.deleteMovie(movieId);
      _movieCache.remove(movieId);
      await _reloadVisibleCollections();
      await _refreshVisibleHistoryCalendarIfNeeded();
    } catch (error) {
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
    List<Movie> movies,
  ) {
    final grouped = <int, List<Movie>>{};
    for (final movie in movies) {
      final watchDate = movie.watchedAt ?? movie.createdAt;
      grouped.putIfAbsent(watchDate.day, () => <Movie>[]).add(movie);
    }

    final summaries = <int, HistoryDaySummary>{};
    for (final entry in grouped.entries) {
      summaries[entry.key] = HistoryDaySummary(
        date: DateTime(month.year, month.month, entry.key),
        movies: List<Movie>.unmodifiable(entry.value),
      );
    }

    return HistoryMonthData(
      month: month,
      summariesByDay: Map<int, HistoryDaySummary>.unmodifiable(summaries),
    );
  }

  Future<void> _warmHistoryCalendarAdjacentMonths(HistoryMonthKey month) async {
    for (final candidate in [month.previous(), month.next()]) {
      if (_historyCalendarCache.containsKey(candidate)) continue;
      try {
        final movies = await _storageService.queryWatchedMoviesByMonth(
          candidate.firstDay,
        );
        _historyCalendarCache[candidate] = _buildHistoryMonthData(
          candidate,
          movies,
        );
      } catch (_) {}
    }
  }

  void _invalidateHistoryCalendarCache() {
    _historyCalendarCache.clear();
    _hasLoadedHistoryCalendar = false;
  }

  Future<void> _refreshVisibleHistoryCalendarIfNeeded() async {
    if (!_hasLoadedHistoryCalendar) return;
    _invalidateHistoryCalendarCache();
    await refreshHistoryCalendarMonth(forceRefresh: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
