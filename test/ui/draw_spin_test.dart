// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/pages/draw/draw_state.dart';

void main() {
  group('T14 转动动画：终点与结果一致（真实曲线驱动）', () {
    test('用 Motion.spinCurve 采样，最后一定停在 resultIndex', () {
      const curve = Motion.spinCurve;
      for (final ringLength in [1, 2, 5, 24]) {
        for (final resultIndex in [
          for (var i = 0; i < ringLength; i++) i,
        ]) {
          final timeline = DrawTimeline(
            ringLength: ringLength,
            resultIndex: resultIndex,
          );

          // 模拟控制器从 0 走到 1 的采样过程。
          int? last;
          for (var i = 0; i <= 100; i++) {
            final index = timeline.indexAt(curve.transform(i / 100));
            expect(index, inInclusiveRange(0, ringLength - 1));
            last = index;
          }
          expect(
            last,
            resultIndex,
            reason: 'ring=$ringLength result=$resultIndex 的终点不对',
          );
        }
      }
    });

    test('不再需要 indexOf 回找：时间表直接给出终点', () {
      final ring = List.generate(7, (i) => i);
      const resultIndex = 4;
      final timeline = DrawTimeline(
        ringLength: ring.length,
        resultIndex: resultIndex,
      );
      // 终点下标就是结果下标，无需在 ring 里搜索。
      expect(timeline.indexAt(1), resultIndex);
    });

    test('转动总步数随环变大而增加（至少两圈）', () {
      final small = DrawTimeline(ringLength: 3, resultIndex: 0);
      final large = DrawTimeline(ringLength: 30, resultIndex: 0);
      expect(large.totalSteps, greaterThan(small.totalSteps));
      expect(small.totalSteps, greaterThanOrEqualTo(2 * 3));
    });
  });

  group('T14 减少动效时直接出结果', () {
    testWidgets('MediaQuery 关闭动画时 Motion.of 返回零', (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                resolved = Motion.of(context, Motion.drawSpin);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(resolved, Duration.zero);
    });
  });
}
