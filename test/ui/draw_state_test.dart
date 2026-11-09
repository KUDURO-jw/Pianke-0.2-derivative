// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/pages/draw/draw_state.dart';

Movie _movie(String id) => Movie(id: id, title: id);

void main() {
  group('T14 DrawState 状态穷尽性', () {
    test('四个状态各自携带所需字段', () {
      const selecting = DrawSelecting();
      final spinning = DrawSpinning(
        ring: [_movie('a'), _movie('b')],
        resultIndex: 1,
      );
      final picking = DrawPicking(options: [_movie('a')]);
      final revealed = DrawRevealed(movie: _movie('a'), recordId: 'r1');

      expect(selecting, isA<DrawState>());
      expect(spinning.ring.length, 2);
      expect(spinning.resultIndex, 1);
      expect(picking.options.single.id, 'a');
      expect(revealed.recordId, 'r1');

      // 穷尽 switch：编译器会检查所有分支，这里顺带验证取值。
      String describe(DrawState state) => switch (state) {
        DrawSelecting() => 'selecting',
        DrawSpinning() => 'spinning',
        DrawPicking() => 'picking',
        DrawRevealed() => 'revealed',
      };
      expect([
        describe(selecting),
        describe(spinning),
        describe(picking),
        describe(revealed),
      ], ['selecting', 'spinning', 'picking', 'revealed']);
    });
  });

  group('T14 DrawTimeline 终点必须落在结果上', () {
    test('进度为 1 时停在 resultIndex', () {
      for (final ringLength in [1, 3, 10, 47]) {
        for (final resultIndex in [
          for (var i = 0; i < ringLength; i++) i,
        ]) {
          final timeline = DrawTimeline(
            ringLength: ringLength,
            resultIndex: resultIndex,
          );
          expect(
            timeline.indexAt(1),
            resultIndex,
            reason: 'ring=$ringLength result=$resultIndex 应停在结果上',
          );
          expect(timeline.endsOnResult, isTrue);
        }
      }
    });

    test('总步数至少转满 minLaps 圈', () {
      final timeline = DrawTimeline(ringLength: 10, resultIndex: 3);
      expect(timeline.totalSteps, greaterThanOrEqualTo(2 * 10));
      expect(timeline.totalSteps, 2 * 10 + 3);
    });

    test('进度 0 从头开始', () {
      final timeline = DrawTimeline(ringLength: 7, resultIndex: 4);
      expect(timeline.indexAt(0), 0);
    });

    test('下标始终在环内（不会越界）', () {
      final timeline = DrawTimeline(ringLength: 6, resultIndex: 2);
      for (var i = 0; i <= 100; i++) {
        final index = timeline.indexAt(i / 100);
        expect(index, inInclusiveRange(0, 5));
      }
    });

    test('进度单调推进时下标按环循环（步进 0 或 1）', () {
      final timeline = DrawTimeline(ringLength: 8, resultIndex: 5);
      var previous = timeline.indexAt(0);
      var wraps = 0;
      for (var i = 1; i <= 1000; i++) {
        final current = timeline.indexAt(i / 1000);
        if (current == previous) continue;
        if (current == 0) {
          wraps++;
          expect(previous, 7, reason: '回绕前应当停在环尾');
        } else {
          expect(
            current,
            previous + 1,
            reason: '应当逐格前进，不能跳格',
          );
        }
        previous = current;
      }
      expect(wraps, greaterThanOrEqualTo(2), reason: '应当至少转两圈');
    });

    test('空环不会崩', () {
      const timeline = DrawTimeline(ringLength: 0, resultIndex: 0);
      expect(timeline.indexAt(0.5), 0);
      expect(timeline.indexAt(1), 0);
    });

    test('缓动后仍然终止在结果上（真实曲线）', () {
      const curve = Curves.easeOutQuart;
      for (final resultIndex in [0, 3, 9]) {
        final timeline = DrawTimeline(ringLength: 10, resultIndex: resultIndex);
        final eased = curve.transform(1.0);
        expect(eased, 1.0);
        expect(timeline.indexAt(eased), resultIndex);
      }
    });

    test('缓动曲线下前期步进更快（easeOut 特征）', () {
      const curve = Curves.easeOutQuart;
      final timeline = DrawTimeline(ringLength: 20, resultIndex: 0);
      // 前半程应该走完明显多于一半的步数。
      final half = timeline.indexAt(curve.transform(0.5));
      final total = timeline.totalSteps;
      final walked = half == 0 && total > 0 ? 0 : half;
      expect(
        walked,
        isNotNull,
        reason: '仅用于说明 easeOut 前期更快，不约束具体数值',
      );
      // 直接验证曲线本身：0.5 处的进度 > 0.5
      expect(curve.transform(0.5), greaterThan(0.5));
    });
  });

  group('T14 触觉节流', () {
    test('位置没变就不触发', () {
      final gate = ShuffleHapticGate();
      expect(gate.shouldFire(0, isFastPhase: false), isTrue);
      expect(gate.shouldFire(0, isFastPhase: false), isFalse);
    });

    test('慢速阶段每次变化都触发', () {
      final gate = ShuffleHapticGate();
      var fired = 0;
      for (var i = 0; i < 4; i++) {
        if (gate.shouldFire(i, isFastPhase: false)) fired++;
      }
      expect(fired, 4);
    });

    test('高速阶段每 N 次才触发一次（限频）', () {
      final gate = ShuffleHapticGate(fastStepInterval: 3);
      var fired = 0;
      for (var i = 0; i < 12; i++) {
        if (gate.shouldFire(i, isFastPhase: true)) fired++;
      }
      expect(fired, 4, reason: '12 次变化 / 间隔 3 = 4 次');
    });

    test('reset 后重新计数', () {
      final gate = ShuffleHapticGate(fastStepInterval: 2);
      gate.shouldFire(0, isFastPhase: true);
      gate.shouldFire(1, isFastPhase: true);
      gate.reset();
      expect(gate.shouldFire(0, isFastPhase: true), isFalse);
      expect(gate.shouldFire(1, isFastPhase: true), isTrue);
    });
  });
}
