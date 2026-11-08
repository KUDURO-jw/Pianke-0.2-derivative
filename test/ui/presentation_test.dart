import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/pages/movies/movie_detail_page.dart';
import 'package:random_movie/pages/movies/movies_page.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/router/app_router.dart';
import 'package:random_movie/router/movie_detail_arguments.dart';
import 'package:random_movie/widgets/movie/movie_poster.dart';
import 'package:random_movie/widgets/movie/movie_card.dart';
import 'package:random_movie/widgets/common/floating_nav_bar.dart';
import 'pages_test.dart' show providers;

class _Movies extends MovieProvider {
  final List<Movie> data;
  final Completer<Movie?>? loading;
  final int recordCount;
  _Movies(this.data, {this.loading, this.recordCount = 0});
  @override
  List<Movie> get movies => data;
  @override
  int get totalCount => data.length;
  @override
  bool get hasLoadedLibrary => true;
  @override
  bool get hasMoreLibrary => false;
  @override
  Future<void> ensureLibraryLoaded() async {}
  @override
  Future<void> ensureHistoryLoaded() async {}
  @override
  Movie? peekMovieById(String id) => null;
  @override
  Future<Movie?> getMovieById(String id, {bool forceRefresh = false}) async =>
      loading == null ? data.first : loading!.future;
  @override
  Future<List<ViewingSession>> sessionsForMovie(String id) async =>
      List.generate(
        recordCount,
        (i) => ViewingSession(
          id: '$i',
          movieId: id,
          watchedAt: DateTime(2026, 1, i + 1),
          note: '多次观影的记录 $i',
        ),
      );
}

class _Collections extends CollectionProvider {
  final bool populated;
  _Collections(this.populated);
  @override
  List<MovieCollection> get manualCollections => populated
      ? [MovieCollection(id: 'list', name: '周末清单', memberCount: 2)]
      : [];
  @override
  Future<void> ensureLoaded() async {}
  @override
  Future<List<MovieTag>> tagsForMovie(String id) async => [];
}

Widget _wrap(_Movies movies, Widget child, {bool collections = false}) =>
    providers(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MovieProvider>.value(value: movies),
          ChangeNotifierProvider<CollectionProvider>(
            create: (_) => _Collections(collections),
          ),
        ],
        child: child,
      ),
    );

void main() {
  testWidgets(
    'large library only builds visible cards and preserves pagination layout',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final movies = _Movies(
        List.generate(
          1000,
          (i) => Movie(id: '$i', title: '影片 $i', year: '2026'),
        ),
      );
      await tester.pumpWidget(
        _wrap(
          movies,
          MaterialApp(theme: AppTheme.lightTheme, home: const MoviesPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MovieCard).evaluate().length, lessThan(30));
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -1600),
        3500,
      );
      await tester.pumpAndSettle();
      expect(find.byType(MovieCard).evaluate().length, lessThan(30));
      expect(tester.getTopLeft(find.text('全部')).dy, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled animations bypass poster flights', (tester) async {
    final movie = Movie(
      id: 'reduce',
      title: '减少动画',
      poster: 'https://example.invalid/reduce.jpg',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(
            width: 100,
            height: 150,
            child: MoviePoster(url: movie.poster, heroTag: 'reduce'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact collection entry expands only for manual collections', (
    tester,
  ) async {
    final movies = _Movies([Movie(id: '1', title: '影片')]);
    await tester.pumpWidget(
      _wrap(
        movies,
        MaterialApp(theme: AppTheme.lightTheme, home: const MoviesPage()),
      ),
    );
    await tester.pumpAndSettle();
    final compact = tester.getTopLeft(find.text('全部')).dy;
    expect(find.text('我的合集'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _wrap(
        movies,
        MaterialApp(theme: AppTheme.lightTheme, home: const MoviesPage()),
        collections: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('周末清单'), findsOneWidget);
    expect(tester.getTopLeft(find.text('全部')).dy, greaterThan(compact));
    expect(tester.takeException(), isNull);
  });

  testWidgets('series progress precedes viewing history and stays separate', (
    tester,
  ) async {
    final series = Movie(
      id: 'series',
      title: '剧集',
      subjectType: MovieSubjectType.tvSeries,
      episodes: List.generate(
        12,
        (i) => MovieEpisode(number: i + 1, label: '第${i + 1}集', doubanUrl: ''),
      ),
    );
    await tester.pumpWidget(
      _wrap(
        _Movies([series]),
        MaterialApp(
          home: MovieDetailPage(movieId: series.id, initialMovie: series),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('分集'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final episodesY = tester.getTopLeft(find.text('分集')).dy;
    expect(find.text('已看 0/12'), findsOneWidget);
    // Both section widgets are materialized within the viewport/cache here.
    expect(tester.getTopLeft(find.text('观影记录')).dy, greaterThan(episodesY));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long series and many viewing records fit small screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final movie = Movie(
        id: 'long',
        title: '很长的剧集名称',
        subjectType: MovieSubjectType.tvSeries,
        episodes: List.generate(
          80,
          (i) =>
              MovieEpisode(number: i + 1, label: '第${i + 1}集', doubanUrl: ''),
        ),
      );
      await tester.pumpWidget(
        _wrap(
          _Movies([movie], recordCount: 20),
          MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: MovieDetailPage(movieId: movie.id, initialMovie: movie),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('观影记录'),
        400,
        maxScrolls: 40,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('共 20 次'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'poster Hero flies on the real nested library route and returns',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final movie = Movie(
        id: 'hero',
        title: '海报转场',
        poster: 'https://example.invalid/poster.jpg',
      );
      appRouter.go('/movies');
      await tester.pumpWidget(
        _wrap(
          _Movies([movie], recordCount: 20),
          MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: appRouter,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sourceState = tester.state(find.byType(MoviesPage));
      expect(
        find.byWidgetPredicate((w) => w is Hero && w.tag == 'library:hero'),
        findsOneWidget,
      );
      await tester.tap(find.text(movie.title));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(MovieDetailPage), findsOneWidget);
      final heroes = tester.widgetList<Hero>(
        find.byType(Hero, skipOffstage: false),
      );
      expect(heroes.where((h) => h.tag == 'library:hero').length, 2);
      expect(find.byType(FloatingNavBar).hitTestable(), findsNothing);
      // A Hero flight has replaced both endpoints with sized placeholders.
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is Hero && w.tag == 'library:hero',
          ),
          matching: find.byType(ClipRSuperellipse),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MovieDetailPage), findsNothing);
      expect(tester.state(find.byType(MoviesPage)), same(sourceState));
      await tester.tap(find.text(movie.title));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      appRouter.pop();
      await tester.pumpAndSettle();
      expect(find.byType(MovieDetailPage), findsNothing);
      expect(tester.state(find.byType(MoviesPage)), same(sourceState));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(movie.title));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(MovieDetailPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final detailHero = find.descendant(
        of: find.byType(MovieDetailPage),
        matching: find.byType(Hero),
      );
      expect(
        tester
            .widget<HeroMode>(
              find
                  .ancestor(of: detailHero, matching: find.byType(HeroMode))
                  .first,
            )
            .enabled,
        isFalse,
      );
      appRouter.pop();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(MoviesPage)), same(sourceState));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'initial poster is available while local data loads and edits survive',
    (tester) async {
      final seed = Movie(
        id: 'seed',
        title: '初始数据',
        userReview: '旧短评',
        poster: 'https://example.invalid/seed.jpg',
      );
      final load = Completer<Movie?>();
      await tester.pumpWidget(
        _wrap(
          _Movies([seed], loading: load),
          MaterialApp(
            home: MovieDetailPage(
              movieId: seed.id,
              initialMovie: seed,
              posterHeroTag: 'test:seed',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MoviePoster), findsOneWidget);
      expect(find.byType(Hero), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), '我的编辑');
      load.complete(seed.copyWith(userReview: '本地新短评'));
      await tester.pumpAndSettle();
      expect(find.text('我的编辑'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('direct detail link and missing image need no Hero arguments', (
    tester,
  ) async {
    final movie = Movie(id: 'direct', title: '直接访问');
    appRouter.go(
      '/movies/detail/direct',
      extra: MovieDetailArguments(Movie(id: 'wrong', title: '错配')),
    );
    await tester.pumpWidget(
      _wrap(_Movies([movie]), MaterialApp.router(routerConfig: appRouter)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MovieDetailPage), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Hero && w.tag is String),
      findsNothing,
    );
    expect(
      tester.widget<MovieDetailPage>(find.byType(MovieDetailPage)).initialMovie,
      isNull,
    );
    expect(tester.takeException(), isNull);
    appRouter.go('/movies');
    await tester.pumpAndSettle();
  });
}
