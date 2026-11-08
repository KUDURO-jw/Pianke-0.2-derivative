// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:random_movie/services/local_data_guard.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/services/watch_status.dart';
import 'package:random_movie/widgets/movie/movie_poster.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/movie/movie_tag_editor.dart';
import 'package:random_movie/widgets/movie/viewing_session_editor.dart';
import 'package:url_launcher/url_launcher.dart';

/// 影片详情页
class MovieDetailPage extends StatefulWidget {
  final String movieId;
  final Movie? initialMovie;
  final String? posterHeroTag;

  const MovieDetailPage({
    super.key,
    required this.movieId,
    this.initialMovie,
    this.posterHeroTag,
  });

  @override
  State<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends State<MovieDetailPage> {
  static const double _detailCacheExtent = 160;
  static const double _expandedPosterHeight = 320;

  Future<Movie?>? _movieFuture;
  Movie? _seedMovie;
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeAnimationStatusListener;
  late double? _userRating;
  late bool _watched;
  late DateTime? _watchedAt;
  late TextEditingController _reviewController;
  late List<MovieEpisode> _episodes;
  List<ViewingSession> _sessions = const [];
  bool _sessionsLoading = true;
  bool _summaryExpanded = false;
  bool _initialized = false;
  Movie? _lastLoadedMovie;
  bool _hasChanges = false;
  bool _saving = false;
  bool _allowLeave = false;
  bool _exitDialogOpen = false;
  bool _isSyncingWatchState = false;
  bool _secondarySectionsReady = false;
  bool _episodeControlsReady = false;
  bool _deferredSectionsScheduled = false;

  @override
  void initState() {
    super.initState();
    _seedMovie = widget.initialMovie?.id == widget.movieId
        ? widget.initialMovie
        : context.read<MovieProvider>().peekMovieById(widget.movieId);
    // A cached film is enough for the first frame. Local refresh and records
    // wait until the route settles instead of rebuilding during Hero flight.
    if (_seedMovie == null) _movieFuture = _loadMovie();
  }

  Future<void> _loadSessions() async {
    final sessions = await context.read<MovieProvider>().sessionsForMovie(
      widget.movieId,
    );
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _sessionsLoading = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindRouteTransition();
  }

  void _bindRouteTransition() {
    final route = ModalRoute.of(context);
    final nextAnimation = route?.animation;
    if (identical(nextAnimation, _routeAnimation)) return;

    _removeRouteTransitionListener();
    _routeAnimation = nextAnimation;

    if (_deferredSectionsScheduled) return;
    if (MediaQuery.disableAnimationsOf(context) ||
        nextAnimation == null ||
        (nextAnimation.status == AnimationStatus.completed &&
            route?.offstage != true)) {
      _beginDeferredReveal();
      return;
    }

    _routeAnimationStatusListener = (status) {
      if (status != AnimationStatus.completed) return;
      // Hero measures the destination offstage with a completed animation
      // proxy. That measurement is not the end of the actual page transition.
      if (route?.offstage == true) return;
      _removeRouteTransitionListener();
      _beginDeferredReveal();
    };
    nextAnimation.addStatusListener(_routeAnimationStatusListener!);
  }

  void _beginDeferredReveal() {
    if (_deferredSectionsScheduled) return;
    _deferredSectionsScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        _secondarySectionsReady = true;
        _episodeControlsReady = true;
        if (_seedMovie != null) _movieFuture = _loadMovie(forceRefresh: true);
      });
      _loadSessions();
    });
  }

  void _removeRouteTransitionListener() {
    final animation = _routeAnimation;
    final listener = _routeAnimationStatusListener;
    if (animation != null && listener != null) {
      animation.removeStatusListener(listener);
    }
    _routeAnimationStatusListener = null;
  }

  void _initFromMovie(Movie movie) {
    if (_initialized &&
        (identical(_lastLoadedMovie, movie) ||
            _hasChanges ||
            _isSyncingWatchState)) {
      return;
    }
    _lastLoadedMovie = movie;
    _episodes = List<MovieEpisode>.from(movie.episodes);
    _userRating = movie.userRating;

    // 统一走 WatchStatus，与片库、抽片页保持同一套判定：
    // 剧集要求所有分集都看完才算已看。
    _watched = WatchStatus.isWatched(movie);
    _watchedAt = _watched ? movie.watchedAt : null;
    if (_initialized) {
      _reviewController.text = movie.userReview ?? '';
    } else {
      _reviewController = TextEditingController(text: movie.userReview ?? '');
    }
    _initialized = true;
  }

  Future<Movie?> _loadMovie({bool forceRefresh = false}) {
    return context.read<MovieProvider>().getMovieById(
      widget.movieId,
      forceRefresh: forceRefresh,
    );
  }

  @override
  void dispose() {
    LocalDataGuard.release(this);
    _removeRouteTransitionListener();
    if (_initialized) {
      _reviewController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Movie?>(
      initialData: _seedMovie,
      future: _movieFuture,
      builder: (context, snapshot) {
        final movie = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting &&
            movie == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (movie == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('影片不存在')),
          );
        }

        _initFromMovie(movie);
        final provider = context.read<MovieProvider>();
        final expandedHeight =
            _expandedPosterHeight +
            (MediaQuery.textScalerOf(context).scale(22) - 22) * 4;
        // Keep these widget identities stable as the sliver scroll offset
        // changes. Only swap the header when it actually crosses collapse.
        final expandedHeader = _buildSliverAppBar(
          context,
          movie,
          collapsed: false,
        );
        final collapsedHeader = _buildSliverAppBar(
          context,
          movie,
          collapsed: true,
        );

        return PopScope<void>(
          canPop: !_hasChanges || _allowLeave,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave(movie);
          },
          child: Scaffold(
            bottomNavigationBar: _hasChanges
                ? SafeArea(
                    minimum: const EdgeInsets.all(AppTheme.spacingMedium),
                    child: FilledButton.icon(
                      onPressed: _saving || _isSyncingWatchState
                          ? null
                          : () => _save(provider, movie),
                      icon: const Icon(Icons.check),
                      label: Text(_saving ? '保存中…' : '保存修改'),
                    ),
                  )
                : null,
            body: AbsorbPointer(
              absorbing: _saving,
              child: CustomScrollView(
                scrollCacheExtent: ScrollCacheExtent.pixels(_detailCacheExtent),
                slivers: [
                  SliverLayoutBuilder(
                    builder: (context, constraints) {
                      return constraints.scrollOffset >=
                              expandedHeight - kToolbarHeight
                          ? collapsedHeader
                          : expandedHeader;
                    },
                  ),
                  ..._buildBodySlivers(context, movie, provider),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    Movie movie, {
    required bool collapsed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surfaceContainerHighest;
    final isSeries = movie.subjectType == MovieSubjectType.tvSeries;
    final durationLabel = _formatDurationText(movie.durationText);
    final hasPoster = movie.poster.isNotEmpty;

    return SliverAppBar(
      expandedHeight:
          _expandedPosterHeight +
          (MediaQuery.textScalerOf(context).scale(22) - 22) * 4,
      pinned: true,
      backgroundColor: collapsed
          ? colorScheme.surface
          : const Color(0xFF242529),
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: collapsed ? colorScheme.onSurface : Colors.white,
      title: collapsed
          ? Text(movie.title, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      systemOverlayStyle: collapsed
          ? (colorScheme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
          : SystemUiOverlayStyle.light,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 暗化封面背景（同海报，cover 铺满）
              if (hasPoster)
                CachedNetworkImage(
                  imageUrl: movie.poster,
                  httpHeaders: ApiConfig.imageHeaders,
                  fit: BoxFit.cover,
                  // Share the decoded/cache entry with the grid and Hero.
                  memCacheWidth: 300,
                  maxWidthDiskCache: 300,
                  fadeInDuration: Duration.zero,
                  placeholder: (_, _) => ColoredBox(color: surfaceColor),
                  errorWidget: (_, _, _) => ColoredBox(color: surfaceColor),
                )
              else
                ColoredBox(
                  color: surfaceColor,
                  child: const Center(
                    child: Icon(Icons.movie, size: 72, color: Colors.white24),
                  ),
                ),
              // 顶部 + 底部渐变 scrim（返回按钮与标题可读）
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.88),
                    ],
                    stops: const [0.0, 0.35, 1.0],
                  ),
                ),
              ),
              // 底部：海报缩略卡 + 标题/元信息/评分并排
              Positioned(
                left: AppTheme.spacingMedium,
                right: AppTheme.spacingMedium,
                bottom: AppTheme.spacingMedium,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    HeroMode(
                      enabled: !collapsed,
                      child: _buildPosterThumb(
                        movie,
                        colorScheme,
                        movie.poster.isNotEmpty,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingMedium),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            movie.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.2,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingSmall),
                          Wrap(
                            spacing: AppTheme.spacingSmall,
                            runSpacing: 6,
                            children: [
                              _chipLabel(isSeries ? '剧集' : '影片'),
                              if (movie.year.isNotEmpty) _chipLabel(movie.year),
                              if (movie.region.isNotEmpty)
                                _chipLabel(movie.region),
                              if (durationLabel.isNotEmpty)
                                _chipLabel(durationLabel),
                            ],
                          ),
                          if (movie.rating > 0) ...[
                            const SizedBox(height: AppTheme.spacingSmall),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  size: 18,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  movie.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '豆瓣',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 头图左下角的清晰海报缩略卡。
  Widget _buildPosterThumb(
    Movie movie,
    ColorScheme colorScheme,
    bool hasPoster,
  ) {
    return Container(
      width: 96,
      height: 144,
      decoration: ShapeDecoration(
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.65),
            width: 1.5,
          ),
        ),
      ),
      child: MoviePoster(
        url: hasPoster ? movie.poster : '',
        heroTag: widget.posterHeroTag,
        radius: AppTheme.radiusMedium - 1.5,
      ),
    );
  }

  Widget _chipLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide.none,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  List<Widget> _buildBodySlivers(
    BuildContext context,
    Movie movie,
    MovieProvider provider,
  ) {
    final sectionBuilders = <WidgetBuilder>[
      (context) => _buildInfoSection(context, movie),
      if (movie.subjectType == MovieSubjectType.tvSeries)
        (context) => RepaintBoundary(
          child: SoftCard(
            showShadow: false,
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: _buildEpisodeControls(
              context,
              movie,
              Theme.of(context).colorScheme,
            ),
          ),
        ),
      (context) => _buildWatchSection(context, movie),
      if (_secondarySectionsReady && movie.summary.isNotEmpty)
        (context) => _buildSummarySection(context, movie),
      if (_secondarySectionsReady) (context) => _buildPersonalSection(context),
      (_) => const SizedBox(height: AppTheme.spacingXLarge),
    ];

    return [
      SliverPadding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final child = sectionBuilders[index](context);
            final isLast = index == sectionBuilders.length - 1;
            return Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : AppTheme.spacingMedium,
              ),
              child: child,
            );
          }, childCount: sectionBuilders.length),
        ),
      ),
    ];
  }

  Widget _buildInfoSection(BuildContext context, Movie movie) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSeries = movie.subjectType == MovieSubjectType.tvSeries;
    final castTop = _splitPeople(movie.cast).take(5).toList();
    final genreText = movie.genre.join(' / ');
    final durationLabel = _formatDurationText(movie.durationText);
    final subjectTypeLabel = isSeries ? '剧集' : '影片';

    final hasCredits =
        genreText.isNotEmpty ||
        movie.director.isNotEmpty ||
        movie.author.isNotEmpty ||
        castTop.isNotEmpty;

    return RepaintBoundary(
      child: SoftCard(
        showShadow: false,
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, '影片信息', icon: Icons.info_outline),
            const SizedBox(height: AppTheme.spacingMedium),
            // 关键信息胶囊
            Wrap(
              spacing: AppTheme.spacingSmall,
              runSpacing: AppTheme.spacingSmall,
              children: [
                _metaChip(colorScheme, subjectTypeLabel),
                if (movie.year.isNotEmpty) _metaChip(colorScheme, movie.year),
                if (movie.region.isNotEmpty)
                  _metaChip(colorScheme, movie.region),
                if (durationLabel.isNotEmpty)
                  _metaChip(colorScheme, durationLabel),
                if (movie.publishedAt.isNotEmpty)
                  _metaChip(
                    colorScheme,
                    '${isSeries ? '首播' : '上映'} ${movie.publishedAt}',
                  ),
                if (movie.rating > 0)
                  _metaChip(
                    colorScheme,
                    '★ ${movie.rating.toStringAsFixed(1)}',
                    accent: true,
                  ),
              ],
            ),
            // 主创
            if (hasCredits) ...[
              const SizedBox(height: AppTheme.spacingMedium),
              if (genreText.isNotEmpty) _creditRow(context, '题材', genreText),
              if (movie.director.isNotEmpty)
                _creditRow(context, '导演', movie.director),
              if (movie.author.isNotEmpty)
                _creditRow(context, '编剧', movie.author),
              if (castTop.isNotEmpty)
                _creditRow(context, '主演', castTop.join(' / ')),
            ],
            if (movie.doubanUrl.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingSmall),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _launchUrl(movie.doubanUrl),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('在豆瓣查看'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 关键信息小胶囊。
  Widget _metaChip(
    ColorScheme colorScheme,
    String text, {
    bool accent = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(
        color: accent
            ? AppTheme.accent.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHighest,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          side: BorderSide.none,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: accent ? AppTheme.accent : colorScheme.onSurface,
        ),
      ),
    );
  }

  /// 主创行：窄标签 + 醒目值。
  Widget _creditRow(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingSmall),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(BuildContext context, Movie movie) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RepaintBoundary(
      child: SoftCard(
        showShadow: false,
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, '简介', icon: Icons.notes_rounded),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              movie.summary,
              maxLines: _summaryExpanded ? null : 4,
              overflow: _summaryExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                height: 1.4,
                color: colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
            if (movie.summary.length > 80) ...[
              const SizedBox(height: AppTheme.spacingSmall),
              TextButton(
                onPressed: () {
                  setState(() => _summaryExpanded = !_summaryExpanded);
                },
                child: Text(_summaryExpanded ? '收起' : '展开'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWatchSection(BuildContext context, Movie movie) {
    final colorScheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: SoftCard(
        showShadow: false,
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _sectionTitle(
                    context,
                    '观影记录',
                    icon: Icons.bookmark_border,
                  ),
                ),
                if (_sessions.isNotEmpty)
                  Text(
                    '共 ${_sessions.length} 次',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            if (_sessions.isNotEmpty) ...[
              _buildWatchSummary(context, colorScheme),
              const SizedBox(height: AppTheme.spacingMedium),
            ],
            _buildSessionList(context, colorScheme),
            const SizedBox(height: AppTheme.spacingMedium),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSyncingWatchState ? null : () => _addSession(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(_sessions.isEmpty ? '记录一次观影' : '再记录一次'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: BorderSide(
                    color: AppTheme.accent.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionList(BuildContext context, ColorScheme colorScheme) {
    if (_sessionsLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMedium),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMedium),
        decoration: ShapeDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            side: BorderSide.none,
          ),
        ),
        child: Text(
          '还没有观影记录，看完后记录一次吧',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final session in _sessions)
          _SessionTile(
            key: ValueKey(session.id),
            session: session,
            onEdit: () => _editSession(session),
            onDelete: () => _deleteSession(session),
          ),
      ],
    );
  }

  Widget _buildWatchSummary(BuildContext context, ColorScheme colorScheme) {
    final latest = _sessions.reduce(
      (a, b) => a.watchedAt.isAfter(b.watchedAt) ? a : b,
    );
    final rewatchCount = _sessions.where((session) => session.isRewatch).length;
    final ratedSessions = _sessions
        .where((session) => session.rating != null)
        .toList(growable: false);
    final averageRating = ratedSessions.isEmpty
        ? null
        : ratedSessions
                  .map((session) => session.rating!)
                  .reduce((a, b) => a + b) /
              ratedSessions.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: ShapeDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.22),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.12)),
        ),
      ),
      child: Wrap(
        spacing: AppTheme.spacingSmall,
        runSpacing: AppTheme.spacingSmall,
        children: [
          _summaryChip(
            context,
            Icons.event_available_rounded,
            '最近 ${DateFormat('M月d日').format(latest.watchedAt)}',
          ),
          _summaryChip(
            context,
            Icons.history_rounded,
            '共 ${_sessions.length} 次',
          ),
          if (rewatchCount > 0)
            _summaryChip(context, Icons.replay_rounded, '重看 $rewatchCount 次'),
          if (averageRating != null)
            _summaryChip(
              context,
              Icons.star_rounded,
              '均分 ${averageRating.toStringAsFixed(1)}',
            ),
        ],
      ),
    );
  }

  Widget _summaryChip(BuildContext context, IconData icon, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colorScheme.primary),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _addSession() async {
    final isRewatch = _sessions.isNotEmpty;
    final draft = await showViewingSessionEditor(
      context,
      movieId: widget.movieId,
      defaultIsRewatch: isRewatch,
    );
    if (draft == null || !mounted) return;

    setState(() => _isSyncingWatchState = true);
    final provider = context.read<MovieProvider>();
    await provider.addViewingSession(draft);
    await _refreshAfterSessionChange(provider);
  }

  Future<void> _editSession(ViewingSession session) async {
    final draft = await showViewingSessionEditor(
      context,
      movieId: widget.movieId,
      existing: session,
    );
    if (draft == null || !mounted) return;

    setState(() => _isSyncingWatchState = true);
    final provider = context.read<MovieProvider>();
    await provider.updateViewingSession(draft);
    await _refreshAfterSessionChange(provider);
  }

  Future<void> _deleteSession(ViewingSession session) async {
    setState(() => _isSyncingWatchState = true);
    final provider = context.read<MovieProvider>();
    await provider.deleteViewingSession(session.id, widget.movieId);
    await _refreshAfterSessionChange(provider);
  }

  Future<void> _refreshAfterSessionChange(MovieProvider provider) async {
    final sessions = await provider.sessionsForMovie(widget.movieId);
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _watched = sessions.isNotEmpty;
      _isSyncingWatchState = false;
      _seedMovie = provider.peekMovieById(widget.movieId);
      _movieFuture = _loadMovie(forceRefresh: true);
    });
  }

  Widget _buildPersonalSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RepaintBoundary(
      child: SoftCard(
        showShadow: false,
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '我的评分',
              style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            _buildStarRating(colorScheme),
            const SizedBox(height: AppTheme.spacingLarge),
            Text(
              '我的短评',
              style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            TextField(
              controller: _reviewController,
              maxLines: 4,
              decoration: const InputDecoration(hintText: '记录你对这部影片的想法…'),
              onChanged: (_) => _markChanged(),
            ),
            const SizedBox(height: AppTheme.spacingLarge),
            Text(
              '我的标签',
              style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            MovieTagEditor(movieId: widget.movieId),
            const SizedBox(height: AppTheme.spacingLarge),
            OutlinedButton.icon(
              onPressed: _pickCollections,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('加入合集'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMedium,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCollections() async {
    final provider = context.read<CollectionProvider>();
    await provider.ensureLoaded();
    if (!mounted) return;
    final selectedBefore = await provider.collectionIdsForMovie(widget.movieId);
    if (!mounted) return;

    final selected = <String>{...selectedBefore};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colorScheme = Theme.of(sheetContext).colorScheme;
            final manual = provider.manualCollections;
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
              ),
              decoration: ShapeDecoration(
                color: colorScheme.surfaceContainerLow,
                shape: RoundedSuperellipseBorder(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppTheme.radiusXLarge),
                  ),
                  side: BorderSide.none,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacingLarge,
                      AppTheme.spacingMedium,
                      AppTheme.spacingSmall,
                      0,
                    ),
                    child: Row(
                      children: [
                        const Text(
                          '加入合集',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  if (manual.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppTheme.spacingXLarge),
                      child: Text('还没有手动合集，去合集页新建一个吧'),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final collection in manual)
                            Material(
                              type: MaterialType.transparency,
                              child: CheckboxListTile(
                                value: selected.contains(collection.id),
                                activeColor: AppTheme.accent,
                                title: Text(collection.name),
                                subtitle: Text('${collection.memberCount} 部'),
                                onChanged: (checked) {
                                  setSheetState(() {
                                    if (checked == true) {
                                      selected.add(collection.id);
                                    } else {
                                      selected.remove(collection.id);
                                    }
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(
                      AppTheme.spacingLarge,
                      AppTheme.spacingSmall,
                      AppTheme.spacingLarge,
                      AppTheme.spacingMedium,
                    ),
                    child: PrimaryButton(
                      label: '完成',
                      icon: Icons.check,
                      onPressed: () => Navigator.of(sheetContext).pop(selected),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null) return;
    final toAdd = result.difference(selectedBefore);
    final toRemove = selectedBefore.difference(result);
    for (final id in toAdd) {
      await provider.addMovieToCollection(id, widget.movieId);
    }
    for (final id in toRemove) {
      await provider.removeMovieFromCollection(id, widget.movieId);
    }
    if (!mounted) return;
    if (toAdd.isNotEmpty || toRemove.isNotEmpty) {
      AppToast.success(context, '已更新合集');
    }
  }

  Widget _sectionTitle(BuildContext context, String title, {IconData? icon}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 20,
            color: colorScheme.onSurface.withValues(alpha: 0.75),
          ),
          const SizedBox(width: AppTheme.spacingSmall),
        ],
        Expanded(
          child: Text(
            title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeControls(
    BuildContext context,
    Movie movie,
    ColorScheme colorScheme,
  ) {
    final total = _episodes.length;
    final watchedCount = _episodes.where((episode) => episode.watched).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppTheme.spacingSmall,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.list_alt_rounded,
                  size: 18,
                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: AppTheme.spacingSmall),
                Text(
                  '分集',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
            Text(
              total > 0 ? '已看 $watchedCount/$total' : '未获取到分集列表',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        if (total > 0 && !_episodeControlsReady)
          Container(
            height: 40,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ShapeDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                side: BorderSide.none,
              ),
            ),
            child: Text(
              '分集内容正在准备…',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          )
        else if (total > 0)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(total, (index) {
              final episode = _episodes[index];
              final selected = episode.watched;

              return SizedBox(
                width: 72,
                child: FilterChip(
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  side: BorderSide(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurface.withValues(alpha: 0.14),
                  ),
                  labelPadding: EdgeInsets.zero,
                  label: SizedBox(
                    width: double.infinity,
                    child: Text(
                      episode.label.isNotEmpty
                          ? episode.label
                          : '${episode.number}',
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : colorScheme.onSurface,
                  ),
                  onSelected: (_) => _toggleEpisode(
                    context.read<MovieProvider>(),
                    movie,
                    index,
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  Future<void> _toggleEpisode(
    MovieProvider provider,
    Movie movie,
    int index,
  ) async {
    if (index < 0 || index >= _episodes.length) return;

    await _updateWatchState(provider, movie, () {
      final next = List<MovieEpisode>.from(_episodes);
      final willWatch = !next[index].watched;

      if (willWatch) {
        // Mark this episode and all before it as watched
        for (var i = 0; i <= index; i++) {
          next[i] = next[i].copyWith(watched: true);
        }
      } else {
        // Unmark this episode and all after it as unwatched
        for (var i = index; i < next.length; i++) {
          next[i] = next[i].copyWith(watched: false);
        }
      }
      _episodes = next;

      final allWatched =
          _episodes.isNotEmpty && _episodes.every((episode) => episode.watched);
      _watched = allWatched;
      _watchedAt = allWatched ? (_watchedAt ?? DateTime.now()) : null;
    });
  }

  Future<void> _updateWatchState(
    MovieProvider provider,
    Movie movie,
    VoidCallback applyChange,
  ) async {
    if (_isSyncingWatchState) return;

    final previousEpisodes = List<MovieEpisode>.from(_episodes);
    final previousWatched = _watched;
    final previousWatchedAt = _watchedAt;

    setState(() {
      _isSyncingWatchState = true;
      applyChange();
    });

    final updated = movie.copyWith(
      episodes: _episodes,
      watched: _watched,
      watchedAt: _watched ? (_watchedAt ?? DateTime.now()) : null,
      clearWatchedAt: !_watched,
    );

    await provider.updateMovie(updated);
    if (!mounted) return;

    if (provider.error != null) {
      setState(() {
        _episodes = previousEpisodes;
        _watched = previousWatched;
        _watchedAt = previousWatchedAt;
        _isSyncingWatchState = false;
      });
      AppToast.error(context, provider.error!);
      return;
    }

    setState(() {
      _isSyncingWatchState = false;
    });
  }

  Widget _buildStarRating(ColorScheme colorScheme) {
    final currentRating = _userRating ?? 0;

    return Row(
      children: List.generate(5, (index) {
        final starValue = (index + 1).toDouble();
        final isFilled = currentRating >= starValue;
        final isHalf =
            currentRating >= starValue - 0.5 && currentRating < starValue;

        return GestureDetector(
          onTap: () {
            setState(() {
              _userRating = _userRating == starValue ? null : starValue;
              _hasChanges = true;
              LocalDataGuard.hold(this);
            });
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              isFilled
                  ? Icons.star
                  : (isHalf ? Icons.star_half : Icons.star_border),
              size: 36,
              color: (isFilled || isHalf)
                  ? Colors.amber
                  : colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        );
      }),
    );
  }

  List<String> _splitPeople(String raw) {
    if (raw.trim().isEmpty) return const [];
    return raw
        .split(RegExp(r'\s*/\s*'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _formatDurationText(String durationText) {
    final text = durationText.trim();
    if (text.isEmpty) return '';

    final match = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?').firstMatch(text);
    if (match == null) return text;

    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;

    if (hours > 0 && minutes > 0) return '$hours小时$minutes分钟';
    if (hours > 0) return '$hours小时';
    if (minutes > 0) return '$minutes分钟';
    return text;
  }

  void _markChanged() {
    LocalDataGuard.hold(this);
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _confirmLeave(Movie movie) async {
    if (_exitDialogOpen || _saving || !_hasChanges) return;
    _exitDialogOpen = true;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存修改后离开？'),
        content: const Text('评分、短评等修改尚未保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('放弃修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('保存并离开'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (!mounted || action == null) return;
    if (action == 'save') {
      if (!await _save(context.read<MovieProvider>(), movie) || !mounted) {
        return;
      }
    }
    LocalDataGuard.release(this);
    setState(() => _allowLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<bool> _save(MovieProvider provider, Movie movie) async {
    if (_saving || _isSyncingWatchState) return false;
    setState(() => _saving = true);
    final updated = (provider.peekMovieById(movie.id) ?? movie).copyWith(
      episodes: _episodes,
      watched: _watched,
      watchedAt: _watchedAt,
      clearWatchedAt: !_watched,
      userRating: _userRating,
      clearUserRating: _userRating == null,
      userReview: _reviewController.text.trim().isNotEmpty
          ? _reviewController.text.trim()
          : null,
      clearUserReview: _reviewController.text.trim().isEmpty,
    );

    try {
      await provider.updateMovie(updated);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.error(context, '保存失败，请重试，修改仍保留在当前页面');
      }
      return false;
    }
    if (!mounted) return false;
    if (provider.error != null) {
      setState(() => _saving = false);
      AppToast.error(context, '保存失败，请重试，修改仍保留在当前页面');
      return false;
    }

    LocalDataGuard.release(this);
    setState(() {
      _saving = false;
      _hasChanges = false;
      _seedMovie = updated;
      _movieFuture = _loadMovie(forceRefresh: true);
    });
    AppToast.success(context, '已保存');
    return true;
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _SessionTile extends StatelessWidget {
  final ViewingSession session;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SessionTile({
    super.key,
    required this.session,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: ShapeDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      DateFormat('yyyy 年 M 月 d 日').format(session.watchedAt),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              if (session.isRewatch)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: ShapeDecoration(
                    color: AppTheme.accent.withValues(
                      alpha: isDark ? 0.2 : 0.15,
                    ),
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide.none,
                    ),
                  ),
                  child: Text(
                    '重看',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: colorScheme.error.withValues(alpha: 0.7),
                    ),
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (session.mood != WatchMood.none ||
              session.watchedWith.isNotEmpty ||
              session.rating != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (session.mood != WatchMood.none)
                  _chip(
                    context,
                    '${session.mood.emoji ?? ''} ${session.mood.label}',
                  ),
                if (session.watchedWith.isNotEmpty)
                  _chip(context, '👥 ${session.watchedWith}'),
                if (session.rating != null)
                  _chip(context, '⭐ ${session.rating!.toStringAsFixed(1)}'),
              ],
            ),
          ],
          if (session.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '"${session.note}"',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide.none,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: colorScheme.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
