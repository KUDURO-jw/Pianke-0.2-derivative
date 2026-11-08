import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/pages/collections/collections_page.dart';
import 'package:random_movie/pages/draw/draw_hub_page.dart';
import 'package:random_movie/pages/history/history_page.dart';
import 'package:random_movie/pages/movies/add_movie_page.dart';
import 'package:random_movie/pages/movies/movie_detail_page.dart';
import 'package:random_movie/pages/movies/movies_page.dart';
import 'package:random_movie/pages/settings/settings_page.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/router/app_router.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/widgets/common/floating_nav_bar.dart';
import 'package:random_movie/widgets/draw/draw_filter_panel.dart';
import 'package:random_movie/widgets/movie/viewing_session_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fixtures exist only in tests. Production continues to use the original services.
class _VisualBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

final fixtureMovie = Movie(
  id: 'ui-fixture',
  title: '一部测试影片',
  year: '2026',
  director: '测试导演',
  genre: ['剧情'],
  summary: '用于核对实际详情组件的排版。',
  rating: 8.2,
);

class _Movies extends MovieProvider {
  @override
  List<Movie> get movies => [fixtureMovie];
  @override
  int get totalCount => 1;
  @override
  bool get hasLoadedLibrary => true;
  @override
  bool get hasMoreLibrary => false;
  @override
  bool get hasLoadedHistory => true;
  @override
  bool get hasMoreHistory => false;
  @override
  bool get hasLoadedHistoryCalendar => true;
  @override
  HistoryMonthData? get visibleHistoryMonthData => null;
  @override
  Future<void> ensureLibraryLoaded() async {}
  @override
  Future<void> ensureHistoryLoaded() async {}
  @override
  Future<void> jumpToCurrentHistoryMonth() async {}
  @override
  Future<void> setVisibleHistoryMonth(HistoryMonthKey month) async {}
  @override
  Future<void> refreshHistoryCalendarMonth({
    HistoryMonthKey? month,
    bool forceRefresh = false,
  }) async {}
  @override
  Movie? peekMovieById(String id) => fixtureMovie;
  @override
  Future<Movie?> getMovieById(String id, {bool forceRefresh = false}) async =>
      fixtureMovie;
  @override
  Future<List<ViewingSession>> sessionsForMovie(String movieId) async => [];
}

class _Collections extends CollectionProvider {
  @override
  bool get hasLoaded => true;
  @override
  Future<void> ensureLoaded() async {}
  @override
  Future<List<MovieTag>> tagsForMovie(String movieId) async => [];
}

class _DrawHistory extends DrawHistoryProvider {
  @override
  bool get hasLoaded => true;
  @override
  bool get hasMore => false;
  @override
  Future<void> ensureLoaded() async {}
}

Widget providers(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<MovieProvider>(create: (_) => _Movies()),
    ChangeNotifierProvider<CollectionProvider>(create: (_) => _Collections()),
    ChangeNotifierProvider<DrawHistoryProvider>(create: (_) => _DrawHistory()),
    ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
  ],
  child: child,
);

ThemeData renderTheme(bool dark) {
  final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  ButtonStyle? labelFont(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStatePropertyAll(
      (style.textStyle?.resolve({}) ?? const TextStyle()).copyWith(
        fontFamily: 'UiChinese',
      ),
    ),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'UiChinese'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'UiChinese'),
    filledButtonTheme: FilledButtonThemeData(
      style: labelFont(theme.filledButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: labelFont(theme.elevatedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: labelFont(theme.textButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: labelFont(theme.outlinedButtonTheme.style),
    ),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'UiChinese',
      ),
    ),
  );
}

Future<void> capture(WidgetTester tester, Finder finder, String name) async {
  final output = Platform.environment['PIANKE_UI_OUTPUT'];
  if (output == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  _VisualBinding();
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      for (final family in ['UiChinese', 'Roboto', 'Ahem']) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
      }
    }
    final icons = File(
      '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/Project/pk/toolchain/flutter-3.44.0'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (_) async => {
            'appName': '片刻·焕新版',
            'packageName': 'app.pianke.personal',
            'version': '0.2.0',
            'buildNumber': '4',
            'buildSignature': '',
          },
        );
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final pages = <String, Widget Function()>{
    'library': () => const MoviesPage(),
    'draw': () => const DrawHubPage(),
    'history': () => const HistoryPage(),
    'settings': () => const SettingsPage(),
    'collections': () => const CollectionsPage(),
    'add': () => const AddMoviePage(),
    'detail': () => MovieDetailPage(movieId: fixtureMovie.id),
    'filter': () => const Scaffold(
      body: DrawFilterPanel(
        initialFilter: DrawFilter.none,
        facets: MovieFacets(),
      ),
    ),
  };
  for (final dark in [false, true]) {
    for (final entry in pages.entries) {
      testWidgets(
        '${entry.key} ${dark ? "dark" : "light"} renders real widgets',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = renderTheme(dark);
          await tester.pumpWidget(
            providers(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.copyWith(
                  textTheme: theme.textTheme.apply(fontFamily: 'UiChinese'),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: const ValueKey('capture'),
                  child: entry.value(),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.runAsync(
            () async => Future<void>.delayed(Duration.zero),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump();
          expect(tester.takeException(), isNull);
          final output = Platform.environment['PIANKE_UI_OUTPUT'];
          if (output != null) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1.5);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(output).create(recursive: true);
              await File(
                '$output/${entry.key}-${dark ? "dark" : "light"}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
        },
      );
    }
  }

  for (final entry in pages.entries) {
    testWidgets('${entry.key} small screen with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        providers(
          MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: entry.value(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('all branches keep state through rapid taps and detail returns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    appRouter.go('/movies');
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('dock-capture'),
        child: providers(
          MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: renderTheme(false),
            routerConfig: appRouter,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await capture(
      tester,
      find.byKey(const ValueKey('dock-capture')),
      'library-dock-light',
    );
    final libraryState = tester.state(find.byType(MoviesPage));
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.text('抽片'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MoviesPage), findsOneWidget);
    expect(find.byType(DrawHubPage), findsOneWidget);
    final incoming = find.ancestor(
      of: find.byType(DrawHubPage),
      matching: find.byType(Opacity),
    );
    expect(
      tester.widget<Opacity>(incoming.first).opacity,
      inExclusiveRange(0, 1),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MoviesPage), findsNothing);
    for (final label in ['设置', '抽片', '观影', '片库']) {
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.text(label),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(MoviesPage)), same(libraryState));
    appRouter.push('/movies/detail/${fixtureMovie.id}');
    await tester.pumpAndSettle();
    expect(find.byType(MovieDetailPage), findsOneWidget);
    expect(find.byType(FloatingNavBar).hitTestable(), findsNothing);
    appRouter.pop();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(MoviesPage)), same(libraryState));
    expect(tester.takeException(), isNull);
  });

  testWidgets('session editor preserves existing free text and fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final existing = ViewingSession(
      id: 'session',
      movieId: fixtureMovie.id,
      watchedAt: DateTime(2026, 1, 2),
      watchedWith: '和猫',
      note: '原来的短评',
      mood: WatchMood.happy,
      rating: 4,
      isRewatch: true,
    );
    ViewingSession? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('编辑'),
              onPressed: () async {
                saved = await showViewingSessionEditor(
                  context,
                  movieId: fixtureMovie.id,
                  existing: existing,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('和猫'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('原来的短评'),
      160,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('原来的短评'), findsOneWidget);
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(saved?.watchedWith, '和猫');
    expect(saved?.note, '原来的短评');
    expect(saved?.rating, 4);
    expect(saved?.isRewatch, isTrue);
  });
}
