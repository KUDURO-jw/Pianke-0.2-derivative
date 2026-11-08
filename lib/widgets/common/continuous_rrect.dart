// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 连续圆角，保留原组件接口，使用 Flutter 原生超椭圆路径。
class ContinuousRRect extends OutlinedBorder {
  /// 圆角半径。
  final double radius;

  /// 平滑度：0 = 正圆角，1 = 最大连续曲率。
  final double smoothing;

  final bool topLeft;
  final bool topRight;
  final bool bottomRight;
  final bool bottomLeft;

  @override
  // ignore: overridden_fields
  final BorderSide side;

  const ContinuousRRect({
    required this.radius,
    this.smoothing = 0.6,
    this.topLeft = true,
    this.topRight = true,
    this.bottomRight = true,
    this.bottomLeft = true,
    this.side = BorderSide.none,
  });

  const ContinuousRRect.all(
    double radius, {
    double smoothing = 0.6,
    BorderSide side = BorderSide.none,
  }) : this(radius: radius, smoothing: smoothing, side: side);

  const ContinuousRRect.top(
    double radius, {
    double smoothing = 0.6,
    BorderSide side = BorderSide.none,
  }) : this(
         radius: radius,
         smoothing: smoothing,
         bottomLeft: false,
         bottomRight: false,
         side: side,
       );

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect.deflate(side.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _buildPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(
      _buildPath(rect.deflate(side.strokeInset / 2)),
      side.toPaint(),
    );
  }

  @override
  ShapeBorder scale(double t) => ContinuousRRect(
    radius: radius * t,
    smoothing: smoothing,
    topLeft: topLeft,
    topRight: topRight,
    bottomRight: bottomRight,
    bottomLeft: bottomLeft,
    side: side.scale(t),
  );

  @override
  OutlinedBorder copyWith({BorderSide? side}) => ContinuousRRect(
    radius: radius,
    smoothing: smoothing,
    topLeft: topLeft,
    topRight: topRight,
    bottomRight: bottomRight,
    bottomLeft: bottomLeft,
    side: side ?? this.side,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is ContinuousRRect) {
      return ContinuousRRect(
        radius: lerpDouble(a.radius, radius, t)!,
        smoothing: lerpDouble(a.smoothing, smoothing, t)!,
        side: BorderSide.lerp(a.side, side, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is ContinuousRRect) {
      return ContinuousRRect(
        radius: lerpDouble(radius, b.radius, t)!,
        smoothing: lerpDouble(smoothing, b.smoothing, t)!,
        side: BorderSide.lerp(side, b.side, t),
      );
    }
    return super.lerpTo(b, t);
  }

  Path _buildPath(Rect rect) {
    return RoundedSuperellipseBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(topLeft ? radius : 0),
        topRight: Radius.circular(topRight ? radius : 0),
        bottomRight: Radius.circular(bottomRight ? radius : 0),
        bottomLeft: Radius.circular(bottomLeft ? radius : 0),
      ),
    ).getOuterPath(rect);
  }
}

/// 连续圆角的输入框边框（[InputDecoration] 要求 [InputBorder] 类型）。
class ContinuousInputBorder extends InputBorder {
  final double radius;
  final double smoothing;

  const ContinuousInputBorder({
    required this.radius,
    this.smoothing = 0.6,
    super.borderSide = BorderSide.none,
  });

  const ContinuousInputBorder.all(
    double radius, {
    double smoothing = 0.6,
    BorderSide borderSide = BorderSide.none,
  }) : this(radius: radius, smoothing: smoothing, borderSide: borderSide);

  @override
  InputBorder copyWith({BorderSide? borderSide, bool? isOutline}) =>
      ContinuousInputBorder(
        radius: radius,
        smoothing: smoothing,
        borderSide: borderSide ?? this.borderSide,
      );

  @override
  bool get isOutline => false;

  @override
  ShapeBorder scale(double t) => ContinuousInputBorder(
    radius: radius * t,
    smoothing: smoothing,
    borderSide: borderSide.scale(t),
  );

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.strokeInset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect.deflate(borderSide.strokeInset));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none) return;
    canvas.drawPath(
      _shape.getOuterPath(rect.deflate(borderSide.strokeInset / 2)),
      borderSide.toPaint(),
    );
  }

  ContinuousRRect get _shape =>
      ContinuousRRect(radius: radius, smoothing: smoothing, side: borderSide);

  @override
  bool operator ==(Object other) =>
      other is ContinuousInputBorder &&
      other.radius == radius &&
      other.smoothing == smoothing &&
      other.borderSide == borderSide;

  @override
  int get hashCode => Object.hash(radius, smoothing, borderSide);
}

/// 便捷扩展：把圆角数转成连续圆角形状。
extension ContinuousRadiusExt on double {
  ShapeBorder get squircle => ContinuousRRect.all(this);
}
