import 'package:flutter/material.dart';
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
    this.shadow = true,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MellowPanel(
      color: color ?? scheme.cardSurface,
      radius: radius,
      border: border ?? BorderSide(color: scheme.hairline),
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
      decoration: BoxDecoration(
        color: scheme.blockSurface,
        borderRadius: BorderRadius.circular(Radii.lg),
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
      padding: padding ??
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
          if (trailing != null) trailing!,
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
  final String hint;
  final VoidCallback? onClear;
  final bool hasText;

  const AppSearchField({
    super.key,
    required this.controller,
    this.onChanged,
    this.hint = '搜索',
    this.onClear,
    this.hasText = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: scheme.cardSurface,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: scheme.hairline),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
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
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: scheme.secondaryText,
                  onPressed: onClear,
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
class SegmentedSwitch extends StatelessWidget {
  final List<String> labels;
  final List<int> counts;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const SegmentedSwitch({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.counts = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SurfaceLevel.inset.colorOf(scheme),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: Motion.normal,
                  curve: Motion.emphasized,
                  decoration: BoxDecoration(
                    color: i == selectedIndex
                        ? (isDark ? SurfaceLevel.block.colorOf(scheme) : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    boxShadow: i == selectedIndex && !isDark
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
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
                              ? scheme.primaryText
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
                            color: scheme.secondaryText,
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
    );
  }
}

// ────────────────────────────────────────────
// 底部导航
// ────────────────────────────────────────────

class NavItemData {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const NavItemData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 悬浮底部导航条。
///
/// 形态参照目标设计：不贴屏幕底边、整条胶囊、选中项图标有胶囊底色、
/// 图标在上文字在下（横排图标+文字在 4 项时会溢出）。
class FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<NavItemData> items;

  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        bottomInset > 0 ? bottomInset * 0.55 : Spacing.md,
      ),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: scheme.cardSurface,
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: Shadows.floating(scheme),
          border: Border.all(color: scheme.hairline),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: 6,
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _NavItem(
                  data: items[i],
                  selected: i == currentIndex,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final NavItemData data;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.accent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: Motion.normal,
            curve: Motion.emphasized,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Icon(
              selected ? data.selectedIcon : data.icon,
              size: 21,
              color: selected ? accent : scheme.secondaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? accent : scheme.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

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
            if (i > 0)
              Container(
                width: 1,
                height: 30,
                color: scheme.hairline,
              ),
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
