// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/models/movie.dart';
import 'package:random_movie/services/watch_status.dart';

/// 影片卡片组件，带点击缩放动效
class MovieCard extends StatefulWidget {
  final Movie movie;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool showWatchedBadge;

  const MovieCard({
    super.key,
    required this.movie,
    this.onTap,
    this.onDelete,
    this.showWatchedBadge = true,
  });

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  bool _isPressed = false;

  /// 性能说明：原实现在 initState 里无条件 addPostFrameCallback 再 setState，
  /// 让**每张卡片首帧都额外重建一次**。列表近百部影片时成批触发，是掉帧来源之一。
  /// 现在海报直接在首帧渲染，依靠 CachedNetworkImage 自身的占位与淡入，
  /// 不再需要额外的 setState 驱动。
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final movie = widget.movie;
    final isSeries = movie.subjectType == MovieSubjectType.tvSeries;
    final totalEpisodes = movie.episodes.length;
    final watchedEpisodes = movie.episodes
        .where((episode) => episode.watched)
        .length;
    final hasEpisodeProgress = isSeries && totalEpisodes > 0;
    final progressValue = hasEpisodeProgress
        ? watchedEpisodes / totalEpisodes
        : 0.0;
    final statusLabel = hasEpisodeProgress
        ? '$watchedEpisodes/$totalEpisodes'
        : (WatchStatus.isWatched(movie) ? '已看' : '未看');
    final statusBackground = hasEpisodeProgress
        ? (watchedEpisodes == totalEpisodes
              ? colorScheme.primary
              : Colors.black.withValues(alpha: 0.66))
        : (WatchStatus.isWatched(movie)
              ? colorScheme.primary
              : Colors.black.withValues(alpha: 0.66));

    return RepaintBoundary(
      child: GestureDetector(
        onTapDown: widget.onTap != null
            ? (_) => setState(() => _isPressed = true)
            : null,
        onTapUp: widget.onTap != null
            ? (_) => setState(() => _isPressed = false)
            : null,
        onTapCancel: widget.onTap != null
            ? () => setState(() => _isPressed = false)
            : null,
        onTap: widget.onTap,
        onLongPress: widget.onDelete == null
            ? null
            : () {
                setState(() => _isPressed = false);
                widget.onDelete!();
              },
        child: AnimatedScale(
          scale: _isPressed ? 0.975 : 1.0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRSuperellipse(
                  clipBehavior: Clip.hardEdge,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (movie.poster.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: movie.poster,
                          httpHeaders: ApiConfig.imageHeaders,
                          fit: BoxFit.cover,
                          // 性能：限制解码尺寸，避免按原图（常见 1000px+）解码，
                          // 这是滚动时最大的内存与解码开销来源。
                          memCacheWidth: 300,
                          maxWidthDiskCache: 300,
                          fadeInDuration: const Duration(milliseconds: 120),
                          placeholder: (_, _) => ColoredBox(
                            color: SurfaceLevel.inset.colorOf(colorScheme),
                          ),
                          errorWidget: (_, _, _) => ColoredBox(
                            color: SurfaceLevel.inset.colorOf(colorScheme),
                            child: Icon(
                              Icons.movie_outlined,
                              size: 30,
                              color: colorScheme.secondaryText,
                            ),
                          ),
                        )
                      else
                        ColoredBox(
                          color: SurfaceLevel.inset.colorOf(colorScheme),
                          child: Icon(
                            Icons.movie_outlined,
                            size: 30,
                            color: colorScheme.secondaryText,
                          ),
                        ),
                      if (widget.showWatchedBadge)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: statusBackground,
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide.none,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasEpisodeProgress) ...[
                                    const Icon(
                                      Icons.tv_rounded,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    statusLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (movie.rating > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: Colors.black.withValues(alpha: 0.66),
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide.none,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star,
                                    size: 14,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    movie.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              if (movie.year.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  movie.year,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
              if (hasEpisodeProgress) ...[
                const SizedBox(height: 6),
                ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 5,
                    backgroundColor: colorScheme.onSurface.withValues(
                      alpha: 0.10,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
