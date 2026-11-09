// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:random_movie/models/movie.dart';

/// 海报占位色。
///
/// 加载中如果只给一块中性灰，视觉上是「空的」；给一块接近海报的色块，
/// 观感会连成一体。取色有两个来源：
///
/// 1. **已存主色**：`movie.posterColor`。这是真正的「海报主色」，
///    需要在下载海报时解码取平均色（属 T7 海报本地化的范围）。
/// 2. **派生色**：没有存过主色时，用海报地址算一个稳定的色相。
///
/// 派生色**不是**海报的真实颜色，只是「同一部影片每次都是同一个颜色」，
/// 用来避免占位块一律是死灰块。T7 落地后第 1 条会自然接管，
/// 无需改动任何调用方。
abstract final class PosterTint {
  /// 取某部影片的占位色；没有海报时返回 null（调用方退回中性底色）。
  static Color? of(Movie movie) {
    final stored = movie.posterColor;
    if (stored != null) return _fromArgb(stored);
    final seed = movie.poster.isNotEmpty ? movie.poster : movie.id;

    // 没有海报也没有 id：交给调用方用中性色，别凭空造色。
    if (seed.isEmpty) return null;
    return derived(seed);
  }

  /// 由任意稳定的字符串派生出稳定的低饱和色。
  ///
  /// 饱和度与亮度刻意压低（S≈0.34 / L≈0.46），这样它只当背景，
  /// 不会抢标题文字的对比度，也不会在暗色主题下刺眼。
  static Color derived(String seed) {
    var hash = 0x811C9DC5; // FNV-1a 32 位
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.34, 0.46).toColor();
  }

  static Color _fromArgb(int value) => Color(value);
}
