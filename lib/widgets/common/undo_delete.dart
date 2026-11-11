// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/services/haptics.dart';

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
bool shouldCommitDeleteAfter(SnackBarClosedReason? reason) =>
    reason != SnackBarClosedReason.action;

/// 可撤销删除。
///
/// 流程刻意做成「先隐藏、后提交」：
/// 1. [hide] 立刻把条目从界面移走 —— 用户看到删除已经生效；
/// 2. 弹出带「撤销」的提示条；
/// 3. 提示条自然结束时才 [commit] 真正删库；点了「撤销」就 [restore]。
///
/// 这样**不存在回滚**：撤销只是「什么都没发生」，比对数据库做反向操作可靠得多。
///
/// 一个已知的边界：这 5 秒内进程被杀，条目仍是「未删除」状态。
/// 这是安全的方向（宁可留着也别误删），下次进入仍然能看到它。
Future<void> deleteWithUndo(
  BuildContext context, {
  required String label,
  required Future<void> Function() commit,
  required VoidCallback hide,
  required VoidCallback restore,

  /// 撤销窗口时长。默认 [kUndoWindow]；测试可传更短的值，
  /// 避免依赖提示条的动画计时。
  Duration undoWindow = kUndoWindow,
}) async {
  // 取值必须在同步阶段完成：调用方可能在这之后被 dispose。
  final messenger = ScaffoldMessenger.maybeOf(context);
  final scheme = Theme.of(context).colorScheme;
  final dockInset = _bottomInsetOf(context);

  hide();
  Haptics.warning();

  // 注意不能只看 `ScaffoldMessenger.maybeOf` 是否为 null：
  // 存在 messenger 但当前没有挂载任何 Scaffold 时，showSnackBar 会直接断言失败。
  // 所以这里必须同时确认「有 messenger」且「至少能显示」——用 try 兜住断言，
  // 显示不出来就退回直接提交，绝不留下「隐藏了却没删」的幽灵条目。
  SnackBarClosedReason? reason;
  if (messenger != null) {
    try {
      // 直接 showSnackBar，不先 removeCurrentSnackBar。
      //
      // 为什么去掉 remove：`removeCurrentSnackBar()` 内部会把
      // `_snackBarController.value = 0.0`，这个赋值触发的是**动画状态回调**，
      // 要到下一帧才把旧条从队列移除。而紧接着的 `showSnackBar` 检查
      // `_snackBars.isEmpty` 决定要不要 `forward()` —— 此刻旧条还在队列里，
      // 于是新条**不会 forward**，`isCompleted` 永远为 false，
      // ScaffoldMessenger 的倒计时 Timer 永远不启动。
      // 结果就是提示条不自动消失、`closed` 永不完成、`commit()` 永不执行。
      //
      // 直接 show 时，若队列里已有旧条，ScaffoldMessenger 会把它排在后面，
      // 旧条走完自己的流程后自动 forward 新条，计时正常。
      final controller = messenger.showSnackBar(
        SnackBar(
          content: Text(label),
          duration: undoWindow,
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.inverseSurface,
          margin: EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, dockInset),
          action: SnackBarAction(
            label: '撤销',
            textColor: scheme.inversePrimary,
            onPressed: () {
              Haptics.selection();
              restore();
            },
          ),
        ),
      );
      reason = await controller.closed;
    } catch (_) {
      // 没有可用 Scaffold 等：走下面的直接提交分支。
      reason = null;
    }
  }

  if (!shouldCommitDeleteAfter(reason)) return;
  await commit();
}

/// 提示条要浮在悬浮底栏上方，避开它，避免被遮住。
double _bottomInsetOf(BuildContext context) {
  final padding = MediaQuery.paddingOf(context).bottom;
  // DockMetrics 在 floating_nav_bar.dart 里，这里不引入整个组件文件，
  // 只用安全区 + 一点余量：底栏本身已按安全区自适配。
  return padding + Spacing.xxl;
}
