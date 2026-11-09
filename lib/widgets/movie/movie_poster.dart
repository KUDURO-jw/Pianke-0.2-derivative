// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/config/design_tokens.dart';

/// A shared, bounded-decode poster. Badges and labels never join its Hero flight.
///
/// 三个加载期细节：
/// - 渐显而不是「啪」地出现：时长走 [Motion]，减少动效时为零；
/// - 占位色优先用海报主色（[tint]），没有主色时退回中性底色；
/// - Hero 在减少动效时直接跳过，避免系统动画开关被绕过。
class MoviePoster extends StatelessWidget {
  final String url;
  final String? heroTag;
  final double radius;

  /// 海报主色（来自 T7 的 `poster_color`）。为 null 时用中性占位色。
  final Color? tint;

  const MoviePoster({
    super.key,
    required this.url,
    this.heroTag,
    this.radius = 16,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = tint ?? SurfaceLevel.inset.colorOf(scheme);

    // 有主色时用主色压暗一点做底，避免亮色海报在加载瞬间刺眼；
    // 没有主色时保持原来的中性灰块 + 弱图标。
    Widget placeholder() {
      if (tint != null) {
        return ColoredBox(
          color: Color.alphaBlend(Colors.black.withValues(alpha: 0.12), base),
        );
      }
      return ColoredBox(
        color: base,
        child: Icon(
          Icons.movie_outlined,
          size: 30,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      );
    }

    final poster = ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder()
          : CachedNetworkImage(
              imageUrl: url,
              httpHeaders: ApiConfig.imageHeaders,
              fit: BoxFit.cover,
              memCacheWidth: 300,
              maxWidthDiskCache: 300,
              // 渐显：图片就位时淡入，而不是瞬间替换占位色。
              fadeInDuration: Motion.of(context, Motion.normal),
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            ),
    );
    if (heroTag == null ||
        url.isEmpty ||
        MediaQuery.disableAnimationsOf(context)) {
      return poster;
    }
    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: true,
      flightShuttleBuilder: (_, animation, direction, from, to) =>
          (direction == HeroFlightDirection.push
                  ? to.widget as Hero
                  : from.widget as Hero)
              .child,
      child: poster,
    );
  }
}
