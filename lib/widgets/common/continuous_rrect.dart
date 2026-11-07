import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 连续圆角（超椭圆 / squircle）形状。
///
/// ── 数学 ──
/// 超椭圆 |x|^n + |y|^n = 1 的参数化：
///   x = cos^(2/n)(θ),  y = sin^(2/n)(θ)，θ ∈ [0, π/2]
///
/// 对每个角，设圆心为 C，a、b 为指向两个切点的单位向量（互相垂直），则
///   P(θ) = C + r · [ a·cos^(2/n)(θ) + b·sin^(2/n)(θ) ]
/// θ=0 得到 C + r·a（第一个切点），θ=π/2 得到 C + r·b（第二个切点）。
///
/// 四角只是换 a、b 的方向，曲线形状一致，因此不会出现方向错乱或多画的凹口。
class ContinuousRRect extends OutlinedBorder {
  /// 圆角半径。
  final double radius;

  /// 平滑度：0 = 正圆角，1 = 最大连续曲率。
  final double smoothing;

  final bool topLeft;
  final bool topRight;
  final bool bottomRight;
  final bool bottomLeft;

  // ignore: overridden_fields
  @override
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

  /// 路径缓存。
  ///
  /// 关键：必须能容纳**多种不同尺寸**的矩形同时存在。
  /// 上一版只留 1 条（`..clear()..[key] = built`），而屏幕上一屏就有
  /// 十几种不同大小的卡片/输入框，导致每次取都错过、每次都要重算，
  /// 缓存等于完全失效，这是滚动掉帧的主因之一。
  static final Map<int, Path> _cache = <int, Path>{};
  static const int _cacheLimit = 64;

  Path _buildPath(Rect rect) {
    if (rect.isEmpty) return Path();

    final key = Object.hash(
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
      radius,
      smoothing,
      topLeft,
      topRight,
      bottomRight,
      bottomLeft,
    );
    final hit = _cache[key];
    if (hit != null) return hit;

    final built = _sample(rect);
    // 超限时整体清空：比 LRU 便宜，且命中率损失很小。
    if (_cache.length >= _cacheLimit) _cache.clear();
    _cache[key] = built;
    return built;
  }

  Path _sample(Rect rect) {
    final path = Path();
    final maxRadius = math.min(rect.width, rect.height) / 2;
    final r = radius.clamp(0.0, maxRadius);

    if (r <= 0.01) {
      path.addRect(rect);
      return path;
    }

    final n = 2.0 + 2.0 * smoothing.clamp(0.0, 1.0);
    final l = rect.left;
    final t = rect.top;
    final right = rect.right;
    final bottom = rect.bottom;

    path.moveTo(topLeft ? l + r : l, t);

    if (topRight) {
      path.lineTo(right - r, t);
      _corner(path, right - r, t + r, r, n, 0, -1, 1, 0);
    } else {
      path.lineTo(right, t);
    }

    if (bottomRight) {
      path.lineTo(right, bottom - r);
      _corner(path, right - r, bottom - r, r, n, 1, 0, 0, 1);
    } else {
      path.lineTo(right, bottom);
    }

    if (bottomLeft) {
      path.lineTo(l + r, bottom);
      _corner(path, l + r, bottom - r, r, n, 0, 1, -1, 0);
    } else {
      path.lineTo(l, bottom);
    }

    if (topLeft) {
      path.lineTo(l, t + r);
      _corner(path, l + r, t + r, r, n, -1, 0, 0, -1);
    } else {
      path.lineTo(l, t);
    }

    path.close();
    return path;
  }

  /// 追加一个角。跳过 θ=0（调用方已 lineTo 到该切点）。
  void _corner(
    Path path,
    double cx,
    double cy,
    double r,
    double n,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    const steps = 12;
    final power = 2.0 / n;
    for (var i = 1; i <= steps; i++) {
      final theta = (math.pi / 2) * (i / steps);
      final c = math.pow(math.cos(theta), power).toDouble();
      final s = math.pow(math.sin(theta), power).toDouble();
      path.lineTo(cx + r * (ax * c + bx * s), cy + r * (ay * c + by * s));
    }
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

  ContinuousRRect get _shape => ContinuousRRect(
    radius: radius,
    smoothing: smoothing,
    side: borderSide,
  );

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
