// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/continuous_rrect.dart';

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

class DockMetrics {
  const DockMetrics._();

  static double heightOf(BuildContext context) =>
      62 + math.max(0, MediaQuery.textScalerOf(context).scale(11) - 11);

  static double bottomOf(BuildContext context) =>
      math.max(18, MediaQuery.viewPaddingOf(context).bottom);

  static double insetOf(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom > 0
      ? 0
      : heightOf(context) + bottomOf(context) + 16;
}

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
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    final shape = const ContinuousRRect.all(Radii.pill);

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(21, 8, 21, DockMetrics.bottomOf(context)),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: dark ? scheme.blockSurface : scheme.cardSurface,
                  shape: shape,
                  shadows: Shadows.floating(scheme),
                ),
                child: SizedBox(
                  height: DockMetrics.heightOf(context),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemWidth = constraints.maxWidth / items.length;
                        return Stack(
                          children: [
                            AnimatedPositionedDirectional(
                              duration: duration,
                              curve: Motion.emphasized,
                              start: currentIndex * itemWidth,
                              top: 0,
                              bottom: 0,
                              width: itemWidth,
                              child: DecoratedBox(
                                decoration: ShapeDecoration(
                                  color: dark
                                      ? scheme.insetSurface
                                      : scheme.blockSurface,
                                  shape: shape,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (var i = 0; i < items.length; i++)
                                  Expanded(
                                    child: _DockItem(
                                      data: items[i],
                                      selected: currentIndex == i,
                                      duration: duration,
                                      onTap: () {
                                        if (currentIndex != i) {
                                          HapticFeedback.selectionClick();
                                        }
                                        onSelected(i);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatefulWidget {
  final NavItemData data;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  const _DockItem({
    required this.data,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.selected ? scheme.accent : scheme.secondaryText;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.data.label,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            containedInkWell: true,
            customBorder: const ContinuousRRect.all(Radii.pill),
            splashColor: Colors.transparent,
            highlightColor: scheme.onSurface.withValues(alpha: 0.04),
            child: AnimatedScale(
              scale: _pressed ? 1.06 : 1,
              duration: widget.duration,
              curve: Motion.standard,
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: widget.duration,
                      child: Icon(
                        widget.selected
                            ? widget.data.selectedIcon
                            : widget.data.icon,
                        key: ValueKey(widget.selected),
                        size: 26,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.25,
                        fontWeight: widget.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
