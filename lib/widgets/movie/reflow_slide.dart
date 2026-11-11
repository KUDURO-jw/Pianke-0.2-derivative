// 片库卡片的位置补位动画。
//
// 背景：片库用普通 SliverGrid，删除后剩余卡片会瞬间跳到新位置，
// 观感很生硬。
//
// 走过的两条弯路（避免重复）：
// 1. 换成 SliverAnimatedGrid —— 它的 initialItemCount 只在首帧生效，
//    片库数据异步加载，直接导致整页空白（严重回归）。
// 2. 在卡片里用 didUpdateWidget 比较行号 —— GridView.builder 在
//    itemCount 变化时是**销毁重建** Element，didUpdateWidget 根本不触发
//    （已用探针实测确认）。
//
// 现在的做法：由外部（页面）在数据变化前后各测一次每张卡片的屏幕位置，
// 把「旧位置 - 新位置」作为起始偏移注入卡片，再动画回 0。
// 这条路不依赖 widget 生命周期，只依赖一次 postFrame 测量。
import 'package:flutter/material.dart';
import 'package:random_movie/config/design_tokens.dart';

/// 卡片位置的补位动画控制器。
///
/// 由页面持有一个实例，在「即将改变数据」与「数据已渲染」两个时刻
/// 分别调用 [captureBefore] / [animateAfter]。
class ReflowController extends ChangeNotifier {
  /// 上一次捕获的位置：key 是影片 id。
  Map<String, Offset> _before = const {};

  /// 当前正在播放的起始偏移：key 是影片 id。
  final Map<String, Offset> _pending = {};

  /// 每个条目的动画进度（0→1）。
  final Map<String, AnimationController> _controllers = {};

  /// 取某个条目的当前偏移。没有动画时返回 [Offset.zero]。
  Offset offsetOf(String id) => _pending[id] ?? Offset.zero;

  /// 记录「变更前」所有可见卡片的位置。
  ///
  /// [keys] 是 id → GlobalKey 的映射，由页面维护。
  void captureBefore(Map<String, GlobalKey> keys) {
    final result = <String, Offset>{};
    for (final entry in keys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        result[entry.key] = box.localToGlobal(Offset.zero);
      }
    }
    _before = result;
  }

  /// 数据已重新渲染：比对位置并启动补位动画。
  ///
  /// 必须在帧后调用（页面用 addPostFrameCallback 调度）。
  void animateAfter(
    Map<String, GlobalKey> keys, {
    required TickerProvider vsync,
    bool enabled = true,
  }) {
    final before = _before;
    _before = const {};
    if (before.isEmpty) return;

    for (final entry in keys.entries) {
      final id = entry.key;
      final oldPos = before[id];
      if (oldPos == null) continue;

      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;

      final newPos = box.localToGlobal(Offset.zero);
      final dx = oldPos.dx - newPos.dx;
      final dy = oldPos.dy - newPos.dy;

      // 只有纵向变化才补动画；横向（换列）属于重排，硬切更自然。
      if (dx.abs() > 1 || dy.abs() < 1) continue;
      if (!enabled) continue;

      _controllers[id]?.dispose();
      final controller = AnimationController(
        vsync: vsync,
        duration: Motion.normal,
      );
      _controllers[id] = controller;
      _pending[id] = Offset(0, dy);

      controller.addListener(() {
        final t = Motion.standard.transform(controller.value.clamp(0.0, 1.0));
        _pending[id] = Offset(0, dy * (1 - t));
        notifyListeners();
      });
      controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _pending.remove(id);
          controller.dispose();
          _controllers.remove(id);
          notifyListeners();
        }
      });
      controller.forward();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _pending.clear();
    super.dispose();
  }
}

/// 读取 [ReflowController] 给出的位移并应用到子组件。
class ReflowSlide extends StatelessWidget {
  const ReflowSlide({
    super.key,
    required this.id,
    required this.controller,
    required this.child,
  });

  final String id;
  final ReflowController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final offset = controller.offsetOf(id);
        if (offset == Offset.zero) return child!;
        return Transform.translate(offset: offset, child: child);
      },
      child: child,
    );
  }
}
