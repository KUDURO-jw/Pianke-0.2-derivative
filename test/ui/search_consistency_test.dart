import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/pages/movies/add_movie_page.dart';
import 'package:random_movie/providers/movie_provider.dart';
import 'package:random_movie/services/local_data_guard.dart';

class _Movies extends MovieProvider {
  final pending = <String, Completer<List<Movie>>>{};
  @override
  Future<List<Movie>> searchDoubanMovies(String query, {int start = 0}) =>
      (pending[query] = Completer<List<Movie>>()).future;
  @override
  Future<List<Movie>> getMoviesByIds(Iterable<String> ids) async => [];
}

Widget _wrap(_Movies movies) => ChangeNotifierProvider<MovieProvider>.value(
  value: movies,
  child: MaterialApp(theme: AppTheme.lightTheme, home: const AddMoviePage()),
);

void main() {
  testWidgets(
    'clear search suppresses the previous response and releases edit guard',
    (tester) async {
      final movies = _Movies();
      await tester.pumpWidget(_wrap(movies));
      expect(LocalDataGuard.isEditing, isTrue);
      await tester.enterText(find.byType(TextField).first, '旧片名');
      await tester.tap(find.widgetWithText(FilledButton, '搜索'));
      await tester.pump();
      expect(find.text('搜索中…'), findsOneWidget);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pump();
      movies.pending['旧片名']!.complete([Movie(id: 'stale', title: '不应出现')]);
      await tester.pumpAndSettle();
      expect(find.text('不应出现'), findsNothing);
      expect(find.text('搜索豆瓣影片'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(LocalDataGuard.isEditing, isFalse);
      expect(tester.takeException(), isNull);
      movies.dispose();
    },
  );

  testWidgets(
    'new submitted search wins when responses arrive in reverse order',
    (tester) async {
      final movies = _Movies();
      await tester.pumpWidget(_wrap(movies));
      await tester.enterText(find.byType(TextField).first, '旧');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '新');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      movies.pending['新']!.complete([Movie(id: 'new', title: '正确的新结果')]);
      await tester.pumpAndSettle();
      movies.pending['旧']!.complete([Movie(id: 'old', title: '过期的旧结果')]);
      await tester.pumpAndSettle();
      expect(find.text('正确的新结果'), findsOneWidget);
      expect(find.text('过期的旧结果'), findsNothing);
      expect(
        tester.getSize(find.byTooltip('加入片库')).shortestSide,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      movies.dispose();
    },
  );
}
