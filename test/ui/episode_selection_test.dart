import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final records = find.byKey(const PageStorageKey('series-records'));
      await tester.drag(records, const Offset(0, -280));
      await tester.pumpAndSettle();
      final recordsScroll = tester.state<ScrollableState>(
        find.descendant(of: records, matching: find.byType(Scrollable)).first,
      );
      final offset = recordsScroll.position.pixels;
      expect(offset, greaterThan(0));
      await tester.drag(find.byType(TabBarView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('资料导演').hitTestable(), findsOneWidget);
      expect(find.text('简介').hitTestable(), findsNothing);
      await tester.drag(find.byType(TabBarView), const Offset(350, 0));
      await tester.pumpAndSettle();
      final restored = tester.state<ScrollableState>(
        find.descendant(of: records, matching: find.byType(Scrollable)).first,
      );
      expect(restored.position.pixels, closeTo(offset, 1));
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
