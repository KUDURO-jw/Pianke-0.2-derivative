import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransition;
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
  int detailReads = 0;
  int sessionReads = 0;
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
  Future<Movie?> getMovieById(String id, {bool forceRefresh = false}) async {
    detailReads++;
    return loading == null ? data.first : loading!.future;
  }

  @override
  Future<List<ViewingSession>> sessionsForMovie(String id) async {
    sessionReads++;
    return List.generate(
      recordCount,
      (i) => ViewingSession(
        id: '$i',
        movieId: id,
        watchedAt: DateTime(2026, 1, i + 1),
        note: '多次观影的记录 $i',
      ),
    );
  }
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
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'library dock double tap scrolls to top (reduced=$reducedMotion)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        appRouter.go('/movies');
        await tester.pumpWidget(
          _wrap(
            _Movies(List.generate(150, (i) => Movie(id: '$i', title: '影片 $i'))),
            MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: appRouter,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reducedMotion),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final libraryState = tester.state(find.byType(MoviesPage));
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(MoviesPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        scrollable.position.jumpTo(2000);
        await tester.pumpAndSettle();
        final previousOffset = scrollable.position.pixels;
        final dockLibrary = find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.text('片库'),
        );
        await tester.tap(dockLibrary);
        await tester.pump(const Duration(milliseconds: 80));
        expect(scrollable.position.pixels, previousOffset);
        await tester.tap(dockLibrary);
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, 0);
        expect(tester.state(find.byType(MoviesPage)), same(libraryState));
        expect(find.text('我的合集'), findsOneWidget);
        // Repeat at the top, then drag rather than tap: no extra route or crash.
        await tester.tap(dockLibrary);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tap(dockLibrary);
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'card pressing reuses the poster subtree and cancelling restores scale',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 140,
              height: 260,
              child: MovieCard(
                movie: Movie(id: 'press', title: '按压'),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      final poster = tester.widget<MoviePoster>(find.byType(MoviePoster));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MovieCard)),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.widget<MoviePoster>(find.byType(MoviePoster)),
        same(poster),
      );
      // 按压反馈现在由 SpringPressScale 提供（内部是 Transform.scale + 弹簧）。
      // 注意不能用 Transform 的 matrix.getMaxScaleOnAxis() 判断缩放：
      // 那个方法取的是整列范数，z 轴恒为 1.0，xy 缩小也只会返回 1.0。
      // 直接看渲染出来的矩形宽度最可靠。
      double cardScale() {
        final width = tester
            .getRect(
              find
                  .descendant(
                    of: find.byType(MovieCard),
                    matching: find.byType(Column),
                  )
                  .first,
            )
            .width;
        return width / 140; // 外层 SizedBox 固定 140 宽
      }

      expect(cardScale(), lessThan(1));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(cardScale(), closeTo(1, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail header reuses its static background while scrolling', (
    tester,
  ) async {
    final movie = Movie(id: 'header', title: '滚动详情', summary: '简介' * 300);
    await tester.pumpWidget(
      _wrap(
        _Movies([movie]),
        MaterialApp(
          home: MovieDetailPage(movieId: movie.id, initialMovie: movie),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final background = tester
        .widget<FlexibleSpaceBar>(find.byType(FlexibleSpaceBar))
        .background;
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    for (final offset in [20.0, 40.0, 80.0, 120.0]) {
      scrollable.position.jumpTo(offset);
      await tester.pump();
      expect(
        tester
            .widget<FlexibleSpaceBar>(find.byType(FlexibleSpaceBar))
            .background,
        same(background),
      );
    }
    expect(tester.takeException(), isNull);
  });
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
      final movies = _Movies([movie], recordCount: 20);
      appRouter.go('/movies');
      await tester.pumpWidget(
        _wrap(
          movies,
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
      expect(movies.detailReads, 0);
      expect(movies.sessionReads, 0);
      // 详情页转场是本项目自实现的 SlideTransition（右侧滑入），
      // 刻意不用 Cupertino 内置的 CupertinoPageTransition ——
      // 后者会带一层整页边缘阴影，进出详情页时每帧重绘开销明显更高。
      // 因此这里断言实际实现，而不是断言某个框架内置类型的名字。
      expect(find.byType(CupertinoPageTransition), findsNothing);
      expect(find.byType(SlideTransition), findsWidgets);
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
      expect(movies.detailReads, 1);
      expect(movies.sessionReads, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MovieDetailPage), findsNothing);
      expect(tester.state(find.byType(MoviesPage)), same(sourceState));
      await tester.tap(find.text(movie.title));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      appRouter.pop();
      await tester.pumpAndSettle();
      // Fast return must not begin the deferred local reads after disposal.
      expect(movies.detailReads, 1);
      expect(movies.sessionReads, 1);
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
