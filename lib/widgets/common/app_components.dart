// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
export 'floating_nav_bar.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/continuous_rrect.dart';

/// 通用 UI 组件库 —— 全应用统一使用，保证视觉一致性。

// ────────────────────────────────────────────
// 卡片
// ────────────────────────────────────────────

/// 标准卡片。白底 + 连续圆角 + 极淡阴影。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final bool shadow;
  final BorderSide? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.radius = Radii.xl,
    this.shadow = false,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MellowPanel(
      color: color ?? scheme.cardSurface,
      radius: radius,
      border: border ?? BorderSide.none,
      padding: padding ?? const EdgeInsets.all(Spacing.cardPadding),
      shadow: shadow,
      onTap: onTap,
      child: child,
    );
  }
}

/// 卡片内二级色块（比卡片略深），用于承载子项。
class AppTileGroup extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const AppTileGroup({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: ShapeDecoration(
        color: scheme.blockSurface,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide.none,
        ),
      ),
      padding: padding ?? const EdgeInsets.all(Spacing.lg),
      child: child,
    );
  }
}

// ────────────────────────────────────────────
// 页面标题
// ────────────────────────────────────────────

/// 大标题 + 副标题 + 右侧操作。对应参考设计的页面头部。
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            Spacing.page,
            Spacing.md,
            Spacing.page,
            Spacing.md,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: TypeScale.headline,
                    fontWeight: FontWeight.w700,
                    color: scheme.primaryText,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: TypeScale.caption,
                      color: scheme.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 圆形图标按钮，用于页面头部右侧。
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final String? tooltip;

  const RoundIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.filled = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final btn = SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: filled ? scheme.accent : scheme.cardSurface,
        shape: ContinuousRRect(
          radius: Radii.pill,
          smoothing: 0.6,
          side: filled ? BorderSide.none : BorderSide(color: scheme.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Icon(
            icon,
            size: 20,
            color: filled ? Colors.white : scheme.primaryText,
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

// ────────────────────────────────────────────
// 搜索框
// ────────────────────────────────────────────

/// 胶囊搜索框。外部传 controller 以支持清空。
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hint;
  final VoidCallback? onClear;
  final bool hasText;

  const AppSearchField({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hint = '搜索',
    this.onClear,
    this.hasText = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 48 + (MediaQuery.textScalerOf(context).scale(14) - 14),
      decoration: ShapeDecoration(
        color: scheme.cardSurface,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
          side: BorderSide(color: scheme.hairline),
        ),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: TypeScale.body, color: scheme.primaryText),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          hintStyle: TextStyle(
            color: scheme.secondaryText,
            fontSize: TypeScale.body,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: scheme.secondaryText,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: scheme.secondaryText,
                  onPressed: onClear,
                  tooltip: '清空搜索',
                )
              : null,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────
// 分段控件
// ────────────────────────────────────────────

/// 分段切换器。整体一个容器，选中块在内部，比一排胶囊更整体。
///
/// [selectedIndex] 是选中项（整数）。当需要选中块跟随滑动实时过渡时，
/// 传入 [progress]（浮点，0..labels.length-1），此时选中块的位置与颜色
/// 随该值连续变化，不再等到整数切换才跳变。片库页只传 [selectedIndex]，
/// 行为与之前完全一致。
class SegmentedSwitch extends StatelessWidget {
  final List<String> labels;
  final List<int> counts;
  final int selectedIndex;
  final double? progress;
  final ValueChanged<int> onChanged;

  const SegmentedSwitch({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.counts = const [],
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final double p = (progress ?? selectedIndex.toDouble())
        .clamp(0.0, (labels.length - 1).toDouble());

    return Container(
      height: 44 + (MediaQuery.textScalerOf(context).scale(13) - 13),
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        color: SurfaceLevel.inset.colorOf(scheme),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
          side: BorderSide.none,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = (constraints.maxWidth - 6) / labels.length;
          return Stack(
            children: [
              // 选中块：位置与颜色随 p 连续移动
              AnimatedPositioned(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : (progress != null
                          ? const Duration(milliseconds: 60)
                          : Motion.normal),
                curve: progress != null ? Curves.linear : Motion.emphasized,
                left: 3 + p * slot,
                top: 0,
                bottom: 0,
                width: slot - 6,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  decoration: ShapeDecoration(
                    color: scheme.accent,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      side: BorderSide.none,
                    ),
                  ),
                ),
              ),
              // 标签层（透明，仅文字）
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => onChanged(i),
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: TypeScale.label,
                                  fontWeight: i == selectedIndex
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: i == selectedIndex
                                      ? scheme.onPrimary
                                      : scheme.secondaryText,
                                ),
                              ),
                              if (counts.length > i) ...[
                                const SizedBox(width: 5),
                                Text(
                                  '${counts[i]}',
                                  style: TextStyle(
                                    fontSize: TypeScale.caption,
                                    fontWeight: FontWeight.w500,
                                    color: i == selectedIndex
                                        ? scheme.onPrimary.withValues(alpha: 0.8)
                                        : scheme.secondaryText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────
// 底部导航
// ────────────────────────────────────────────

// ────────────────────────────────────────────
// 统计块
// ────────────────────────────────────────────

/// 大数字 + 说明文字。用于仪表盘类的统计展示。
class StatBlock extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;
  final IconData? icon;

  const StatBlock({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: scheme.secondaryText),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: TypeScale.caption,
                color: scheme.secondaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: TypeScale.display,
            fontWeight: FontWeight.w700,
            color: valueColor ?? scheme.primaryText,
            height: 1.05,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }
}

/// 小号统计（横向三格）。对应参考设计的底部三个数字块。
class CompactStats extends StatelessWidget {
  final List<(String value, String label)> items;

  const CompactStats({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.lg,
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(width: 1, height: 30, color: scheme.hairline),
            Expanded(
              child: Column(
                children: [
                  Text(
                    items[i].$1,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: scheme.primaryText,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    items[i].$2,
                    style: TextStyle(
                      fontSize: TypeScale.caption,
                      color: scheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
