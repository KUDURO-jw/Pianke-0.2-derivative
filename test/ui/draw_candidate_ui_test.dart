import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/pages/draw/draw_page.dart';
import 'package:random_movie/services/storage_service.dart';

class _Store implements StorageService {
  final films = [
    Movie(id: 'a', title: '长片一', durationMinutes: 150),
    Movie(id: 'b', title: '长片二', durationMinutes: 160),
  ];
  @override
  Future<int> countMovies({
    String searchQuery = '',
    bool watchedOnly = false,
    bool unwatchedOnly = false,
  }) async => films.length;
  @override
  Future<List<Movie>> queryMovies({
    required int limit,
    required int offset,
    String searchQuery = '',
    bool watchedOnly = false,
    bool unwatchedOnly = false,
  }) async => offset == 0 ? films : [];
  @override
  Future<List<Movie>> getMoviesByIds(Iterable<String> ids) async =>
      films.where((m) => ids.contains(m.id)).toList();
  @override
  Future<List<String>> queryMovieIds({
    String searchQuery = '',
    bool watchedOnly = false,
    bool unwatchedOnly = false,
  }) async => films.map((m) => m.id).toList();
  @override
  Future<List<MovieTag>> queryAllTags() async => [];
  @override
  Future<MovieFacets> queryMovieFacets() async => const MovieFacets();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'draw shows real candidates, removes filter and fits small screens at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: DrawPage(storage: _Store()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('符合条件 2 部'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('筛选'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2 小时内'));
        await tester.tap(find.text('应用筛选'));
        await tester.pumpAndSettle();
        expect(find.text('符合条件 0 部'), findsOneWidget);
        expect(find.textContaining('取消120分钟内可选 2 部'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final chip = tester.widget<InputChip>(find.byType(InputChip));
        chip.onDeleted!();
        await tester.pumpAndSettle();
        expect(find.text('符合条件 2 部'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
