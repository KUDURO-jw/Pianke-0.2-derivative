// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/router/movie_detail_arguments.dart';
import 'package:random_movie/pages/collections/collections_page.dart';
import 'package:random_movie/pages/collections/collection_detail_page.dart';
import 'package:random_movie/pages/history/history_page.dart';
import 'package:random_movie/pages/history/annual_review_page.dart';
import 'package:random_movie/pages/draw/draw_hub_page.dart';
import 'package:random_movie/pages/draw/draw_page.dart';
import 'package:random_movie/pages/movies/add_movie_page.dart';
import 'package:random_movie/pages/movies/movie_detail_page.dart';
import 'package:random_movie/pages/movies/movies_page.dart';
import 'package:random_movie/widgets/common/app_components.dart';
import 'package:random_movie/pages/settings/settings_page.dart';
import 'package:random_movie/providers/movie_provider.dart';
import 'package:random_movie/widgets/movie/library_scroll_request.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _moviesNavigatorKey = GlobalKey<NavigatorState>();
final _drawNavigatorKey = GlobalKey<NavigatorState>();
final _historyNavigatorKey = GlobalKey<NavigatorState>();
final _settingsNavigatorKey = GlobalKey<NavigatorState>();

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final Set<int> _primedBranches = <int>{};
  final _libraryScrollRequest = LibraryScrollRequest();

  @override
  void dispose() {
    _libraryScrollRequest.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _primeCurrentBranch();
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationShell.currentIndex !=
        widget.navigationShell.currentIndex) {
      _primeCurrentBranch();
    }
  }

  void _primeCurrentBranch() {
    final index = widget.navigationShell.currentIndex;
    if (_primedBranches.contains(index)) return;
    _primedBranches.add(index);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index == 0) {
        context.read<MovieProvider>().ensureLibraryLoaded();
      } else if (index == 2) {
        context.read<MovieProvider>().ensureHistoryLoaded();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _primeCurrentBranch();
    final navigationShell = widget.navigationShell;

    return ListenableProvider<LibraryScrollRequest>.value(
      value: _libraryScrollRequest,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: navigationShell),
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FloatingNavBar(
                  currentIndex: navigationShell.currentIndex,
                  onSelected: (index) {
                    navigationShell.goBranch(
                      index,
                      initialLocation: index == navigationShell.currentIndex,
                    );
                  },
                  onDoubleTap: (index) {
                    if (index == 0) _libraryScrollRequest.scrollToTop();
                  },
                  items: const [
                    NavItemData(
                      icon: Icons.video_library_outlined,
                      selectedIcon: Icons.video_library_rounded,
                      label: '片库',
                    ),
                    NavItemData(
                      icon: Icons.casino_outlined,
                      selectedIcon: Icons.casino_rounded,
                      label: '抽片',
                    ),
                    NavItemData(
                      icon: Icons.insights_outlined,
                      selectedIcon: Icons.insights_rounded,
                      label: '观影',
                    ),
                    NavItemData(
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.settings_rounded,
                      label: '设置',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

CustomTransitionPage<void> _secondaryPage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  bool detail = false,
}) => CustomTransitionPage<void>(
  key: state.pageKey,
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 280),
  reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220),
  transitionsBuilder: detail
      ? AppPageTransitionsBuilder.detailTransition
      : AppPageTransitionsBuilder.transition,
  child: child,
);

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/movies',
  routes: [
    GoRoute(
      path: '/history/year',
      pageBuilder: (context, state) =>
          _secondaryPage(context, state, const AnnualReviewPage()),
    ),
    StatefulShellRoute(
      navigatorContainerBuilder: (context, navigationShell, children) =>
          _BranchTransition(
            index: navigationShell.currentIndex,
            children: children,
          ),
      builder: (context, state, navigationShell) {
        return HomeShell(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          navigatorKey: _moviesNavigatorKey,
          routes: [
            GoRoute(
              path: '/movies',
              builder: (context, state) => const MoviesPage(),
              routes: [
                GoRoute(
                  path: 'add',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder: (context, state) =>
                      _secondaryPage(context, state, const AddMoviePage()),
                ),
                GoRoute(
                  path: 'detail/:movieId',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder: (context, state) {
                    final movieId = state.pathParameters['movieId']!;
                    final extra = state.extra;
                    final args =
                        extra is MovieDetailArguments &&
                            extra.movie.id == movieId
                        ? extra
                        : null;
                    return _secondaryPage(
                      context,
                      state,
                      MovieDetailPage(
                        movieId: movieId,
                        initialMovie: args?.movie,
                        posterHeroTag: args?.posterTag,
                      ),
                      detail: true,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _drawNavigatorKey,
          routes: [
            GoRoute(
              path: '/draw',
              builder: (context, state) => const DrawHubPage(),
              routes: [
                GoRoute(
                  path: 'start',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder: (context, state) =>
                      _secondaryPage(context, state, const DrawPage()),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _historyNavigatorKey,
          routes: [
            GoRoute(
              path: '/history',
              builder: (context, state) => const HistoryPage(),
              routes: [
                GoRoute(
                  path: 'calendar',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder: (context, state) => _secondaryPage(
                    context,
                    state,
                    const HistoryCalendarPage(),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _settingsNavigatorKey,
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/collections',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) =>
          _secondaryPage(context, state, const CollectionsPage()),
      routes: [
        GoRoute(
          path: 'detail',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) {
            final collection = state.extra as MovieCollection;
            return _secondaryPage(
              context,
              state,
              CollectionDetailPage(collection: collection),
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/draw-from',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) {
        final args = state.extra as ({List<String> movieIds, String title});
        return _secondaryPage(
          context,
          state,
          DrawPage(presetMovieIds: args.movieIds, presetTitle: args.title),
        );
      },
    ),
  ],
);

class _BranchTransition extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _BranchTransition({required this.index, required this.children});

  @override
  State<_BranchTransition> createState() => _BranchTransitionState();
}

class _BranchTransitionState extends State<_BranchTransition>
    with SingleTickerProviderStateMixin {
  int? _outgoing;
  double _direction = 1;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  )..addStatusListener(_onStatus);

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && _outgoing != null) {
      setState(() => _outgoing = null);
    }
  }

  @override
  void didUpdateWidget(covariant _BranchTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _outgoing = null;
        _controller.value = 1;
      } else {
        _outgoing = oldWidget.index;
        _direction = widget.index > oldWidget.index ? 1 : -1;
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context) == TextDirection.rtl
        ? -_direction
        : _direction;
    Widget branch(int index) {
      final active = index == widget.index;
      final visible = active || index == _outgoing;
      return Offstage(
        key: ValueKey('branch-$index'),
        offstage: !visible,
        child: TickerMode(
          enabled: active,
          child: IgnorePointer(
            ignoring: !active,
            child: ExcludeSemantics(
              excluding: !active,
              child: ExcludeFocus(
                excluding: !active,
                child: AnimatedBuilder(
                  animation: _controller,
                  // The Navigator subtree is stable throughout the animation.
                  child: RepaintBoundary(child: widget.children[index]),
                  builder: (context, child) {
                    final progress = MediaQuery.disableAnimationsOf(context)
                        ? 1.0
                        : Curves.easeInOutCubic.transform(_controller.value);
                    return FractionalTranslation(
                      translation: Offset(
                        direction *
                            (active ? (1 - progress) * 0.08 : -progress * 0.04),
                        0,
                      ),
                      child: Opacity(
                        opacity: active ? progress : 1,
                        child: child,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            if (i != widget.index) branch(i),
          branch(widget.index),
        ],
      ),
    );
  }
}
