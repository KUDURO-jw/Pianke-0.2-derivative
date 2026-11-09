// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/animated_entrance.dart';

Widget _host({required Widget child, bool disableAnimations = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('T12 卡片进入动画', () {
    testWidgets('play=false 时不创建动画，直接渲染子组件', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const AnimatedCardEntrance(
            play: false,
            child: SizedBox(key: ValueKey('card'), width: 40, height: 40),
          ),
        ),
      );
      // 没有 TweenAnimationBuilder 就说明没起动画。
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(find.byKey(const ValueKey('card')), findsOneWidget);
    });

    testWidgets('减少动效时同样不创建动画', (tester) async {
      await tester.pumpWidget(
        _host(
          disableAnimations: true,
          child: const AnimatedCardEntrance(
            play: true,
            reduceMotion: true,
            child: SizedBox(key: ValueKey('card'), width: 40, height: 40),
          ),
        ),
      );
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(find.byKey(const ValueKey('card')), findsOneWidget);
    });

    testWidgets('play=true 时从低透明度渐入到完全不透明', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const AnimatedCardEntrance(
            play: true,
            child: SizedBox(key: ValueKey('card'), width: 40, height: 40),
          ),
        ),
      );

      // 起始帧：应当还没到完全不透明。
      await tester.pump();
      double opacityNow() => tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byKey(const ValueKey('card')),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;

      final start = opacityNow();
      expect(start, lessThan(1.0), reason: '应当从低透明度开始');

      // 走完动画。
      await tester.pump(Motion.normal);
      await tester.pumpAndSettle();
      expect(opacityNow(), 1.0);
    });

    testWidgets('动画时长走后处理令牌（减少动效时为零）', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const AnimatedCardEntrance(
            play: true,
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      );
      await tester.pump();
      final builder = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>),
      );
      expect(builder.duration, Motion.normal);
    });
  });

  group('T12 卡片进入动画的稳定性', () {
    testWidgets('快速连续重建不会抛异常', (tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(
          _host(
            child: AnimatedCardEntrance(
              key: ValueKey('k$i'),
              play: i.isEven,
              child: const SizedBox(width: 30, height: 30),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('子组件被移除后动画回调不会报错', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const AnimatedCardEntrance(
            play: true,
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      );
      await tester.pump();
      // 动画进行到一半就把整棵子树换掉。
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(_host(child: const SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
