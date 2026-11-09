// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:random_movie/config/design_tokens.dart';

/// 单张卡片的进入动画（渐显 + 轻微上浮）。
///
/// 只给「本批新增」的条目播放一次，已在屏上的条目保持静止——
/// 否则列表一重排整屏都会闪一下，比没有动画更让人分心。
///
/// [play] 为 false（或处于「减少动效」）时直接渲染终态，不创建任何动画。
class AnimatedCardEntrance extends StatefulWidget {
  final Widget child;
  final bool play;
  final bool reduceMotion;

  const AnimatedCardEntrance({
    super.key,
    required this.child,
    this.play = true,
    this.reduceMotion = false,
  });

  @override
  State<AnimatedCardEntrance> createState() => _AnimatedCardEntranceState();
}

class _AnimatedCardEntranceState extends State<AnimatedCardEntrance> {
  /// 入场只播一次：播完就把标记关掉，避免后续重建时反复播放。
  late bool _playOnce = widget.play && !widget.reduceMotion;

  @override
  void initState() {
    super.initState();
    if (_playOnce) {
      // 让首帧先停在起点，否则 TweenAnimationBuilder 会直接跳到终态。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _playOnce = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.play && !_playOnce) return widget.child;
    if (widget.reduceMotion) return widget.child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, Motion.normal),
      curve: Motion.standard,
      builder: (context, value, child) => Opacity(
        // 不用 0 起手：完全透明会让 Hero 飞行起点短暂「消失」。
        opacity: 0.15 + 0.85 * value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 8),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
