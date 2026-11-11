// 回归：片库必须能渲染 + 补位动画控制器行为。
//
// 最重要的一条在最前面：0.2.34 用 SliverAnimatedGrid 导致片库整页空白
// （initialItemCount 只在首帧生效，而片库数据是异步加载的）。
// 这个测试守住「有数据就必须有卡片」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/movie/reflow_slide.dart';

void main() {
  group('片库必须能渲染（严重回归守卫）', () {
    testWidgets('异步数据到位后网格要显示卡片', (tester) async {
      var data = <String>[];

      Widget build() => MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 300,
                ),
                itemCount: data.length,
                itemBuilder: (c, i) =>
                    Card(key: ValueKey(data[i]), child: Text(data[i])),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(build());
      await tester.pump();
      expect(find.byType(Card), findsNothing, reason: '首帧数据为空');

      data = ['a', 'b', 'c'];
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      expect(
        find.byType(Card),
        findsNWidgets(3),
        reason: '数据到位后必须渲染卡片。这条若失败等同于「片库白屏」。',
      );
    });
  });

  group('ReflowController', () {
    testWidgets('捕获前后位置，给移位的条目注入偏移', (tester) async {
      final controller = ReflowController();
      addTearDown(controller.dispose);
      final keys = <String, GlobalKey>{};

      // 4 张卡片，3 列 → d 在第 1 行。
      Widget build(List<String> ids) => MaterialApp(
        home: Scaffold(
          body: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 0,
              crossAxisSpacing: 0,
            ),
            itemCount: ids.length,
            itemBuilder: (c, i) {
              final key = keys.putIfAbsent(ids[i], GlobalKey.new);
              return KeyedSubtree(
                key: key,
                child: SizedBox(height: 200, child: Text(ids[i])),
              );
            },
          ),
        ),
      );

      await tester.pumpWidget(build(['a', 'b', 'c', 'd']));
      await tester.pumpAndSettle();

      // 删除前记录位置。
      controller.captureBefore(keys);

      // 删掉前 3 项：d 从第 1 行移到第 0 行。
      await tester.pumpWidget(build(['d']));
      await tester.pump();

      // 帧后启动补位动画。
      controller.animateAfter(
        keys,
        vsync: tester,
        enabled: true,
      );

      // 启动瞬间应有非零偏移（把 d 补回旧位置）。
      final startOffset = controller.offsetOf('d');
      expect(
        startOffset.dy.abs(),
        greaterThan(1),
        reason: '刚启动时应有纵向偏移（补回旧位置），'
            '实际 offset=$startOffset',
      );

      // 动画结束后偏移应归零。
      await tester.pumpAndSettle();
      expect(
        controller.offsetOf('d'),
        Offset.zero,
        reason: '动画结束偏移应归零',
      );
    });

    testWidgets('关闭动画时不注入偏移', (tester) async {
      final controller = ReflowController();
      addTearDown(controller.dispose);
      final keys = <String, GlobalKey>{};

      Widget build(List<String> ids) => MaterialApp(
        home: Scaffold(
          body: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
            ),
            itemCount: ids.length,
            itemBuilder: (c, i) {
              final key = keys.putIfAbsent(ids[i], GlobalKey.new);
              return KeyedSubtree(
                key: key,
                child: SizedBox(height: 200, child: Text(ids[i])),
              );
            },
          ),
        ),
      );

      await tester.pumpWidget(build(['a', 'b', 'c', 'd']));
      await tester.pumpAndSettle();
      controller.captureBefore(keys);

      await tester.pumpWidget(build(['d']));
      await tester.pump();
      controller.animateAfter(keys, vsync: tester, enabled: false);

      expect(
        controller.offsetOf('d'),
        Offset.zero,
        reason: '关闭动画时不应注入偏移',
      );
    });

    testWidgets('新出现的条目不做补位动画', (tester) async {
      final controller = ReflowController();
      addTearDown(controller.dispose);
      final keys = <String, GlobalKey>{};

      Widget build(List<String> ids) => MaterialApp(
        home: Scaffold(
          body: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
            ),
            itemCount: ids.length,
            itemBuilder: (c, i) {
              final key = keys.putIfAbsent(ids[i], GlobalKey.new);
              return KeyedSubtree(
                key: key,
                child: SizedBox(height: 200, child: Text(ids[i])),
              );
            },
          ),
        ),
      );

      await tester.pumpWidget(build(['a']));
      await tester.pumpAndSettle();
      controller.captureBefore(keys);

      // b 是新出现的，捕获前不存在于 keys。
      await tester.pumpWidget(build(['a', 'b']));
      await tester.pump();
      controller.animateAfter(keys, vsync: tester, enabled: true);

      // b 没有「旧位置」，不该有偏移。
      expect(
        controller.offsetOf('b'),
        Offset.zero,
        reason: '新条目没有旧位置，不应产生补位偏移',
      );
    });
  });

  test('Motion.normal 用作补位时长', () {
    expect(Motion.normal.inMilliseconds, inInclusiveRange(150, 300));
  });
}
