// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/services/haptics.dart';
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
  final ValueChanged<int>? onDoubleTap;
  final List<NavItemData> items;

  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.onDoubleTap,
    required this.items,
  }) : assert(items.length > 0);

  @override
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<FloatingNavBar>
    with SingleTickerProviderStateMixin {
  // 对齐 FlClash dock 的按压膨胀：按下整体放大，松开回弹。
  static final SpringDescription _swellSpring =
      SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 311,
        ratio: 0.593,
      );
  // 最长边（dock 高度 62 + 内边距）约 70dp，固定增量约 8dp → 1.11。
  static const double _growth = 0.11;

  late final AnimationController _swell = AnimationController(
    vsync: this,
    duration: Motion.page,
    lowerBound: 0.0,
    upperBound: 1.0,
  );

  @override
  void dispose() {
    _swell.dispose();
    super.dispose();
  }

  void _pressStart() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _swell.animateTo(1.0, curve: Motion.fade);
  }

  void _pressEnd() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _swell.animateWith(SpringSimulation(_swellSpring, _swell.value, 0, 0));
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final shape = const ContinuousRRect.all(Radii.pill);
    // Glass, clipping and shadow stay outside the per-frame animation builder.
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(21, 8, 21, DockMetrics.bottomOf(context)),
        child: Center(
          heightFactor: 1,
          child: AnimatedBuilder(
            animation: _swell,
            builder: (context, child) {
              final scale = 1 + _swell.value * _growth;
              return Transform.scale(scale: scale, child: child);
            },
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
                          color: (dark
                                  ? scheme.blockSurface
                                  : scheme.cardSurface)
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
                            child: _DockTrack(
                              currentIndex: widget.currentIndex,
                              onSelected: widget.onSelected,
                              onDoubleTap: widget.onDoubleTap,
                              items: widget.items,
                              onPressStart: _pressStart,
                              onPressEnd: _pressEnd,
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
      ),
    );
  }
}

class _DockTrack extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<int>? onDoubleTap;
  final List<NavItemData> items;
  final VoidCallback? onPressStart;
  final VoidCallback? onPressEnd;
  const _DockTrack({
    required this.currentIndex,
    required this.onSelected,
    required this.onDoubleTap,
    required this.items,
    this.onPressStart,
    this.onPressEnd,
  });

  @override
  State<_DockTrack> createState() => _DockTrackState();
}

class _DockTrackState extends State<_DockTrack> with TickerProviderStateMixin {
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.currentIndex.toDouble(),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: Motion.settle,
    reverseDuration: Motion.fast,
  );
  final ValueNotifier<int?> _pressedIndex = ValueNotifier(null);
  late final Listenable _motion = Listenable.merge([
    _position,
    _press,
    _pressedIndex,
  ]);
  VelocityTracker? _tracker;
  double? _releaseVelocity;
  double _target = 0;
  bool _dragging = false;
  bool _cancelled = false;
  int? _lastHapticIndex;
  int? _lastTapIndex;
  Duration? _lastTapTime;
  Duration _pointerDownTime = Duration.zero;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _target = widget.currentIndex.toDouble();
    _position.addStatusListener((status) {
      if (status == AnimationStatus.completed) _position.value = _target;
    });
    _press.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _pressedIndex.value = null;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _position.value = widget.currentIndex.toDouble();
      _press.value = _pressedIndex.value == null ? 0 : 1;
    }
  }

  @override
  void didUpdateWidget(covariant _DockTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex &&
        !_dragging &&
        _target != widget.currentIndex.toDouble()) {
      _settle(widget.currentIndex);
    }
  }

  void _settle(int index, [double velocity = 0]) {
    _target = index.toDouble();
    if (_reduceMotion) {
      _position.value = _target;
    } else {
      _position.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 350, damping: 30),
          _position.value,
          _target,
          velocity.clamp(-8.0, 8.0),
          tolerance: const Tolerance(distance: 0.001, velocity: 0.001),
        ),
      );
    }
  }

  void _select(int index, {bool haptic = true}) {
    _settle(index);
    if (index != widget.currentIndex) {
      if (haptic) Haptics.selection();
      widget.onSelected(index);
    }
  }

  void _releasePress() {
    if (_reduceMotion || _press.value == 0) {
      _pressedIndex.value = null;
      _press.value = 0;
    } else {
      _press.reverse();
    }
  }

  void _handleTap(int index) {
    // Recognize the second tap without delaying the first tap's navigation.
    // Pointer timestamps also keep this independent of wall-clock changes.
    final elapsed = _lastTapTime == null
        ? null
        : _pointerDownTime - _lastTapTime!;
    final doubleTap =
        widget.onDoubleTap != null &&
        index == widget.currentIndex &&
        _lastTapIndex == index &&
        elapsed != null &&
        elapsed >= Duration.zero &&
        elapsed <= kDoubleTapTimeout;
    if (doubleTap) {
      _lastTapIndex = null;
      _lastTapTime = null;
      widget.onDoubleTap!(index);
    } else {
      _lastTapIndex = index;
      _lastTapTime = _pointerDownTime;
      _select(index);
    }
  }

  @override
  void dispose() {
    _position.dispose();
    _press.dispose();
    _pressedIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / widget.items.length;
        double position(double x) =>
            ((rtl ? constraints.maxWidth - x : x) / itemWidth - 0.5).clamp(
              0.0,
              (widget.items.length - 1).toDouble(),
            );
        void dragTo(double x) {
          final next = position(x);
          final index = next.round();
          _position.value = next;
          _pressedIndex.value = index;
          if (_lastHapticIndex != index) {
            Haptics.selection();
            _lastHapticIndex = index;
          }
        }

        void cancel() {
          if (_dragging) {
            _lastTapIndex = null;
            _lastTapTime = null;
          }
          _cancelled = true;
          _dragging = false;
          _tracker = null;
          _releaseVelocity = null;
          _releasePress();
          _settle(widget.currentIndex);
        }

        return Listener(
          onPointerDown: (event) {
            _pointerDownTime = event.timeStamp;
            _cancelled = false;
            _releaseVelocity = null;
            _lastHapticIndex = position(event.localPosition.dx).round();
            _pressedIndex.value = _lastHapticIndex;
            _tracker = VelocityTracker.withKind(event.kind)
              ..addPosition(event.timeStamp, event.localPosition);
            if (_reduceMotion) {
              _press.value = 1;
            } else {
              _press.forward();
            }
            widget.onPressStart?.call();
          },
          onPointerMove: (event) =>
              _tracker?.addPosition(event.timeStamp, event.localPosition),
          onPointerUp: (_) {
            _releaseVelocity = _tracker?.getVelocity().pixelsPerSecond.dx;
            _tracker = null;
            _releasePress();
            widget.onPressEnd?.call();
          },
          onPointerCancel: (_) {
            widget.onPressEnd?.call();
            cancel();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              _lastTapIndex = null;
              _lastTapTime = null;
              _dragging = true;
              dragTo(details.localPosition.dx);
            },
            onHorizontalDragUpdate: (details) =>
                dragTo(details.localPosition.dx),
            onHorizontalDragCancel: cancel,
            onHorizontalDragEnd: (details) {
              if (_cancelled) return;
              final velocity =
                  (_releaseVelocity ??
                      _tracker?.getVelocity().pixelsPerSecond.dx ??
                      details.primaryVelocity ??
                      0) *
                  (rtl ? -1 : 1);
              final releaseIndex = _position.value.round();
              final projected = (_position.value + velocity * 0.1 / itemWidth)
                  .round();
              final target =
                  (releaseIndex + (projected - releaseIndex).clamp(-1, 1))
                      .clamp(0, widget.items.length - 1);
              _dragging = false;
              if (_lastHapticIndex != target) Haptics.selection();
              _settle(target, velocity / itemWidth);
              if (target != widget.currentIndex) widget.onSelected(target);
            },
            child: AnimatedBuilder(
              animation: _motion,
              builder: (context, _) {
                final location = _position.value.clamp(
                  0.0,
                  (widget.items.length - 1).toDouble(),
                );
                final lift = Motion.fadeIn.transform(_press.value);
                final preview = _dragging
                    ? location.round()
                    : widget.currentIndex;
                return Stack(
                  children: [
                    PositionedDirectional(
                      start: 0,
                      top: 0,
                      bottom: 0,
                      width: itemWidth,
                      child: Transform.translate(
                        offset: Offset(
                          location * itemWidth * (rtl ? -1 : 1),
                          0,
                        ),
                        child: Transform.scale(
                          key: const ValueKey('dock-lens-scale'),
                          scale: 1 + lift * 0.06,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(
                                    alpha: dark ? 0.22 : 0.9,
                                  ),
                                  scheme.blockSurface.withValues(alpha: 0.45),
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
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: widget.currentIndex == i,
                              label: widget.items[i].label,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _handleTap(i),
                                child: Transform.scale(
                                  key: ValueKey(
                                    'dock-item-scale-${widget.items[i].label}',
                                  ),
                                  scale:
                                      1 +
                                      0.09 *
                                          (1 - (location - i).abs()).clamp(
                                            0.0,
                                            1.0,
                                          ) +
                                      (_pressedIndex.value == i
                                          ? lift * 0.12
                                          : 0),
                                  child: SizedBox.expand(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Transform.translate(
                                          offset: Offset(
                                            0,
                                            -1.5 *
                                                    (1 - (location - i).abs())
                                                        .clamp(0.0, 1.0) -
                                                (_pressedIndex.value == i
                                                    ? lift * 1.5
                                                    : 0),
                                          ),
                                          child: Icon(
                                            preview == i
                                                ? widget.items[i].selectedIcon
                                                : widget.items[i].icon,
                                            size: 26,
                                            color: preview == i
                                                ? scheme.accent
                                                : scheme.secondaryText,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.items[i].label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: preview == i
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: preview == i
                                                ? scheme.accent
                                                : scheme.secondaryText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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
          ),
        );
      },
    );
  }
}
