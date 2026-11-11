// 回归：骨架屏在无界高度父级下不得崩溃。
//
// 背景：0.2.23 把骨架网格从 childAspectRatio 改成 mainAxisExtent 后，
// 在片库页（SliverToBoxAdapter 包裹，父级给的是 0<=h<=Infinity）
// 会抛「Unsupported operation: Infinity or NaN toInt」，
// 位置在 SliverGridRegularTileLayout.getMinChildIndexForScrollOffset。
//
// 根因：mainAxisExtent 固定时，行步长 = extent + spacing；
// 网格若去撑满无界父级，scrollOffset 变成 Infinity，
// Infinity / 有限值 仍是 Infinity，toInt() 抛异常。
// 修复：GridView 加 shrinkWrap: true，按内容高度布局。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/widgets/common/skeleton.dart';

void main() {
  group('骨架屏在无界高度下不崩溃', () {
    testWidgets('SliverToBoxAdapter 包裹（片库页真实用法）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: LibrarySkeletonGrid(count: 12),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: '无界高度下不应产生 Infinity/NaN 布局异常',
      );
    });

    testWidgets('Column + SingleChildScrollView 包裹', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: const [LibrarySkeletonGrid(count: 6)],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('直接放在 Scaffold body（有界）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LibrarySkeletonGrid(count: 12)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('大字体下同样不崩溃', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: LibrarySkeletonGrid(count: 6),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('骨架网格用固定行高且为有限正数', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LibrarySkeletonGrid(count: 3)),
        ),
      );
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;

      expect(grid.shrinkWrap, isTrue, reason: '必须 shrinkWrap，否则无界父级下崩溃');
      expect(delegate.mainAxisExtent, isNotNull);
      expect(delegate.mainAxisExtent!.isFinite, isTrue);
      expect(delegate.mainAxisExtent, greaterThan(0));
    });
  });
}
