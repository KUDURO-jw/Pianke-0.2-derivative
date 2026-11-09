// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/design_tokens.dart';

/// 把 [child] 包在一个能指定「减少动态效果」的 MediaQuery 里。
Widget _host({required bool disableAnimations, required Widget child}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: child,
    ),
  );
}

void main() {
  group('T9 Motion 令牌', () {
    testWidgets('正常情况返回令牌原值', (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        _host(
          disableAnimations: false,
          child: Builder(
            builder: (context) {
              resolved = Motion.of(context, Motion.normal);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolved, Motion.normal);
      expect(resolved, isNot(Duration.zero));
    });

    testWidgets('开启「移除动画」后返回 Duration.zero', (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        _host(
          disableAnimations: true,
          child: Builder(
            builder: (context) {
              resolved = Motion.of(context, Motion.normal);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolved, Duration.zero);
    });

    testWidgets('enabled(context) 与 of() 结论一致', (tester) async {
      for (final disable in [false, true]) {
        late bool enabled;
        late Duration duration;
        await tester.pumpWidget(
          _host(
            disableAnimations: disable,
            child: Builder(
              builder: (context) {
                enabled = Motion.enabled(context);
                duration = Motion.of(context, Motion.slow);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(enabled, !disable);
        expect(duration == Duration.zero, disable);
      }
    });

    test('令牌取值符合目标手感（进入略慢于返回）', () {
      expect(Motion.page.inMilliseconds, greaterThan(Motion.pageBack.inMilliseconds));
      expect(Motion.fast.inMilliseconds, lessThan(Motion.normal.inMilliseconds));
      expect(Motion.normal.inMilliseconds, lessThan(Motion.slow.inMilliseconds));
    });

    test('所有令牌都是正的有限时长', () {
      const durations = <String, Duration>{
        'fast': Motion.fast,
        'normal': Motion.normal,
        'slow': Motion.slow,
        'page': Motion.page,
        'pageBack': Motion.pageBack,
        'panel': Motion.panel,
        'settle': Motion.settle,
        'shimmer': Motion.shimmer,
        'breath': Motion.breath,
        'reveal': Motion.reveal,
        'placeholderFade': Motion.placeholderFade,
        'scroll': Motion.scroll,
        'shuffleTick': Motion.shuffleTick,
        'resultHold': Motion.resultHold,
        'debounce': Motion.debounce,
      };
      durations.forEach((name, duration) {
        expect(
          duration.inMilliseconds,
          greaterThan(0),
          reason: '令牌 $name 必须是正时长',
        );
        expect(
          duration.inMilliseconds,
          lessThan(5000),
          reason: '令牌 $name 过长，用户会觉得卡住',
        );
      });
    });
  });

  group('T9 动画组件确实遵守减少动效', () {
    testWidgets('AnimatedContainer 在移除动画时立即到位', (tester) async {
      // 用 Builder 拿到真正带「减少动效」的 MediaQuery context。
      Widget build(bool disable, bool expanded) => _host(
        disableAnimations: disable,
        child: Center(
          child: Builder(
            builder: (context) => AnimatedContainer(
              duration: Motion.of(context, Motion.normal),
              width: expanded ? 200 : 100,
              height: 40,
              color: Colors.blue,
            ),
          ),
        ),
      );

      await tester.pumpWidget(build(true, false));
      await tester.pumpWidget(build(true, true));
      // 移除动画时，下一帧就应该是终态，不需要等 220ms。
      await tester.pump();
      final box = tester.getSize(find.byType(AnimatedContainer));
      expect(box.width, 200);
    });

    testWidgets('正常情况同样经过动画时长后到位', (tester) async {
      await tester.pumpWidget(
        _host(
          disableAnimations: false,
          child: const Center(
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      );
      await tester.pumpWidget(
        _host(
          disableAnimations: false,
          child: Center(
            child: AnimatedContainer(
              duration: Motion.normal,
              width: 200,
              height: 40,
              color: Colors.blue,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(AnimatedContainer)).width,
        200,
      );
    });
  });
}
