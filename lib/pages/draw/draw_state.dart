// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:random_movie/models/models.dart';

/// 抽片页的状态。
///
/// 原先用一个 `DrawPhase` 枚举加若干 `Timer` / `Future.delayed` 拼节奏，
/// 状态与定时器交错，很难说明「现在到底处于哪一步」。
///
/// 改成 sealed class 之后：
/// - 每个状态携带自己需要的字段，不存在「选了但没结果」这种半成品组合；
/// - switch 是穷尽的，新增状态编译器会报错，不会漏分支；
/// - 状态转换集中在一处，页面只负责渲染。
sealed class DrawState {
  const DrawState();
}

/// 选片阶段：挑候选、选模式、设筛选。
class DrawSelecting extends DrawState {
  const DrawSelecting();
}

/// 转动阶段：转盘上有 [ring] 这些影片，最终停在 [resultIndex]。
class DrawSpinning extends DrawState {
  final List<Movie> ring;
  final int resultIndex;

  const DrawSpinning({required this.ring, required this.resultIndex});
}

/// 三选一阶段：给出 [options]，由用户挑选。
class DrawPicking extends DrawState {
  final List<Movie> options;

  const DrawPicking({required this.options});
}

/// 揭晓阶段：结果已确定并已写入记录。
class DrawRevealed extends DrawState {
  final Movie movie;
  final String? recordId;

  const DrawRevealed({required this.movie, this.recordId});
}

/// 转盘时间线：把「转几下、停在谁」算成纯函数，便于测试。
///
/// 关键点：**终点必须恰好落在结果上**。原实现转完后用 `indexOf` 回找位置，
/// 一旦候选里有重复对象或结果不在候选里就会落错；这里改为
/// 「预先算出总步数，让最后一步 ≡ resultIndex」，不需要任何回找。
class DrawTimeline {
  /// 至少转几圈。转得太少会显得「没抽」，太多会拖时间。
  static const int minLaps = 2;

  final int ringLength;

  /// 结果在 ring 中的下标。
  final int resultIndex;

  const DrawTimeline({required this.ringLength, required this.resultIndex});

  /// 总步数：整数圈 + 落到结果所需的那几步。
  int get totalSteps => minLaps * ringLength + resultIndex;

  /// 给定动画进度（0..1，已过缓动曲线），当前应显示第几个。
  ///
  /// [eased] 必须是**已经过曲线变换**的值；这里只做「进度 → 下标」的映射。
  int indexAt(double eased) {
    if (ringLength <= 0) return 0;
    final clamped = eased.clamp(0.0, 1.0);
    // 用 floor 保证 t=1 时才到达 totalSteps；再取模回到 ring 内。
    // 末尾额外 +0.5 步的修正不需要——floor(totalSteps) 就是 totalSteps，
    // 取模后正好等于 resultIndex。
    final step = (clamped * totalSteps).floor();
    return step % ringLength;
  }

  /// 进度到 1 时是否已经停在结果上（供断言与调试使用）。
  bool get endsOnResult => indexAt(1) == resultIndex % ringLength;
}

/// 转动时的触觉节流。
///
/// 高速阶段每一步都震会变成持续嗡嗡声，所以只在位置变化且间隔够久时触发。
class ShuffleHapticGate {
  final int fastStepInterval;
  int _lastIndex = -1;
  int _calls = 0;

  ShuffleHapticGate({this.fastStepInterval = 3});

  /// 返回本次是否应当触发触觉。
  ///
  /// [isFastPhase] 为真时每 [fastStepInterval] 次位置变化才允许一次。
  bool shouldFire(int index, {required bool isFastPhase}) {
    final moved = index != _lastIndex;
    if (!moved) return false;
    _lastIndex = index;
    _calls++;
    if (!isFastPhase) return true;
    return _calls % fastStepInterval == 0;
  }

  void reset() {
    _lastIndex = -1;
    _calls = 0;
  }
}
