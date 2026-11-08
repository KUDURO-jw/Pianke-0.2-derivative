import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/pages/movies/movie_detail_page.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/services/local_data_guard.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/widgets/movie/quick_viewing_entry.dart';

class _Movies extends MovieProvider {
  Movie movie = Movie(id: 'local', title: '离线影片', userReview: '原短评');
  bool failSave = false;
  String? failure;
  ViewingSession? recorded;
  @override
  String? get error => failure;
  @override
  Movie? peekMovieById(String id) => movie;
  @override
  Future<Movie?> getMovieById(String id, {bool forceRefresh = false}) async =>
      movie;
  @override
  Future<List<ViewingSession>> sessionsForMovie(String id) async => [];
  @override
  Future<void> updateMovie(Movie value) async {
    failure = failSave ? '模拟磁盘错误' : null;
    if (!failSave) movie = value;
  }

  @override
  Future<ViewingSession?> addViewingSession(ViewingSession value) async {
    recorded = value;
    return value;
  }
}

class _Collections extends CollectionProvider {
  @override
  Future<void> ensureLoaded() async {}
  @override
  Future<List<MovieTag>> tagsForMovie(String id) async => [];
}

class _Store implements StorageService {
  final Movie movie;
  final List<String> queries = [];
  _Store(this.movie);
  @override
  Future<List<Movie>> queryMovies({
    required int limit,
    required int offset,
    String searchQuery = '',
    bool watchedOnly = false,
    bool unwatchedOnly = false,
  }) async {
    queries.add(searchQuery);
    return offset == 0 ? [movie] : [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(_Movies movies, Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<MovieProvider>.value(value: movies),
    ChangeNotifierProvider<CollectionProvider>(create: (_) => _Collections()),
  ],
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

void main() {
  for (final action in ['继续编辑', '放弃修改', '保存并离开']) {
    testWidgets('detail return handles $action and preserves local edits', (
      tester,
    ) async {
      final movies = _Movies();
      await tester.pumpWidget(
        _wrap(
          movies,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const MovieDetailPage(movieId: 'local'),
                  ),
                ),
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), '新的短评');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(LocalDataGuard.isEditing, isTrue);
      expect(find.text('保存修改'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('保存修改后离开？'), findsOneWidget);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      if (action == '继续编辑') {
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '新的短评',
        );
        expect(LocalDataGuard.isEditing, isTrue);
      } else {
        expect(find.text('打开详情'), findsOneWidget);
        expect(LocalDataGuard.isEditing, isFalse);
        expect(movies.movie.userReview, action == '保存并离开' ? '新的短评' : '原短评');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(LocalDataGuard.isEditing, isFalse);
    });
  }

  testWidgets('failed detail save leaves draft on screen and retry succeeds', (
    tester,
  ) async {
    final movies = _Movies()..failSave = true;
    await tester.pumpWidget(
      _wrap(movies, const MovieDetailPage(movieId: 'local')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(TextField),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), '保存失败也保留');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(find.text('保存修改'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '保存失败也保留',
    );
    expect(movies.movie.userReview, '原短评');
    movies.failSave = false;
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    expect(movies.movie.userReview, '保存失败也保留');
    expect(LocalDataGuard.isEditing, isFalse);
  });

  testWidgets(
    'quick entry searches only local movies and keeps the selected date',
    (tester) async {
      final movies = _Movies();
      final store = _Store(movies.movie);
      final date = DateTime(2024, 2, 29);
      await tester.pumpWidget(
        _wrap(
          movies,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showQuickViewingEntry(context, date: date, storage: store),
                child: const Text('补记'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('补记'));
      await tester.pumpAndSettle();
      expect(LocalDataGuard.isEditing, isTrue);
      await tester.enterText(find.byType(TextField), '离线');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(store.queries, ['', '离线']);
      await tester.tap(find.text('离线影片'));
      await tester.pumpAndSettle();
      expect(find.text('2024 年 2 月 29 日'), findsOneWidget);
      await tester.tap(find.text('保存记录'));
      await tester.pumpAndSettle();
      expect(movies.recorded?.movieId, 'local');
      expect(movies.recorded?.watchedAt, date);
      expect(LocalDataGuard.isEditing, isFalse);
    },
  );
}
