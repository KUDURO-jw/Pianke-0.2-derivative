// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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

/// 当前正在显示的撤销提示条。
///
/// 全局只允许存在一条。连续删除多部影片时：
/// - 旧提示条立刻关闭（按「被顶掉」处理 → 确认删除前一部）
/// - 新提示条接管位置
///
/// 不做单例的后果（用户实际遇到）：同时删三部会叠三层提示条，
/// 每层都在跑自己的倒计时与弹簧动画，画面持续重绘 → 卡顿 + 闪烁。
/// 而且三条叠在一起，用户根本分不清「撤销」点的是哪一部。
_UndoBannerHandle? _activeBanner;

/// 一条正在显示的撤销提示的可控句柄。
///
/// [dismiss] 由新提示调用，用来把旧提示按「被顶掉」结束掉。
class _UndoBannerHandle {
  _UndoBannerHandle({required this.dismiss, required this.isAlive});

  final void Function() dismiss;
  final bool Function() isAlive;
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
  // 顶掉上一条：新提示接管，旧提示按「被顶掉」结束（→ 确认删除上一条）。
  // 这样连续删除多部时界面上永远只有一条，且每一部都会被正确提交。
  final previous = _activeBanner;
  _activeBanner = null;
  previous?.dismiss();

  final completer = Completer<UndoDismissReason>();
  late OverlayEntry entry;
  final hostKey = GlobalKey<_UndoBannerHostState>();

  // 先声明 handle，finish 里要用它做「我还是不是当前那条」的判断。
  // 用 late 是为了让 dismiss 闭包能引用到 handleself。
  late final _UndoBannerHandle handle;
  handle = _UndoBannerHandle(
    dismiss: () {
      final state = hostKey.currentState;
      if (state != null && state.mounted) {
        // 让宿主播退场，结束后统一走 finish。
        state.dismissAs(UndoDismissReason.replaced);
      } else if (!completer.isCompleted) {
        // 宿主还没挂载就被顶掉：直接按「确认删除」完成，不能丢。
        completer.complete(UndoDismissReason.replaced);
      }
    },
    isAlive: () => !completer.isCompleted,
  );

  void finish(UndoDismissReason reason, {required bool removeNow}) {
    // 只有当「当前记录的还是我」时才清空全局引用，
    // 避免旧提示的收尾回调把新提示的引用抹掉。
    if (identical(_activeBanner, handle)) {
      _activeBanner = null;
    }
    if (!completer.isCompleted) completer.complete(reason);
    if (removeNow && entry.mounted) entry.remove();
  }

  _activeBanner = handle;

  entry = OverlayEntry(
    builder: (context) => _UndoBannerHost(
      key: hostKey,
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
    super.key,
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

  /// 上报关闭原因。[removeNow] 为真表示退场动画已结束，可以移除 entry。
  final void Function(UndoDismissReason reason, {required bool removeNow})
      onDismiss;

  final VoidCallback onUndo;

  @override
  State<_UndoBannerHost> createState() => _UndoBannerHostState();
}

class _UndoBannerHostState extends State<_UndoBannerHost>
    with TickerProviderStateMixin {
  /// 入场/退场动画（0=完全隐藏，1=完全显示）。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.reduceMotion ? Duration.zero : Motion.panel,
  );

  /// 倒计时进度（1→0）。与 [_controller] 分开：拖动提示条时倒计时暂停，
  /// 松手回弹后继续，两者互不干扰。
  ///
  /// 用 controller 而不是 Timer：同一个时间源既驱动底部进度条，
  /// 又在归零时触发关闭，不会出现「进度条走完了但还没关」的错位。
  late final AnimationController _countdown = AnimationController(
    vsync: this,
    duration: widget.undoWindow,
    value: 1,
  );

  /// 已处理过关闭，防止「点撤销」和「超时」重复提交。
  bool _settled = false;

  /// 退场专用弹簧：硬、临界阻尼，约 130ms 视觉收束，不过冲。
  ///
  /// 参数用逐帧采样实测选定（目标：手感上「甩手即走」）：
  /// - stiffness 350（settleSpring）→ 透明到不可见要 220ms，总时长 416ms
  /// - stiffness 700 → 260ms
  /// - stiffness 1800 + 容差 0.05 → 约 130ms，与手势结束节奏一致
  ///
  /// ratio = 1.0 临界阻尼：单调收敛、不过冲，
  /// 不会先弹回去再落下。
  static final SpringDescription _exitSpring =
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 1800,
        ratio: 1.0,
      );

  /// 退场瞬间冻结的拖动位移。
  ///
  /// 退场期间位移 = [_exitDragStart] 恒定值 + 按 (1 - t) 叠加的甩出距离。
  /// 用单一时间源（[_controller]）驱动，避免两条曲线互相拉扯。
  double _exitDragStart = 0;

  /// 用户拖动产生的纵向位移（向下为正）。
  double _dragOffset = 0;

  /// 当前拖动是否已越过关闭阈值。
  bool _dragPastThreshold = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _countdown.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !_settled) {
        _settle(UndoDismissReason.timeout);
      }
    });
    // 从 1 走到 0：duration 就是 undoWindow。
    _countdown.reverse(from: 1);
  }

  @override
  void dispose() {
    // 宿主在提示条还在时被销毁：按「确认删除」处理，避免幽灵条目。
    // 注意此时不能再去 remove entry（正在 dispose 中），removeNow 传 false。
    if (!_settled) {
      _settled = true;
      widget.onDismiss(UndoDismissReason.disposed, removeNow: false);
    }
    _controller.dispose();
    _countdown.dispose();
    super.dispose();
  }

  /// 结束提示条：停计时、播退场、等动画真的结束再移除 entry。
  ///
  /// 退场分成两件事，各自用合适的驱动方式：
  ///
  /// - **位移**用弹簧，并带上用户松手时的速度 → 「被甩走」的势头。
  ///   陷阱：`SpringSimulation` 的 velocity 是「朝目标方向为正」。
  ///   目标是 0（隐藏），所以向下甩（velocity 为正）要传**正值**才对；
  ///   原来直接传 `velocity / 400` 在数学上没错，但弹簧会先过冲越过 0
  ///   再折返，`Transform.translate` 于是先往回弹一下再落下——
  ///   那一下折返就是用户看到的「最后还闪一下」。
  ///   这里改用临界阻尼（`Motion.snapSpring`），不过冲、单调收敛。
  ///
  /// - **透明度**用线性收束到 0，与位移同步结束。
  ///
  /// 关键：`onDismiss(removeNow: true)` 必须在两者都**播完之后**才发，
  /// 否则 overlay entry 被提前摘掉，画面硬切。
  void _settle(UndoDismissReason reason, {double velocity = 0}) {
    if (_settled) return;
    _settled = true;
    _countdown.stop();

    if (widget.reduceMotion) {
      widget.onDismiss(reason, removeNow: true);
      return;
    }

    // velocity 归一化：拖动速度是 px/s，除 1200 后落在弹簧能接受的量级。
    final springVelocity = (velocity / 1200).clamp(-4.0, 4.0);

    // 记下退场瞬间的拖动位移。
    //
    // 退场期间这个值不再变化，位移改由 build 里按 (1 - t) 再叠一段
    // 甩出距离。不用第二个控制器分别驱动拖动位移与透明度——
    // 两条曲线叠加会互相拉扯，出现「先往下再弹回」的折返，
    // 那比原来的问题更难看。
    _exitDragStart = _dragOffset;

    _controller
        .animateWith(
          SpringSimulation(
            // 退场要「干净利落」：硬一点的临界阻尼弹簧，单调收敛、不过冲。
            _exitSpring,
            _controller.value,
            0,
            springVelocity,
            // 容差 0.05：透明度低于 5% 时肉眼已分辨不出，
            // 此时就结束退场、移除 entry。
            tolerance: const Tolerance(distance: 0.05, velocity: 0.05),
          ),
        )
        .whenCompleteOrCancel(() {
          if (!mounted) return;
          // 关键：用 `removeNow` 让调用方立刻移除 entry。
          //
          // 不能等弹簧「数值上完全归零」——那要 300ms 以上，
          // 而透明度在 110ms 时已经低于 0.04，肉眼完全看不出。
          // 多挂着的这 200ms 就是用户说的「最后还顿一下」：
          // entry 还在，虽然几乎全透明，但它占着一个合成层，
          // 移除瞬间下层要重绘，观感上就是一下闪动。
          widget.onDismiss(reason, removeNow: true);
        });
  }

  void _handleUndo() {
    if (_settled) return;
    _countdown.stop();
    widget.onUndo();
    // 注意不要先置 _settled 再调 _settle：_settle 自己会置，
    // 先置会导致 _settle 直接 return，entry 永远不被移除。
    _settle(UndoDismissReason.undo);
  }

  /// 被新提示顶掉时调用：立刻退场并把原因报为 [reason]。
  ///
  /// 与 [dispose] 的区别是它走正常退场流程（有弹簧动画），
  /// 且会通知调用方移除 entry。连续删除多部时靠它让旧提示让位。
  void dismissAs(UndoDismissReason reason) {
    if (_settled) return;
    _settle(reason);
  }

  void _onDragStart(DragStartDetails _) {
    if (_settled) return;
    _countdown.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_settled) return;
    setState(() {
      // 只允许向下拖；向上给一点阻尼，不跟手。
      final delta = details.delta.dy;
      _dragOffset = (_dragOffset + (delta > 0 ? delta : delta * 0.3))
          .clamp(0.0, 160.0);
      _dragPastThreshold = _dragOffset > 56;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_settled) return;
    final velocity = details.primaryVelocity ?? 0;

    if (_dragPastThreshold || velocity > 700) {
      // 越过阈值或甩得够快：按下滑关闭处理。
      _settle(UndoDismissReason.swipe, velocity: velocity / 400);
      return;
    }

    // 没到阈值：弹簧回弹到原位，倒计时继续。
    setState(() {
      _dragOffset = 0;
      _dragPastThreshold = false;
    });
    _countdown.reverse(from: _countdown.value);
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
        animation: Listenable.merge([_controller, _countdown]),
        builder: (context, child) {
          // t: 1 = 完全显示，0 = 完全退场。
          // 弹簧可能算出极小的负值或略大于 1，钳住避免反向抖动。
          final t = _controller.value.clamp(0.0, 1.0);

          // 退场进度（0 = 刚开始退，1 = 完全退完）。
          final exitProgress = 1 - t;

          // 位移由三部分叠加，全部朝下（正值），不会出现折返：
          //
          // 1. enterLift：入场时从下方 12dp 浮上来，退场时反向回落。
          // 2. 拖动位移：拖动中是实时的 `_dragOffset`；
          //    退场开始后冻结为 `_exitDragStart`，不再变化。
          // 3. exitThrow：退场时额外朝下走 60dp，
          //    让提示条「被甩出」而不是「原位淡出」。
          //
          // 第 3 项是关键：早先退场只做透明度收束，用户拖了 120dp 之后
          // 松手只再走 12dp 就淡完了，视觉上就是「停在半空慢慢变透明，
          // 然后突然没了」——反馈里的「最后还闪一下」。
          final enterLift = exitProgress * 12;
          final dragPart = _settled ? _exitDragStart : _dragOffset;
          final exitThrow = exitProgress * 60;

          // 拖动进度：越往下越透明，给「松手就没了」的预期。
          final dragProgress = (dragPart / 120).clamp(0.0, 1.0);
          final opacity = (t * (1 - dragProgress * 0.75)).clamp(0.0, 1.0);

          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, enterLift + dragPart + exitThrow),
              child: child,
            ),
          );
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: GestureDetector(
              // 拖动而不是 fling：要跟手，不能等手势结束才动。
              onVerticalDragStart: _onDragStart,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              child: _UndoBannerSurface(
                scheme: scheme,
                label: widget.label,
                countdown: _countdown,
                pastThreshold: _dragPastThreshold,
                onUndo: _handleUndo,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 提示条的可视部分：连续圆角深色胶囊 + 文字 + 撤销按钮 + 倒计时进度。
///
/// 视觉参数对齐项目既有规范：
/// - 深色胶囊用 `#2A2A2E`（与全局 snackBarTheme 一致）
/// - 连续圆角 `Radii.md`
/// - 文字 `TypeScale.body` / w500
/// - 撤销按钮用主题强调色
///
/// 倒计时参考 Telegram 的撤销提示：胶囊底部一条细进度条随剩余时间收缩，
/// 让「还剩多久」可见，比单纯等 5 秒然后突然消失更容易预期。
class _UndoBannerSurface extends StatelessWidget {
  const _UndoBannerSurface({
    required this.scheme,
    required this.label,
    required this.countdown,
    required this.pastThreshold,
    required this.onUndo,
  });

  final ColorScheme scheme;
  final String label;

  /// 剩余时间进度：1 = 刚开始，0 = 到时。
  final Animation<double> countdown;

  /// 拖动是否已越过关闭阈值（越过时文字变淡，提示松手就关）。
  final bool pastThreshold;

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF2A2A2E);
    final shape = ContinuousRRect(radius: Radii.md, smoothing: 0.6);

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: Shadows.floating(scheme),
      ),
      child: Material(
        color: surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm + 2,
                Spacing.sm,
                Spacing.sm + 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: AnimatedOpacity(
                      duration: Motion.fast,
                      opacity: pastThreshold ? 0.45 : 1,
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
            // 倒计时进度条：贴底、极细、随剩余时间收缩。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: countdown,
                builder: (context, _) {
                  final remaining = countdown.value.clamp(0.0, 1.0);
                  return FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: remaining,
                    child: Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: scheme.accent.withValues(alpha: 0.85),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(2),
                          bottomRight: Radius.circular(2),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
