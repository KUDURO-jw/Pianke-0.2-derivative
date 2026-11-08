import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/pages/history/annual_review_page.dart';
import 'package:random_movie/services/storage_service.dart';

class _ReviewStore implements StorageService {
  @override
  Future<List<Movie>> getAllMoviesForBackup() async => [
    Movie(
      id: 'a',
      title: '漫长的季节',
      genre: ['悬疑', '剧情'],
      subjectType: MovieSubjectType.tvSeries,
    ),
    Movie(id: 'b', title: '机器人之梦', genre: ['动画', '剧情']),
  ];
  @override
  Future<List<ViewingSession>> getAllSessionsForBackup() async => [
    ViewingSession(
      id: '1',
      movieId: 'a',
      watchedAt: DateTime(DateTime.now().year, 1, 1),
      rating: 5,
      note: '不应出现在分享图的私密短评',
      watchedWith: '私密同伴',
    ),
    ViewingSession(
      id: '2',
      movieId: 'b',
      watchedAt: DateTime(DateTime.now().year, 1, 2),
      rating: 4,
    ),
    ViewingSession(
      id: '3',
      movieId: 'b',
      watchedAt: DateTime(2024, 2, 29),
      rating: 3,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    final chinese = File('C:/Windows/Fonts/msyh.ttc');
    if (chinese.existsSync()) {
      await (FontLoader('ReviewChinese')..addFont(
            Future.value(ByteData.sublistView(chinese.readAsBytesSync())),
          ))
          .load();
    }
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'annual review is local, renders full PNG, dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var requests = 0;
          await HttpOverrides.runZoned(
            () async {
              final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme.copyWith(
                    textTheme: theme.textTheme.apply(
                      fontFamily: 'ReviewChinese',
                    ),
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: AnnualReviewPage(storage: _ReviewStore()),
                ),
              );
              await tester.pumpAndSettle();
              expect(find.text('2 次观影 · 2 个观影日'), findsOneWidget);
              expect(find.text('不应出现在分享图的私密短评'), findsNothing);
              expect(find.text('私密同伴'), findsNothing);
              final finder = find
                  .ancestor(
                    of: find.text('我的观影回顾'),
                    matching: find.byType(RepaintBoundary),
                  )
                  .first;
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  finder,
                );
                final image = await boundary.toImage(pixelRatio: 1);
                try {
                  expect(image.height, greaterThan(400));
                  final output = Platform.environment['PIANKE_UI_OUTPUT'];
                  if (output != null) {
                    await Directory(output).create(recursive: true);
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    await File(
                      '$output/annual-${dark ? 'dark' : 'light'}-$scale.png',
                    ).writeAsBytes(bytes!.buffer.asUint8List());
                  }
                } finally {
                  image.dispose();
                }
              });
              expect(tester.takeException(), isNull);
              await tester.tap(find.byType(DropdownButtonFormField<int>));
              await tester.pumpAndSettle();
              await tester.tap(find.text('2024 年').last);
              await tester.pumpAndSettle();
              expect(find.text('1 次观影 · 1 个观影日'), findsOneWidget);
              expect(tester.takeException(), isNull);
            },
            createHttpClient: (_) {
              requests++;
              throw StateError('Annual review must stay offline');
            },
          );
          expect(requests, 0);
        },
      );
    }
  }
}
