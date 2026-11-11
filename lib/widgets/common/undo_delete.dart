// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/services/haptics.dart';
import 'package:random_movie/widgets/common/continuous_rrect.dart';

/// 撤销提示停留时长。
///
/// 太短来不及点，太长会让「删除」像没生效。5 秒是 iOS/Android 通用惯例。
const Duration kUndoWindow = Duration(seconds: 5);

/// 判断提示条关闭后是否应该真正删除。
///
/// 抽成纯函数是为了能直接测：这类「什么情况下算确认」的判断一旦写错，
/// 后果是数据静默丢失或留下删不掉的条目，比动画细节重要得多。
///
/// 只有用户**明确点了「撤销」**才不删。其余情况——超时、被新提示顶掉、
/// 下滑关闭、甚至提示条压根没能显示（[reason] 为 null）——都必须提交，
/// 否则界面已经隐藏了条目，数据库却永远留着它，形成幽灵数据。
bool shouldCommitDeleteAfter(UndoDismissReason? reason) =>
    reason != UndoDismissReason.undo;

/// 提示条消失的原因。
enum UndoDismissReason {
  /// 到时自动消失 → 确认删除
  timeout,

  /// 用户点了「撤销」→ 不删
  undo,

  /// 用户下滑关闭 → 确认删除
  swipe,

  /// 被新的提示顶掉 → 确认删除
  replaced,

  /// 宿主销毁 → 确认删除
  disposed,
}

/// 可撤销删除。
///
/// 流程刻意做成「先隐藏、后提交」：
/// 1. [hide] 立刻把条目从界面移走 —— 用户看到删除已经生效；
/// 2. 弹出带「撤销」的提示条；
/// 3. 提示条自然结束时才 [commit] 真正删库；点了「撤销」就 [restore]。
///
/// 这样**不存在回滚**：撤销只是「什么都没发生」，比对数据库做反向操作可靠得多。
///
/// ## 为什么不用 ScaffoldMessenger / SnackBar
///
/// 项目原先用 `ScaffoldMessenger.showSnackBar` 实现，出现两个问题：
///
/// 1. **提示条不自动消失**。`ScaffoldMessengerState.build` 里启动倒计时
///    有一个前置条件 `_snackBarController.isCompleted`，而 controller 只在
///    `_snackBars.isEmpty` 时才会 `forward()`。本项目的调用时序
///    （对话框 `pop()` 之后立刻调用）会让这个条件永远不满足，
///    于是 `Timer` 从不创建 → 提示条不消失 → `controller.closed` 永不完成
///    → `commit()` 不执行 → 界面显示已删除但数据库还留着。
/// 2. **下滑关闭时闪屏**。SnackBar 的退场走 Material 内置动画，
///    与本项目「页面转场不用淡入」的取向冲突，滑走那一下会露出背景。
///
/// 自绘提示条完全可控：定时器自己持有、退场动画自己写、视觉与项目一致。
Future<void> deleteWithUndo(
  BuildContext context, {
  required String label,
  required Future<void> Function() commit,
  required VoidCallback hide,
  required VoidCallback restore,

  /// 撤销窗口时长。默认 [kUndoWindow]；测试可传更短的值。
  Duration undoWindow = kUndoWindow,
}) async {
  // 取值必须在同步阶段完成：调用方可能在这之后被 dispose。
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final scheme = Theme.of(context).colorScheme;
  final reduceMotion = MediaQuery.disableAnimationsOf(context);

  hide();
  Haptics.warning();

  if (overlay == null) {
    // 没有 Overlay（极端情况）：提示条显示不出来，按「确认删除」处理，
    // 绝不留下「隐藏了却没删」的幽灵条目。
    await commit();
    return;
  }

  final reason = await _showUndoBanner(
    overlay: overlay,
    scheme: scheme,
    label: label,
    undoWindow: undoWindow,
    reduceMotion: reduceMotion,
    onUndo: () {
      Haptics.selection();
      restore();
    },
  );

  if (!shouldCommitDeleteAfter(reason)) return;
  await commit();
}

/// 在 Overlay 上挂一条自绘提示条，返回它消失的原因。
Future<UndoDismissReason> _showUndoBanner({
  required OverlayState overlay,
  required ColorScheme scheme,
  required String label,
  required Duration undoWindow,
  required bool reduceMotion,
  required VoidCallback onUndo,
}) {
  final completer = Completer<UndoDismissReason>();
  late OverlayEntry entry;

  void finish(UndoDismissReason reason) {
    if (completer.isCompleted) return;
    completer.complete(reason);
    // 等退场动画播完再移除 entry，避免硬切造成闪烁。
    Future<void>.delayed(reduceMotion ? Duration.zero : Motion.panel, () {
      if (entry.mounted) entry.remove();
    });
  }

  entry = OverlayEntry(
    builder: (context) => _UndoBannerHost(
      scheme: scheme,
      label: label,
      undoWindow: undoWindow,
      reduceMotion: reduceMotion,
      onDismiss: finish,
      onUndo: onUndo,
    ),
  );

  overlay.insert(entry);
  return completer.future;
}

/// 提示条本体：负责入场动画、倒计时、下滑关闭。
class _UndoBannerHost extends StatefulWidget {
  const _UndoBannerHost({
    required this.scheme,
    required this.label,
    required this.undoWindow,
    required this.reduceMotion,
    required this.onDismiss,
    required this.onUndo,
  });

  final ColorScheme scheme;
  final String label;
  final Duration undoWindow;
  final bool reduceMotion;
  final void Function(UndoDismissReason) onDismiss;
  final VoidCallback onUndo;

  @override
  State<_UndoBannerHost> createState() => _UndoBannerHostState();
}

class _UndoBannerHostState extends State<_UndoBannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.reduceMotion ? Duration.zero : Motion.panel,
  );

  Timer? _timer;

  /// 已处理过关闭，防止「点撤销」和「超时」重复提交。
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // 倒计时自己持有，不依赖任何框架的 SnackBar 状态机。
    _timer = Timer(widget.undoWindow, () => _settle(UndoDismissReason.timeout));
  }

  @override
  void dispose() {
    _timer?.cancel();
    // 宿主在提示条还在时被销毁：按「确认删除」处理，避免幽灵条目。
    if (!_settled) {
      _settled = true;
      widget.onDismiss(UndoDismissReason.disposed);
    }
    _controller.dispose();
    super.dispose();
  }

  /// 结束提示条：停计时、播退场、上报原因。
  void _settle(UndoDismissReason reason) {
    if (_settled) return;
    _settled = true;
    _timer?.cancel();
    _controller.reverse();
    widget.onDismiss(reason);
  }

  void _handleUndo() {
    if (_settled) return;
    _settled = true;
    _timer?.cancel();
    widget.onUndo();
    _controller.reverse();
    widget.onDismiss(UndoDismissReason.undo);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final media = MediaQuery.of(context);
    // 浮在悬浮底栏上方，与 AppToast 保持同一套避让规则。
    final bottomInset = media.padding.bottom + Spacing.xxl +
        (media.viewInsets.bottom > 0 ? 0 : 44);

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomInset,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Motion.fade.transform(_controller.value.clamp(0.0, 1.0));
          return Opacity(
            opacity: t,
            // 入场从下方轻微上浮，退场回落；不做整层淡入淡出，
            // 避免滑走时露出背景造成闪烁。
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 12),
              child: child,
            ),
          );
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: _UndoBannerSurface(
              scheme: scheme,
              label: widget.label,
              onUndo: _handleUndo,
              onSwipeDismiss: () => _settle(UndoDismissReason.swipe),
            ),
          ),
        ),
      ),
    );
  }
}

/// 提示条的可视部分：连续圆角深色胶囊 + 文字 + 撤销按钮。
///
/// 视觉参数对齐项目既有规范：
/// - 深色胶囊用 `#2A2A2E`（与全局 snackBarTheme 一致）
/// - 连续圆角 `Radii.md`
/// - 文字 `TypeScale.body` / w500
/// - 撤销按钮用主题强调色
class _UndoBannerSurface extends StatelessWidget {
  const _UndoBannerSurface({
    required this.scheme,
    required this.label,
    required this.onUndo,
    required this.onSwipeDismiss,
  });

  final ColorScheme scheme;
  final String label;
  final VoidCallback onUndo;
  final VoidCallback onSwipeDismiss;

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF2A2A2E);
    final shape = ContinuousRRect(radius: Radii.md, smoothing: 0.6);

    return GestureDetector(
      // 下滑关闭：与系统提示条一致的手势习惯。
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 0) onSwipeDismiss();
      },
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          shadows: Shadows.floating(scheme),
        ),
        child: Material(
          color: surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm + 2,
              Spacing.sm,
              Spacing.sm + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: TypeScale.body,
                      fontWeight: FontWeight.w500,
                      height: TypeScale.lineHeight,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                TextButton(
                  onPressed: onUndo,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.xs,
                    ),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: ContinuousRRect(
                      radius: Radii.pill,
                      smoothing: 0.6,
                    ),
                  ),
                  child: const Text(
                    '撤销',
                    style: TextStyle(
                      fontSize: TypeScale.label,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
