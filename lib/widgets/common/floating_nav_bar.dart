// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

class FloatingNavBar extends StatefulWidget {
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
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<FloatingNavBar> {
  double? _dragPosition;
  VelocityTracker? _gestureTracker;
  double? _releaseVelocity;

  void _select(int index) {
    if (index != widget.currentIndex) {
      HapticFeedback.selectionClick();
      widget.onSelected(index);
    }
  }

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
                  shape: shape,
                  shadows: Shadows.floating(scheme),
                ),
                child: ClipPath(
                  clipper: ShapeBorderClipper(shape: shape),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: (dark ? scheme.blockSurface : scheme.cardSurface)
                            .withValues(alpha: dark ? 0.78 : 0.65),
                        shape: ContinuousRRect.all(
                          Radii.pill,
                          side: BorderSide(
                            color: Colors.white.withValues(
                              alpha: dark ? 0.12 : 0.65,
                            ),
                          ),
                        ),
                      ),
                      child: SizedBox(
                        height: DockMetrics.heightOf(context),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final itemWidth =
                                  constraints.maxWidth / widget.items.length;
                              double position(double x) {
                                final logicalX =
                                    Directionality.of(context) ==
                                        TextDirection.rtl
                                    ? constraints.maxWidth - x
                                    : x;
                                return (logicalX / itemWidth - 0.5).clamp(
                                  0.0,
                                  (widget.items.length - 1).toDouble(),
                                );
                              }

                              void finishDrag(DragEndDetails details) {
                                final position = _dragPosition;
                                if (position == null) return;
                                final direction =
                                    Directionality.of(context) ==
                                        TextDirection.rtl
                                    ? -1
                                    : 1;
                                final velocity =
                                    (_releaseVelocity ??
                                        _gestureTracker
                                            ?.getVelocity()
                                            .pixelsPerSecond
                                            .dx ??
                                        details.primaryVelocity ??
                                        0) *
                                    direction;
                                final releaseIndex = position.round();
                                // A flick may carry the selection one neighbour beyond
                                // the finger, never skip across the whole dock.
                                final projectedIndex =
                                    (position + velocity * 0.1 / itemWidth)
                                        .round();
                                final carry = (projectedIndex - releaseIndex)
                                    .clamp(-1, 1);
                                var target = releaseIndex + carry;
                                target = target.clamp(
                                  0,
                                  widget.items.length - 1,
                                );
                                setState(() => _dragPosition = null);
                                _select(target);
                              }

                              return Listener(
                                onPointerDown: (event) {
                                  _releaseVelocity = null;
                                  _gestureTracker =
                                      VelocityTracker.withKind(event.kind)
                                        ..addPosition(
                                          event.timeStamp,
                                          event.localPosition,
                                        );
                                },
                                onPointerMove: (event) =>
                                    _gestureTracker?.addPosition(
                                      event.timeStamp,
                                      event.localPosition,
                                    ),
                                onPointerUp: (_) {
                                  _releaseVelocity = _gestureTracker
                                      ?.getVelocity()
                                      .pixelsPerSecond
                                      .dx;
                                  _gestureTracker = null;
                                },
                                onPointerCancel: (_) => _gestureTracker = null,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragStart: (details) =>
                                      setState(() {
                                        _dragPosition = position(
                                          details.localPosition.dx,
                                        );
                                      }),
                                  onHorizontalDragUpdate: (details) =>
                                      setState(() {
                                        _dragPosition = position(
                                          details.localPosition.dx,
                                        );
                                      }),
                                  onHorizontalDragEnd: finishDrag,
                                  onHorizontalDragCancel: () =>
                                      setState(() => _dragPosition = null),
                                  child: Stack(
                                    children: [
                                      AnimatedPositionedDirectional(
                                        duration: _dragPosition == null
                                            ? duration
                                            : Duration.zero,
                                        curve: Motion.emphasized,
                                        start:
                                            (_dragPosition ??
                                                widget.currentIndex
                                                    .toDouble()) *
                                            itemWidth,
                                        top: 0,
                                        bottom: 0,
                                        width: itemWidth,
                                        child: DecoratedBox(
                                          decoration: ShapeDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Colors.white.withValues(
                                                  alpha: dark ? 0.22 : 0.9,
                                                ),
                                                scheme.blockSurface.withValues(
                                                  alpha: 0.45,
                                                ),
                                              ],
                                            ),
                                            shape: ContinuousRRect.all(
                                              Radii.pill,
                                              side: BorderSide(
                                                color: Colors.white.withValues(
                                                  alpha: dark ? 0.22 : 0.85,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          for (
                                            var i = 0;
                                            i < widget.items.length;
                                            i++
                                          )
                                            Expanded(
                                              child: _DockItem(
                                                data: widget.items[i],
                                                selected:
                                                    (_dragPosition?.round() ??
                                                        widget.currentIndex) ==
                                                    i,
                                                duration: duration,
                                                onTap: () {
                                                  _select(i);
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
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
