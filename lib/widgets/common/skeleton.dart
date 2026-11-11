// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:random_movie/config/design_tokens.dart';

/// 骨架屏的高光来源。
///
/// 整块屏幕只跑**一个** [AnimationController]（而不是每个占位块各跑一个），
/// 通过 [InheritedNotifier] 把进度下发，几千个占位块也只有一条动画在动。
///
/// 用户开启「移除动画」时不创建控制器，进度恒为 0 —— 占位块退化成静态底色，
/// 不会闪烁。
class ShimmerScope extends StatefulWidget {
  final Widget child;

  const ShimmerScope({super.key, required this.child});

  /// 读取当前高光进度（0..1）；不在 [ShimmerScope] 内时返回 0。
  static double progressOf(BuildContext context) {
    final notifier = context
        .dependOnInheritedWidgetOfExactType<_ShimmerProgress>();
    return notifier?.notifier?.value ?? 0;
  }

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  /// 是否已经按当前的「减少动效」设置初始化过控制器。
  ///
  /// 不能只比对 `_reduceMotion` 的布尔值：它初值就是 false，与默认的
  /// 「不减少动效」相同，`didChangeDependencies` 会误判为「没有变化」而直接
  /// 返回，于是控制器永远不会被创建，骨架屏一直是静止的。
  bool _initialized = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (_initialized && reduce == _reduceMotion) return;
    _initialized = true;
    _reduceMotion = reduce;
    if (reduce) {
      _controller?.dispose();
      _controller = null;
    } else {
      _controller?.dispose();
      _controller = AnimationController(vsync: this, duration: Motion.shimmer)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _ShimmerProgress(notifier: ValueNotifier(0.0), child: widget.child);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) =>
          _ShimmerProgress(notifier: controller, child: child!),
      child: widget.child,
    );
  }
}

/// controller 与 ValueNotifier 都满足 [ValueListenable]，统一成一种下发形式。
class _ShimmerProgress extends InheritedNotifier<ValueListenable<double>> {
  const _ShimmerProgress({required super.notifier, required super.child});
}

/// 一个占位块。默认只画静态底色；在 [ShimmerScope] 内会自动带上扫光。
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  /// 圆弧半径；与真实卡片保持一致才不会在加载完成时「跳一下」。
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = Radii.md,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = SurfaceLevel.inset.colorOf(scheme);
    final progress = ShimmerScope.progressOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highlight = Color.alphaBlend(
      scheme.surface.withValues(alpha: 0.55),
      base,
    );

    final shape = borderRadius ?? BorderRadius.circular(radius);

    if (reduceMotion) {
      return SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: base,
            shape: RoundedSuperellipseBorder(borderRadius: shape),
          ),
        ),
      );
    }

    // 高光带从左上扫到右下：位置由 progress 决定，范围略超出以保证进出都有过渡。
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(borderRadius: shape),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [base, highlight, base],
            stops: [
              (progress - 0.25).clamp(0.0, 1.0),
              progress.clamp(0.0, 1.0),
              (progress + 0.25).clamp(0.0, 1.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// 与真实海报卡片同比例（含标题两行）的占位卡。
///
/// 片库首次加载时用它渲染一整屏骨架：因为比例、圆角、间距都和
/// [MovieCard] 一致，数据到位后高度不会跳变。
class SkeletonPosterCard extends StatelessWidget {
  /// 与网格 `childAspectRatio` 保持一致。
  final double aspectRatio;

  const SkeletonPosterCard({super.key, this.aspectRatio = 0.58});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AspectRatio(
            // 海报本体是 2:3，比整卡更「高瘦」，这样标题区高度稳定。
            aspectRatio: 2 / 3,
            child: LayoutBuilder(
              builder: (context, constraints) => SkeletonBox(
                radius: Radii.md,
                width: constraints.maxWidth,
                height: constraints.maxHeight,
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        // 标题两行的位置与 [MovieCard] 一致，加载完成时高度不跳。
        const SkeletonBox(height: 12, radius: 6, width: double.infinity),
        const SizedBox(height: Spacing.xs),
        const FractionallySizedBox(
          widthFactor: 0.5,
          child: SkeletonBox(height: 10, radius: 5, width: double.infinity),
        ),
      ],
    );
  }
}

/// 片库首屏骨架：一整屏与真实网格同参数排列的占位卡。
class LibrarySkeletonGrid extends StatelessWidget {
  /// 与真实网格一致的 `SliverGridDelegateWithMaxCrossAxisExtent` 参数。
  final int count;
  final EdgeInsets padding;

  const LibrarySkeletonGrid({
    super.key,
    this.count = 12,
    this.padding = const EdgeInsets.fromLTRB(
      Spacing.page,
      Spacing.md,
      Spacing.page,
      Spacing.xxl,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return ShimmerScope(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          // 必须与 movies_page._libraryCardExtent 完全一致，
          // 否则骨架 → 真数据时网格会跳动一下。
          mainAxisExtent: textScaler.scale(14) > 19 ? 362.5 : 300.0,
          crossAxisSpacing: Spacing.md,
          mainAxisSpacing: Spacing.lg,
        ),
        itemCount: count,
        itemBuilder: (context, index) => const SkeletonPosterCard(),
      ),
    );
  }
}
