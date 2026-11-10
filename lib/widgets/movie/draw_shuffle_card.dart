// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/movie.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';

/// Shared shuffle card used by draw animations.
///
/// Displays a movie poster + title inside a glass container with
/// instant image rendering (no fade-in delay) for smooth rapid switching.
///
/// 洗牌时每张卡带一点纵向位移（[shuffleCount] 的奇偶决定方向），
/// 让「换卡」看起来是从一个方向流过去，而不是原地闪烁。
class DrawShuffleCard extends StatelessWidget {
  final Movie movie;
  final int shuffleCount;

  const DrawShuffleCard({
    super.key,
    required this.movie,
    required this.shuffleCount,
  });

  /// 单张卡的纵向漂移量（dp）。够小不撑破布局，够大能被眼睛捕捉到。
  static const double _drift = 12;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 方向恒定向下：卡池在「往下抽」，结果从顶部被抽出来。
    final offsetY = (shuffleCount.isEven ? -1 : 1) * _drift * 0.5;

    return Transform.translate(
      offset: Offset(0, offsetY),
      child: SizedBox(
        key: ValueKey(movie.id + shuffleCount.toString()),
        width: 200,
        height: 320,
        child: SoftContainer(
          padding: const EdgeInsets.all(8),
          borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
          child: Column(
            children: [
              Expanded(
                child: ClipRSuperellipse(
                  clipBehavior: Clip.hardEdge,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: movie.poster.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: movie.poster,
                          httpHeaders: ApiConfig.imageHeaders,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          // Disable fade-in so images render instantly from cache
                          // during rapid shuffles
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholderFadeInDuration: Duration.zero,
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Center(child: Icon(Icons.movie, size: 48)),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
