// 弹簧按压反馈统一实现，Apache-2.0。
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:random_movie/config/design_tokens.dart';

/// 可复用的弹簧按压容器。
///
/// 全应用凡是要「按下去缩一点、松开弹回来」的元素都走这里，
/// 而不是各自写 `AnimatedScale` + 不同曲线。这样：
/// - 手感统一：同一套 [Motion.pressSpring] 参数；
/// - 有过冲回弹：`AnimatedScale` 走补间曲线，永远弹不回来，只是线性复原；
/// - 尊重「移除动画」：在这一个地方统一兜底。
///
/// 过冲会让元素短暂略微超出目标尺寸，因此调用方应当把它放在
/// 有裁剪或留白的容器里（卡片本身都带圆角裁剪，通常安全）。
class SpringPressScale extends StatefulWidget {
  const SpringPressScale({
    super.key,
    required this.pressed,
    required this.child,
    this.minScale = 0.975,
    this.alignment = Alignment.center,
  });

  /// 是否处于按下态。由调用方根据 onTapDown / onTapUp / onTapCancel 维护。
  final bool pressed;

  /// 按下时缩放到的比例。
  final double minScale;

  final Alignment alignment;
  final Widget child;

  @override
  State<SpringPressScale> createState() => _SpringPressScaleState();
}

class _SpringPressScaleState extends State<SpringPressScale>
    with SingleTickerProviderStateMixin {
  // unbounded：弹簧回弹会越过终点，有界控制器会把过冲截掉，
  // 观感变成「缩到目标就卡住」，失去回弹手感。
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    // 若首帧就处于按下态（例如被复用的 State），直接落到目标位置。
    if (widget.pressed) _controller.value = widget.minScale;
  }

  @override
  void didUpdateWidget(covariant SpringPressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pressedChanged = oldWidget.pressed != widget.pressed;
    final scaleChanged =
        oldWidget.minScale != widget.minScale && widget.pressed;
    if (pressedChanged || scaleChanged) _animate();
  }

  double get _target => widget.pressed ? widget.minScale : 1.0;

  void _animate() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = _target;
      return;
    }
    _controller.animateWith(
      SpringSimulation(Motion.pressSpring, _controller.value, _target, 0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(
        scale: _controller.value,
        alignment: widget.alignment,
        child: child,
      ),
      child: widget.child,
    );
  }
}
