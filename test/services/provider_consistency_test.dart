import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/services/storage_service.dart';

class _Store implements StorageService {
  Future<List<Movie>> Function(int, int, String, bool)? movies;
  Future<List<ViewingSession>> Function(int, int)? sessions;
  Future<List<Movie>> Function(DateTime)? calendar;
  Future<List<DrawRecord>> Function(int, int)? draws;
  Future<Movie> Function(Movie)? save;
  @override
  Future<List<Movie>> queryMovies({
    required int limit,
    required int offset,
    String searchQuery = '',
    bool watchedOnly = false,
    bool unwatchedOnly = false,
  }) =>
      movies?.call(limit, offset, searchQuery, watchedOnly) ?? Future.value([]);
  @override
  Future<int> countMovies({
    String searchQuery = '',
    bool watchedOnly = false,
    bool unwatchedOnly = false,
  }) async => 100;
  @override
  Future<List<ViewingSession>> querySessions({
    required int limit,
    required int offset,
  }) => sessions?.call(limit, offset) ?? Future.value([]);
  @override
  Future<ViewingStats> queryViewingStats() async => const ViewingStats();
  @override
  Future<List<Movie>> getMoviesByIds(Iterable<String> ids) async =>
      ids.map((id) => Movie(id: id, title: id)).toList();
  @override
  Future<List<Movie>> queryWatchedMoviesByMonth(DateTime month) =>
      calendar?.call(month) ?? Future.value([]);

  /// 日历现在还会查「分集日期」。
  ///
  /// 这个测试替身只需要给出空结果：本文件验证的是竞态（旧请求不得覆盖
  /// 新结果），与分集无关。真实聚合逻辑另见 calendar_series_test.dart。
  @override
  Future<List<({Movie movie, List<int> episodeNumbers})>>
  querySeriesEpisodesByMonth(DateTime month) => Future.value(const []);
  @override
  Future<List<DrawRecord>> queryDrawRecords({
    required int limit,
    required int offset,
  }) => draws?.call(limit, offset) ?? Future.value([]);
  @override
  Future<void> clearDrawHistory() async {}
  @override
  Future<Movie> addMovie(Movie movie) =>
      save?.call(movie) ?? Future.value(movie);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Movie> _movies(String prefix, int count) =>
    List.generate(count, (i) => Movie(id: '$prefix$i', title: '$prefix$i'));
ViewingSession _session(String id) =>
    ViewingSession(id: id, movieId: id, watchedAt: DateTime(2026));
DrawRecord _draw(String id) => DrawRecord(
  id: id,
  movieId: id,
  movieTitle: id,
  moviePoster: '',
  seed: 1,
  candidateCount: 1,
  drawnAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old pagination cannot append after a filter refresh', () async {
    final pending = Completer<List<Movie>>();
    final store = _Store()
      ..movies = (limit, offset, query, watched) async => offset > 0
          ? pending.future
          : _movies(watched ? 'watched' : 'old', 12);
    final provider = MovieProvider(storage: store);
    await provider.refreshLibrary();
    final load = provider.loadMoreLibrary();
    await provider.setLibraryFilter(LibraryFilter.watched);
    pending.complete(_movies('stale', 5));
    await load;
    expect(provider.movies.every((m) => m.id.startsWith('watched')), isTrue);
    expect(provider.isLibraryLoadingMore, isFalse);
    provider.dispose();
  });

  test(
    'typing invalidates the in-flight list before debounce elapses',
    () async {
      final pending = Completer<List<Movie>>();
      final store = _Store()..movies = (_, _, _, _) => pending.future;
      final provider = MovieProvider(storage: store);
      final load = provider.refreshLibrary();
      provider.setSearchQueryDebounced('新查询');
      pending.complete(_movies('old', 2));
      await load;
      expect(provider.movies, isEmpty);
      expect(provider.isLibraryLoading, isTrue);
      provider.dispose();
    },
  );

  test(
    'latest search wins even when the previous request completes later',
    () async {
      final pending = Completer<List<Movie>>();
      final store = _Store()
        ..movies = (_, _, query, _) =>
            query == 'old' ? pending.future : Future.value(_movies('new', 2));
      final provider = MovieProvider(storage: store);
      final old = provider.setSearchQuery('old');
      await provider.setSearchQuery('new');
      pending.complete(_movies('stale', 2));
      await old;
      expect(provider.movies.first.id, 'new0');
      provider.dispose();
    },
  );

  test('history refresh invalidates an older pending page', () async {
    final pending = Completer<List<ViewingSession>>();
    var refreshed = false;
    final store = _Store()
      ..sessions = (_, offset) async => offset > 0
          ? pending.future
          : refreshed
          ? [_session('new')]
          : List.generate(20, (i) => _session('old$i'));
    final provider = MovieProvider(storage: store);
    await provider.refreshWatchedHistory();
    final load = provider.loadMoreWatchedHistory();
    refreshed = true;
    await provider.refreshWatchedHistory();
    pending.complete([_session('stale')]);
    await load;
    expect(provider.sessionEntries.map((e) => e.session.id), ['new']);
    provider.dispose();
  });

  test(
    'calendar refresh for the same month ignores an older completion',
    () async {
      final pending = Completer<List<Movie>>();
      var calls = 0;
      final store = _Store()
        ..calendar = (_) => ++calls == 1
            ? pending.future
            : Future.value([
                Movie(
                  id: 'new',
                  title: 'new',
                  watchedAt: DateTime(2026, 11, 2),
                ),
              ]);
      final provider = MovieProvider(storage: store);
      final old = provider.refreshHistoryCalendarMonth(forceRefresh: true);
      await provider.refreshHistoryCalendarMonth(forceRefresh: true);
      pending.complete([
        Movie(id: 'stale', title: 'stale', watchedAt: DateTime(2026, 11, 3)),
      ]);
      await old;
      expect(
        provider.visibleHistoryMonthData!.summariesByDay.containsKey(3),
        isFalse,
      );
      expect(provider.isHistoryCalendarLoading, isFalse);
      provider.dispose();
    },
  );

  test('clearing draw history invalidates an older pending page', () async {
    final pending = Completer<List<DrawRecord>>();
    final store = _Store()
      ..draws = (_, offset) async => offset > 0
          ? pending.future
          : List.generate(20, (i) => _draw('old$i'));
    final provider = DrawHistoryProvider(storage: store);
    await provider.refresh();
    final load = provider.loadMore();
    await provider.clearAll();
    pending.complete([_draw('stale')]);
    await load;
    expect(provider.records, isEmpty);
    expect(provider.isLoadingMore, isFalse);
    provider.dispose();
  });

  test(
    'batch import separates failures from duplicates and permits retry',
    () async {
      var failing = true;
      final store = _Store()
        ..save = (movie) async {
          if (movie.id == 'duplicate') throw DuplicateMovieException(movie);
          if (failing && movie.id == 'failed') {
            throw StateError('disk unavailable');
          }
          return movie;
        };
      final provider = MovieProvider(storage: store);
      final result = await provider.addScrapedMovies([
        Movie(id: 'ok', title: 'ok'),
        Movie(id: 'duplicate', title: 'duplicate'),
        Movie(id: 'failed', title: 'failed'),
      ]);
      expect(result.added, 1);
      expect(result.skipped, 1);
      expect(result.failed.single.id, 'failed');
      failing = false;
      final retry = await provider.addScrapedMovies(result.failed);
      expect(retry.added, 1);
      expect(retry.failed, isEmpty);
      provider.dispose();
    },
  );

  test('provider completion after dispose sends no notifications', () async {
    final pending = Completer<List<Movie>>();
    final provider = MovieProvider(
      storage: _Store()..movies = (_, _, _, _) => pending.future,
    );
    var notifications = 0;
    provider.addListener(() => notifications++);
    final load = provider.refreshLibrary();
    provider.dispose();
    pending.complete(_movies('late', 1));
    await load;
    expect(notifications, 0);
    expect(provider.peekMovieById('late0'), isNull);
  });
}
