// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/widgets/common/app_components.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/movie_provider.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/movie/quick_viewing_entry.dart';

/// 观影记录页面
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    // 日历内嵌到「观影记录」下方，进入页面即预载当前月。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MovieProvider>().jumpToCurrentHistoryMonth();
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      context.read<MovieProvider>().loadMoreWatchedHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          Selector<
            MovieProvider,
            ({
              List<SessionEntry> sessionEntries,
              ViewingStats viewingStats,
              bool hasLoadedHistory,
              bool isHistoryLoading,
              bool isHistoryLoadingMore,
              bool hasMoreHistory,
              String? error,
            })
          >(
            selector: (_, provider) => (
              sessionEntries: provider.sessionEntries,
              viewingStats: provider.viewingStats,
              hasLoadedHistory: provider.hasLoadedHistory,
              isHistoryLoading: provider.isHistoryLoading,
              isHistoryLoadingMore: provider.isHistoryLoadingMore,
              hasMoreHistory: provider.hasMoreHistory,
              error: provider.error,
            ),
            builder: (context, state, _) {
              return _HistoryListView(
                scrollController: _scrollController,
                sessionEntries: state.sessionEntries,
                viewingStats: state.viewingStats,
                hasLoadedHistory: state.hasLoadedHistory,
                isHistoryLoading: state.isHistoryLoading,
                isHistoryLoadingMore: state.isHistoryLoadingMore,
                hasMoreHistory: state.hasMoreHistory,
                error: state.error,
              );
            },
          ),
    );
  }
}

class HistoryCalendarPage extends StatefulWidget {
  const HistoryCalendarPage({super.key});

  @override
  State<HistoryCalendarPage> createState() => _HistoryCalendarPageState();
}

class _HistoryCalendarPageState extends State<HistoryCalendarPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MovieProvider>().jumpToCurrentHistoryMonth();
    });
  }

  void _openDaySheet(BuildContext context, HistoryDaySummary summary) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _HistoryDaySheet(summary: summary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.chevron_left_rounded, size: 30),
        ),
        title: const Text('日历'),
        actions: [
          IconButton(
            tooltip: '补记观影',
            icon: const Icon(Icons.add),
            onPressed: () => showQuickViewingEntry(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
      ),
      body:
          Selector<
            MovieProvider,
            ({
              bool isHistoryCalendarLoading,
              bool hasLoadedHistoryCalendar,
              HistoryMonthKey visibleMonth,
              HistoryMonthData? visibleMonthData,
              String? error,
            })
          >(
            selector: (_, provider) => (
              isHistoryCalendarLoading: provider.isHistoryCalendarLoading,
              hasLoadedHistoryCalendar: provider.hasLoadedHistoryCalendar,
              visibleMonth: provider.visibleHistoryMonth,
              visibleMonthData: provider.visibleHistoryMonthData,
              error: provider.error,
            ),
            builder: (context, state, _) {
              return _HistoryCalendarView(
                visibleMonth: state.visibleMonth,
                monthData: state.visibleMonthData,
                isLoading: state.isHistoryCalendarLoading,
                hasLoaded: state.hasLoadedHistoryCalendar,
                error: state.error,
                onPreviousMonth: () {
                  context.read<MovieProvider>().setVisibleHistoryMonth(
                    state.visibleMonth.previous(),
                  );
                },
                onNextMonth: () {
                  context.read<MovieProvider>().setVisibleHistoryMonth(
                    state.visibleMonth.next(),
                  );
                },
                onJumpToToday: () {
                  context.read<MovieProvider>().jumpToCurrentHistoryMonth();
                },
                onRetry: () {
                  context.read<MovieProvider>().refreshHistoryCalendarMonth(
                    forceRefresh: true,
                  );
                },
                onTapDay: (summary) => _openDaySheet(context, summary),
              );
            },
          ),
    );
  }
}

/// 打开某一天的观影明细底部弹层（内嵌日历与日历页共用）。
void _openHistoryDaySheet(BuildContext context, HistoryDaySummary summary) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _HistoryDaySheet(summary: summary),
  );
}

class _HistoryListView extends StatelessWidget {
  final ScrollController scrollController;
  final List<SessionEntry> sessionEntries;
  final ViewingStats viewingStats;
  final bool hasLoadedHistory;
  final bool isHistoryLoading;
  final bool isHistoryLoadingMore;
  final bool hasMoreHistory;
  final String? error;

  const _HistoryListView({
    required this.scrollController,
    required this.sessionEntries,
    required this.viewingStats,
    required this.hasLoadedHistory,
    required this.isHistoryLoading,
    required this.isHistoryLoadingMore,
    required this.hasMoreHistory,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('history-session-list'),
      controller: scrollController,
      scrollCacheExtent: ScrollCacheExtent.pixels(
        MediaQuery.of(context).size.height * 1.25,
      ),
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: PageHeader(
              title: '观影记录',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '补记观影',
                    icon: const Icon(Icons.add),
                    onPressed: () => showQuickViewingEntry(context),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '观影工具',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (value) => context.push(
                      value == 'year' ? '/history/year' : '/history/calendar',
                    ),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'calendar', child: Text('打开观影日历')),
                      PopupMenuItem(value: 'year', child: Text('年度回顾')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // 日历内嵌在标题正下方
        SliverToBoxAdapter(child: _buildCalendar(context)),
        _buildContent(context),
        SliverToBoxAdapter(
          child: SizedBox(height: DockMetrics.insetOf(context)),
        ),
      ],
    );
  }

  Widget _buildCalendar(BuildContext context) {
    return Selector<
      MovieProvider,
      ({
        bool isHistoryCalendarLoading,
        bool hasLoadedHistoryCalendar,
        HistoryMonthKey visibleMonth,
        HistoryMonthData? visibleMonthData,
        String? error,
      })
    >(
      selector: (_, p) => (
        isHistoryCalendarLoading: p.isHistoryCalendarLoading,
        hasLoadedHistoryCalendar: p.hasLoadedHistoryCalendar,
        visibleMonth: p.visibleHistoryMonth,
        visibleMonthData: p.visibleHistoryMonthData,
        error: p.error,
      ),
      builder: (context, s, _) => _HistoryCalendarView(
        embedded: true,
        visibleMonth: s.visibleMonth,
        monthData: s.visibleMonthData,
        isLoading: s.isHistoryCalendarLoading,
        hasLoaded: s.hasLoadedHistoryCalendar,
        error: s.error,
        onPreviousMonth: () => context
            .read<MovieProvider>()
            .setVisibleHistoryMonth(s.visibleMonth.previous()),
        onNextMonth: () => context.read<MovieProvider>().setVisibleHistoryMonth(
          s.visibleMonth.next(),
        ),
        onJumpToToday: () =>
            context.read<MovieProvider>().jumpToCurrentHistoryMonth(),
        onRetry: () => context
            .read<MovieProvider>()
            .refreshHistoryCalendarMonth(forceRefresh: true),
        onTapDay: (summary) => _openHistoryDaySheet(context, summary),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if ((!hasLoadedHistory || isHistoryLoading) && sessionEntries.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: LoadingState(message: '加载中…'),
      );
    }

    if (error != null && sessionEntries.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorState(
          message: error!,
          onRetry: context.read<MovieProvider>().refreshWatchedHistory,
        ),
      );
    }

    if (sessionEntries.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          title: '还没有观影记录',
          subtitle: '在影片详情页「记录一次观影」后，时间线会出现在这里。',
          icon: Icons.visibility_outlined,
        ),
      );
    }

    // header (stats) + timeline items + optional loader
    final hasStats = !viewingStats.isEmpty;
    final headerCount = hasStats ? 1 : 0;
    final trailerCount = hasMoreHistory || isHistoryLoadingMore ? 1 : 0;
    final itemCount = headerCount + sessionEntries.length + trailerCount;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingMedium,
        AppTheme.spacingMedium,
        AppTheme.spacingMedium,
        AppTheme.spacingXLarge,
      ),
      sliver: SliverList.separated(
        itemCount: itemCount,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppTheme.spacingMedium),
        itemBuilder: (context, index) {
          if (hasStats && index == 0) {
            return _StatsDashboard(stats: viewingStats);
          }
          final entryIndex = index - headerCount;
          if (entryIndex >= sessionEntries.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTheme.spacingLarge),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final entry = sessionEntries[entryIndex];
          return RepaintBoundary(
            child: _SessionTimelineCard(
              key: ValueKey(entry.session.id),
              entry: entry,
              onTap: () => context.push('/movies/detail/${entry.movie.id}'),
            ),
          );
        },
      ),
    );
  }
}

/// 观影页顶部统计仪表盘。
class _StatsDashboard extends StatelessWidget {
  final ViewingStats stats;

  const _StatsDashboard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topGenres = stats.genreDistribution.take(3).toList();

    return SoftContainer(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCell(value: '${stats.monthlyCount}', label: '本月观影'),
              ),
              _divider(colorScheme),
              Expanded(
                child: _StatCell(value: '${stats.totalCount}', label: '累计观影'),
              ),
              _divider(colorScheme),
              Expanded(
                child: _StatCell(
                  value: stats.highestRating != null
                      ? stats.highestRating!.toStringAsFixed(1)
                      : '—',
                  label: '我的最高分',
                ),
              ),
              _divider(colorScheme),
              Expanded(
                child: _StatCell(
                  value: stats.streakDays > 0 ? '${stats.streakDays}' : '—',
                  label: '连续天数',
                ),
              ),
            ],
          ),
          if (topGenres.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingMedium),
            Divider(
              height: 1,
              color: colorScheme.outline.withValues(alpha: 0.12),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            Row(
              children: [
                Icon(
                  Icons.category_outlined,
                  size: 16,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  '常看类型',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingMedium),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final genre in topGenres)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: ShapeDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.12),
                            shape: RoundedSuperellipseBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: BorderSide.none,
                            ),
                          ),
                          child: Text(
                            '${genre.key} ${genre.value}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(ColorScheme colorScheme) => Container(
    width: 1,
    height: 32,
    color: colorScheme.outline.withValues(alpha: 0.12),
  );
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;

  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _HistoryCalendarView extends StatelessWidget {
  static const List<String> _weekdays = ['日', '一', '二', '三', '四', '五', '六'];

  final HistoryMonthKey visibleMonth;
  final HistoryMonthData? monthData;
  final bool isLoading;
  final bool hasLoaded;
  final String? error;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onJumpToToday;
  final VoidCallback onRetry;
  final ValueChanged<HistoryDaySummary> onTapDay;
  final bool embedded;

  const _HistoryCalendarView({
    required this.visibleMonth,
    required this.monthData,
    required this.isLoading,
    required this.hasLoaded,
    required this.error,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onJumpToToday,
    required this.onRetry,
    required this.onTapDay,
    this.embedded = false,
  });

  Widget _boundedIfEmbedded(Widget child) =>
      embedded ? SizedBox(height: 280, child: child) : child;

  @override
  Widget build(BuildContext context) {
    if ((!hasLoaded || isLoading) && monthData == null) {
      return _boundedIfEmbedded(const LoadingState(message: '正在准备本月海报…'));
    }

    if (error != null && monthData == null) {
      return _boundedIfEmbedded(ErrorState(message: error!, onRetry: onRetry));
    }

    final firstDay = visibleMonth.firstDay;
    final leadingSlots = firstDay.weekday % 7;
    final firstGridDay = firstDay.subtract(Duration(days: leadingSlots));
    final today = DateTime.now();

    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 240) return;
        if (velocity < 0) {
          onNextMonth();
        } else {
          onPreviousMonth();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CalendarMonthHeader(
            visibleMonth: visibleMonth,
            onPreviousMonth: onPreviousMonth,
            onNextMonth: onNextMonth,
            onJumpToToday: onJumpToToday,
          ),
          const SizedBox(height: 14),
          Row(
            children: _weekdays
                .map(
                  (weekday) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        weekday,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          GridView.builder(
            key: ValueKey(visibleMonth.toString()),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final date = firstGridDay.add(Duration(days: index));
              final isCurrentMonth = date.month == visibleMonth.month;
              final isToday =
                  date.year == today.year &&
                  date.month == today.month &&
                  date.day == today.day;
              final summary = isCurrentMonth
                  ? monthData?.summaryForDay(date.day)
                  : null;

              return RepaintBoundary(
                child: _HistoryCalendarCell(
                  date: date,
                  summary: summary,
                  isCurrentMonth: isCurrentMonth,
                  isToday: isToday,
                  onTap:
                      !isCurrentMonth ||
                          date.isAfter(
                            DateTime(today.year, today.month, today.day),
                          )
                      ? null
                      : summary == null
                      ? () => showQuickViewingEntry(context, date: date)
                      : () => onTapDay(summary),
                ),
              );
            },
          ),
          if ((monthData == null || monthData!.isEmpty) && !isLoading) ...[
            const SizedBox(height: AppTheme.spacingLarge),
            Center(
              child: TextButton(
                onPressed: onJumpToToday,
                child: const Text('这个月还没有观影记录'),
              ),
            ),
          ],
        ],
      ),
    );

    if (embedded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, AppTheme.spacingSmall),
        child: content,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        10,
        12,
        10,
        AppTheme.spacingXLarge * 3,
      ),
      child: content,
    );
  }
}

class _CalendarMonthHeader extends StatelessWidget {
  final HistoryMonthKey visibleMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onJumpToToday;

  const _CalendarMonthHeader({
    required this.visibleMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onJumpToToday,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${visibleMonth.year} 年 ${visibleMonth.month} 月',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          TextButton(
            onPressed: onJumpToToday,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
            child: const Text('今天'),
          ),
          IconButton(
            onPressed: onPreviousMonth,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded, size: 26),
          ),
          IconButton(
            onPressed: onNextMonth,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right_rounded, size: 26),
          ),
        ],
      ),
    );
  }
}

class _HistoryCalendarCell extends StatelessWidget {
  final DateTime date;
  final HistoryDaySummary? summary;
  final bool isCurrentMonth;
  final bool isToday;
  final VoidCallback? onTap;

  const _HistoryCalendarCell({
    required this.date,
    required this.summary,
    required this.isCurrentMonth,
    required this.isToday,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMovie = summary != null && summary!.hasMovies;
    final count = summary?.count ?? 0;
    final textColor = isCurrentMonth
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.25);
    const cellRadius = 12.0;
    final dayTextStyle = TextStyle(
      color: hasMovie
          ? Colors.white
          : (isToday ? colorScheme.primary : textColor),
      fontSize: 15,
      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
      shadows: hasMovie
          ? const [
              Shadow(
                color: Color(0x99000000),
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ]
          : null,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(cellRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cellRadius),
            border: isToday
                ? Border.all(color: colorScheme.primary, width: 2)
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasMovie)
                ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(cellRadius),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final devicePixelRatio = MediaQuery.of(
                        context,
                      ).devicePixelRatio;
                      final cacheWidth =
                          (constraints.maxWidth * devicePixelRatio).round();
                      final posterUrl = summary!.primaryPoster;

                      if (posterUrl.isEmpty) {
                        return ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.movie_outlined,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.42,
                            ),
                          ),
                        );
                      }

                      return CachedNetworkImage(
                        imageUrl: posterUrl,
                        httpHeaders: ApiConfig.imageHeaders,
                        fit: BoxFit.cover,
                        memCacheWidth: cacheWidth.clamp(72, 180).toInt(),
                        maxWidthDiskCache: cacheWidth.clamp(72, 180).toInt(),
                        fadeInDuration: Duration.zero,
                        placeholder: (_, _) => ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (_, _, _) => ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.movie_outlined, size: 18),
                        ),
                      );
                    },
                  ),
                ),
              if (hasMovie)
                DecoratedBox(
                  decoration: ShapeDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.42),
                      ],
                    ),
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(cellRadius),
                      side: BorderSide.none,
                    ),
                  ),
                ),
              Center(child: Text('${date.day}', style: dayTextStyle)),
              if (count > 1)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: ShapeDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide.none,
                      ),
                    ),
                    child: Text(
                      '×$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryDaySheet extends StatelessWidget {
  final HistoryDaySummary summary;

  const _HistoryDaySheet({required this.summary});

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('yyyy年M月d日').format(summary.date);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingMedium,
            0,
            AppTheme.spacingMedium,
            AppTheme.spacingLarge,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateLabel, style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('补记这一天'),
                onPressed: () {
                  final hostContext = Navigator.of(context).context;
                  Navigator.pop(context);
                  showQuickViewingEntry(hostContext, date: summary.date);
                },
              ),
              const SizedBox(height: AppTheme.spacingXSmall),
              Text(
                '共 ${summary.count} 部',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              Expanded(
                child: ListView.separated(
                  itemCount: summary.movies.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppTheme.spacingSmall),
                  itemBuilder: (context, index) {
                    final movie = summary.movies[index];
                    return _HistoryDayMovieTile(movie: movie);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryDayMovieTile extends StatelessWidget {
  final Movie movie;

  const _HistoryDayMovieTile({required this.movie});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final watchDate = movie.watchedAt ?? movie.createdAt;

    return SoftContainer(
      showShadow: false,
      padding: const EdgeInsets.all(AppTheme.spacingSmall),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        onTap: () {
          Navigator.of(context).pop();
          context.push('/movies/detail/${movie.id}');
        },
        child: Row(
          children: [
            ClipRSuperellipse(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              child: SizedBox(
                width: 52,
                height: 74,
                child: movie.poster.isEmpty
                    ? ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.movie_outlined, size: 20),
                      )
                    : CachedNetworkImage(
                        imageUrl: movie.poster,
                        httpHeaders: ApiConfig.imageHeaders,
                        fit: BoxFit.cover,
                        memCacheWidth: 120,
                        maxWidthDiskCache: 120,
                        fadeInDuration: Duration.zero,
                        placeholder: (_, _) => ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (_, _, _) => ColoredBox(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.movie_outlined, size: 20),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: AppTheme.spacingSmall),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(watchDate),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (movie.year.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      movie.year,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// 观影时间线卡片：一次观影会话（一部多次 = 多条）。
class _SessionTimelineCard extends StatefulWidget {
  final SessionEntry entry;
  final VoidCallback? onTap;

  const _SessionTimelineCard({super.key, required this.entry, this.onTap});

  @override
  State<_SessionTimelineCard> createState() => _SessionTimelineCardState();
}

class _SessionTimelineCardState extends State<_SessionTimelineCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final movie = widget.entry.movie;
    final session = widget.entry.session;

    final metaChips = <String>[
      if (session.mood != WatchMood.none)
        '${session.mood.emoji ?? ''} ${session.mood.label}',
      if (session.watchedWith.isNotEmpty) '👥 ${session.watchedWith}',
      if (session.rating != null) '⭐ ${session.rating!.toStringAsFixed(1)}',
    ];

    return GestureDetector(
      onTapDown: widget.onTap != null
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: widget.onTap != null
          ? (_) => setState(() => _pressed = false)
          : null,
      onTapCancel: widget.onTap != null
          ? () => setState(() => _pressed = false)
          : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          decoration: ShapeDecoration(
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              side: BorderSide.none,
            ),
          ),
          child: SoftContainer(
            padding: const EdgeInsets.all(12),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRSuperellipse(
                  clipBehavior: Clip.hardEdge,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: SizedBox(
                    width: 72,
                    height: 100,
                    child: movie.poster.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: movie.poster,
                            httpHeaders: ApiConfig.imageHeaders,
                            fit: BoxFit.cover,
                            memCacheWidth: 160,
                            maxWidthDiskCache: 160,
                            fadeInDuration: Duration.zero,
                            placeholder: (_, _) => ColoredBox(
                              color: colorScheme.surfaceContainerHighest,
                            ),
                            errorWidget: (_, _, _) => ColoredBox(
                              color: colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.movie, size: 24),
                            ),
                          )
                        : ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.movie,
                              size: 24,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              movie.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (session.isRewatch) ...[
                            const SizedBox(width: 8),
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
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 13,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            DateFormat('yyyy年M月d日').format(session.watchedAt),
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (metaChips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final chip in metaChips)
                              Text(
                                chip,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (session.note.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '"${session.note}"',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
