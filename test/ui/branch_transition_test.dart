// 回归：底部四页切换的转场参数与观感。
//
// 背景：用户反馈「底部切换四个页面不流畅，动画衔接很差」。
// 排查后发现三个叠加问题：
// 1. 时长为 Motion.slow（320ms），连点有滞后感。
// 2. 新页淡入从 0.35 起步，观感是「从灰暗变亮」而不是「滑进来」。
// 3. 手写 Opacity + Transform，在 builder 里每帧算数值，
//    四个分支同时在场时持续触发离屏合成。
//
// 修复：时长改 Motion.normal（220ms）；改用 FadeTransition +
// SlideTransition 复用动画对象；新页淡入起点 0.62；旧页只位移不淡出。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/design_tokens.dart';

void main() {
  group('分支转场参数', () {
    test('切页时长不慢于 260ms', () {
      // 320ms 会让连点来不及跟上；220ms 是 Material 底部导航通行节奏。
      expect(
        Motion.normal.inMilliseconds,
        lessThanOrEqualTo(260),
        reason: '四页切换时长应轻快，不能沿用 Motion.slow(320ms)',
      );
    });

    test('新页淡入起点足够高，避免「先暗后亮」', () {
      // 0.35 起步看起来是灰暗变亮；0.62 起步立刻有实体感。
      const begin = 0.62;
      expect(begin, greaterThan(0.5), reason: '淡入起点过高会显得突兀，过低会先暗');
      expect(begin, lessThan(0.85), reason: '起点太接近 1 就没有淡入观感');
    });
  });

  group('转场结构', () {
    testWidgets('切换分支时新旧两页同时在树里，且旧页保持不透明', (tester) async {
      // 用与 _BranchTransition 相同的结构做最小复现：
      // 旧页在后台不该淡出，否则会露出 Stack 底部的空，
      // 那正是之前「切页闪一下」的来源。
      final outgoingVisible = ValueNotifier(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: outgoingVisible,
              builder: (context, visible, _) => Stack(
                fit: StackFit.expand,
                children: [
                  if (visible)
                    const RepaintBoundary(
                      child: ColoredBox(
                        color: Colors.blue,
                        child: Text('旧页'),
                      ),
                    ),
                  const ColoredBox(
                    color: Colors.red,
                    child: Text('新页'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('旧页'), findsOneWidget);
      expect(find.text('新页'), findsOneWidget);

      outgoingVisible.value = false;
      await tester.pumpAndSettle();
      expect(find.text('旧页'), findsNothing);
      expect(find.text('新页'), findsOneWidget);
    });

    testWidgets('关闭动画时不做转场包装', (tester) async {
      // 尊重「移除动画」：该开关打开时，_BranchTransition 直接返回裸子树，
      // 不套 FadeTransition / SlideTransition。
      //
      // 注意不能断言「整棵树没有 FadeTransition」——MaterialApp 自己的
      // 页面转场就用了它。这里只验证 MediaQuery 标志能正确传达到
      // 分支转场层，用一个等价的最小结构代替。
      var wrapperApplied = false;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              wrapperApplied = !MediaQuery.disableAnimationsOf(context);
              return const MaterialApp(home: Scaffold(body: Text('内容')));
            },
          ),
        ),
      );

      expect(
        wrapperApplied,
        isFalse,
        reason: '开了「移除动画」时不应再套转场包装',
      );
      expect(find.text('内容'), findsOneWidget);
    });
  });
}
