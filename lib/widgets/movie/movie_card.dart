// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/widgets/movie/movie_poster.dart';
import 'package:random_movie/models/movie.dart';
import 'package:random_movie/services/watch_status.dart';

/// 影片卡片组件，带点击缩放动效
class MovieCard extends StatefulWidget {
  final Movie movie;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool showWatchedBadge;
  final String? posterHeroTag;
  final Widget? posterAction;

  const MovieCard({
    super.key,
    required this.movie,
    this.onTap,
    this.onDelete,
    this.showWatchedBadge = true,
    this.posterHeroTag,
    this.posterAction,
  });

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard>
    with SingleTickerProviderStateMixin {
  bool _reduceMotion = false;
  late final AnimationController _scale = AnimationController(
    vsync: this,
    lowerBound: 0.975,
    upperBound: 1,
    value: 1,
    duration: const Duration(milliseconds: 90),
  );

  void _setPressed(bool pressed) {
    if (!mounted) return;
    final target = pressed ? 0.975 : 1.0;
    if (_reduceMotion) {
      _scale.value = target;
    } else {
      _scale.animateTo(target, curve: Curves.easeOut);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
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
        onTapDown: widget.onTap != null ? (_) => _setPressed(true) : null,
        onTapUp: widget.onTap != null ? (_) => _setPressed(false) : null,
        onTapCancel: widget.onTap != null ? () => _setPressed(false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onDelete == null
            ? null
            : () {
                _setPressed(false);
                widget.onDelete!();
              },
        child: ScaleTransition(
          scale: _scale,
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
                      MoviePoster(
                        url: movie.poster,
                        heroTag: widget.posterHeroTag,
                        radius: AppTheme.radiusLarge,
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
                      if (widget.posterAction != null)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: widget.posterAction!,
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
