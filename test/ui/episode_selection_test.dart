import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/pages/movies/movie_detail_page.dart';
import 'package:random_movie/pages/movies/movies_page.dart';
import 'package:random_movie/widgets/common/app_components.dart';

class EpisodeMovies extends MovieProvider {
  final saved = Completer<void>();
  Movie movie = Movie(
    id: 'series',
    title: '测试剧集',
    summary: List.filled(300, '剧情简介').join(),
    subjectType: MovieSubjectType.tvSeries,
    episodes: List.generate(
      3,
      (i) => MovieEpisode(number: i + 1, label: '第${i + 1}集', doubanUrl: ''),
    ),
  );
  @override
  Movie? peekMovieById(String id) => movie;
  @override
  Future<Movie?> getMovieById(String id, {bool forceRefresh = false}) async =>
      movie;
  @override
  Future<List<ViewingSession>> sessionsForMovie(String id) async => [];
  @override
  Future<void> updateMovie(Movie value) async {
    await saved.future;
    movie = value;
  }
}

class EpisodeCollections extends CollectionProvider {
  @override
  Future<void> ensureLoaded() async {}
  @override
  Future<List<MovieTag>> tagsForMovie(String id) async => [];
}

class LibraryMovies extends MovieProvider {
  LibraryFilter filter = LibraryFilter.all;
  @override
  List<Movie> get movies =>
      List.generate(60, (i) => Movie(id: '$i', title: '影片$i'));
  @override
  bool get hasLoadedLibrary => true;
  @override
  bool get hasMoreLibrary => false;
  @override
  LibraryFilter get libraryFilter => filter;
  @override
  Future<void> setLibraryFilter(LibraryFilter value) async {
    filter = value;
    notifyListeners();
  }
}

void main() {
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      for (final family in ['Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(
              font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            ))
            .load();
      }
    }
    final icons = File(
      'C:/Project/pk/toolchain/flutter-3.44.0/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            icons.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          ))
          .load();
    }
  });
  for (final dark in [false, true]) {
    testWidgets(
      'detail tab surface stays below artwork (${dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final movies = EpisodeMovies();
        movies.movie = movies.movie.copyWith(
          summary: '故事从一场超市纵火案展开，一段关于人与社会的故事。',
        );
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<MovieProvider>.value(value: movies),
              ChangeNotifierProvider<CollectionProvider>(
                create: (_) => EpisodeCollections(),
              ),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              home: RepaintBoundary(
                key: captureKey,
                child: const MovieDetailPage(movieId: 'series'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 详情页的页签是自实现的 SegmentedSwitch（胶囊分段器），
        // 不是 Material 自带的下划线 TabBar —— 后者在 0.2.11 已被移除，
        // 目的全应用统一成同一套分段器样式。这里断言替换后的实际实现。
        expect(find.byType(TabBar), findsNothing);
        final segmented = tester.widget<SegmentedSwitch>(
          find.byType(SegmentedSwitch),
        );
        expect(segmented.labels, const ['记录', '资料']);
        expect(segmented.selectedIndex, 0);

        final surface = find.byKey(const ValueKey('detail-tab-surface'));
        expect(surface, findsOneWidget);
        expect(
          tester.getRect(surface).top,
          greaterThanOrEqualTo(
            tester.getRect(find.byType(FlexibleSpaceBar)).bottom,
          ),
        );
        expect(find.text('记录').hitTestable(), findsOneWidget);
        expect(find.text('资料').hitTestable(), findsOneWidget);
        final captureDirectory = Platform.environment['PIANKE_CAPTURE_DIR'];
        if (captureDirectory != null) {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(captureDirectory).create(recursive: true);
            await File(
              '$captureDirectory/detail-${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.drag(
          find.byKey(const PageStorageKey('series-records')),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(surface).dy, closeTo(kToolbarHeight, 1));
        expect(find.text('资料').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'detail tabs support swipes, taps and independent scroll positions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final movies = EpisodeMovies();
      movies.movie = movies.movie.copyWith(
        director: '资料导演',
        year: '2026',
        summary: '一段简短的剧情简介。',
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MovieProvider>.value(value: movies),
            ChangeNotifierProvider<CollectionProvider>(
              create: (_) => EpisodeCollections(),
            ),
          ],
          child: const MaterialApp(home: MovieDetailPage(movieId: 'series')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('简介').hitTestable(), findsOneWidget);
      expect(find.text('第1集').hitTestable(), findsOneWidget);
      expect(find.text('影片信息'), findsNothing);

      // 详情页用 NestedScrollView：头图折叠与正文滚动由**外层**的
      // Scrollable 统一接管，正文自己的 CustomScrollView 只承担
      // SliverOverlapInjector 之后那一小段余量。所以不能用「正文
      // offset > 0」来判断「页面能滚」，那个值会被压到很小甚至为 0，
      // 断言它等于在测实现细节而不是用户看到的行为。
      //
      // 改成断言用户真正感知到的东西：拖动后正文内容在屏幕上向上位移，
      // 且切到「资料」再切回来时，滚动位置被保留。
      final records = find.byKey(const PageStorageKey('series-records'));
      expect(records, findsOneWidget);

      final summary = find.textContaining('剧情简介').first;
      final topBefore = tester.getTopLeft(summary).dy;

      await tester.drag(records, const Offset(0, -280), warnIfMissed: false);
      await tester.pumpAndSettle();

      final topAfter = tester.getTopLeft(summary).dy;
      expect(
        topAfter,
        lessThan(topBefore),
        reason: '向上拖动后正文应当整体上移',
      );

      final offset = topAfter;

      await tester.drag(find.byType(TabBarView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('资料导演').hitTestable(), findsOneWidget);
      expect(find.text('简介').hitTestable(), findsNothing);
      await tester.drag(find.byType(TabBarView), const Offset(350, 0));
      await tester.pumpAndSettle();

      // 切回「记录」后滚动位置应被保留：正文仍在拖动后的位置附近。
      expect(
        tester.getTopLeft(find.textContaining('剧情简介').first).dy,
        closeTo(offset, 1),
        reason: '两个页签各自保留滚动位置',
      );
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      expect(find.text('资料导演').hitTestable(), findsOneWidget);
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      expect(find.text('资料导演').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('summary expansion remains offline across page visits', (
    tester,
  ) async {
    var requests = 0;
    await HttpOverrides.runZoned(
      () async {
        for (var visit = 0; visit < 2; visit++) {
          final movies = EpisodeMovies();
          movies.movie = movies.movie.copyWith(
            summary: List.filled(60, '简介').join(),
            doubanUrl: 'https://movie.douban.com/subject/123/',
          );
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<MovieProvider>.value(value: movies),
                ChangeNotifierProvider<CollectionProvider>(
                  create: (_) => EpisodeCollections(),
                ),
              ],
              child: const MaterialApp(
                home: MovieDetailPage(movieId: 'series'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (var toggle = 0; toggle < 2; toggle++) {
            await tester.scrollUntilVisible(
              find.text('展开'),
              200,
              scrollable: find
                  .descendant(
                    of: find.byKey(const PageStorageKey('series-records')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            await Scrollable.ensureVisible(
              tester.element(find.text('展开')),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('展开'));
            await tester.pumpAndSettle();
            await Scrollable.ensureVisible(
              tester.element(find.text('收起')),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('收起'));
            await tester.pumpAndSettle();
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      },
      createHttpClient: (_) {
        requests++;
        throw StateError('No HTTP expected while expanding saved summary');
      },
    );
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pinned library filters stay below status bar and accept taps', (
    tester,
  ) async {
    final movies = LibraryMovies();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MovieProvider>.value(value: movies),
          ChangeNotifierProvider<CollectionProvider>(
            create: (_) => EpisodeCollections(),
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 48)),
            child: const MoviesPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<PageHeader>(find.byType(PageHeader)).trailing, isNull);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('全部')).dy, greaterThanOrEqualTo(48));
    await tester.tap(find.text('已看'));
    await tester.pumpAndSettle();
    expect(movies.filter, LibraryFilter.watched);
    await tester.tap(find.text('未看').first);
    await tester.pumpAndSettle();
    expect(movies.filter, LibraryFilter.unwatched);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'episode controls keep their enabled appearance throughout save',
    (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final movies = EpisodeMovies();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MovieProvider>.value(value: movies),
            ChangeNotifierProvider<CollectionProvider>(
              create: (_) => EpisodeCollections(),
            ),
          ],
          child: const MaterialApp(home: MovieDetailPage(movieId: 'series')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('第1集'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('series-records')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('第1集')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('第1集'));
      await tester.pump();
      final chips = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .toList();
      expect(chips, hasLength(3));
      expect(chips.every((chip) => chip.onSelected != null), isTrue);
      expect(chips.first.selected, isTrue);
      await tester.tap(find.text('第2集'));
      await tester.pump();
      expect(
        tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .elementAt(1)
            .selected,
        isFalse,
      );
      movies.saved.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('第2集'));
      await tester.pumpAndSettle();
      expect(movies.movie.episodes.take(2).every((e) => e.watched), isTrue);
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      final context = tester.element(find.byType(MovieDetailPage));
      expect(appBar.backgroundColor, Theme.of(context).colorScheme.surface);
      expect(appBar.title, isA<Text>());
      expect(tester.takeException(), isNull);
    },
  );
}
