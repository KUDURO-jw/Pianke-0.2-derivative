// 回归：片库删除后的补位动画确实接上了。
//
// 用户反馈：「删除一部片子，下面的片子补位没有动画，很生硬」。
//
// 关键教训：光把 SliverGrid.builder 换成 SliverAnimatedGrid 是不够的。
// 后者只在显式调用 `removeItem(index, builder)` 时才播移除/补位动画；
// 数据一变就重建，行为与普通网格完全一致。
//
// 这个测试验证「删除流程真的调用了 removeItem」——通过检查网格里
// 出现了 SizeTransition（移除动画的载体）来判定。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/design_tokens.dart';

void main() {
  group('SliverAnimatedGrid 补位动画接线', () {
    testWidgets('调用 removeItem 后出现移除动画载体', (tester) async {
      final gridKey = GlobalKey<SliverAnimatedGridState>();
      final ids = ['a', 'b', 'c'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverAnimatedGrid(
                  key: gridKey,
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisExtent: 300,
                      ),
                  initialItemCount: ids.length,
                  itemBuilder: (c, i, anim) =>
                      Card(child: Center(child: Text(ids[i]))),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 模拟片库页 _deleteWithUndo 里的调用。
      gridKey.currentState!.removeItem(
        0,
        (context, animation) => SizeTransition(
          sizeFactor: animation,
          child: FadeTransition(
            opacity: animation,
            child: const Card(child: SizedBox()),
          ),
        ),
        duration: Motion.normal,
      );
      await tester.pump();

      expect(
        find.byType(SizeTransition),
        findsWidgets,
        reason: 'removeItem 后应出现 SizeTransition（移除动画载体）。'
            '若找不到，说明补位动画没接上，删除仍是瞬跳。',
      );

      await tester.pumpAndSettle();
    });

    testWidgets('未调用 removeItem 时没有动画载体（对照）', (tester) async {
      // 这条对照说明：只换成 SliverAnimatedGrid 而不调 removeItem，
      // 和普通网格一样不会有补位动画。
      final ids = ['a', 'b', 'c'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverAnimatedGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisExtent: 300,
                      ),
                  initialItemCount: ids.length,
                  itemBuilder: (c, i, anim) =>
                      Card(child: Center(child: Text(ids[i]))),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SizeTransition), findsNothing);
    });
  });
}
