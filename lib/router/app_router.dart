// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/pages/collections/collections_page.dart';
import 'package:random_movie/pages/collections/collection_detail_page.dart';
import 'package:random_movie/pages/history/history_page.dart';
import 'package:random_movie/pages/draw/draw_hub_page.dart';
import 'package:random_movie/pages/draw/draw_page.dart';
import 'package:random_movie/pages/movies/add_movie_page.dart';
import 'package:random_movie/pages/movies/movie_detail_page.dart';
import 'package:random_movie/pages/movies/movies_page.dart';
import 'package:random_movie/widgets/common/app_components.dart';
import 'package:random_movie/pages/settings/settings_page.dart';
import 'package:random_movie/providers/movie_provider.dart';

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

    return Scaffold(
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
    );
  }
}

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/movies',
  routes: [
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
                  builder: (context, state) => const AddMoviePage(),
                ),
                GoRoute(
                  path: 'detail/:movieId',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder: (context, state) {
                    final movieId = state.pathParameters['movieId']!;
                    return CustomTransitionPage<void>(
                      key: state.pageKey,
                      transitionDuration: const Duration(milliseconds: 160),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 120,
                      ),
                      child: MovieDetailPage(movieId: movieId),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            final fade = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic,
                            );
                            if (MediaQuery.disableAnimationsOf(context)) {
                              return child;
                            }
                            return FadeTransition(opacity: fade, child: child);
                          },
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
                  builder: (context, state) => const DrawPage(),
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
                  builder: (context, state) => const HistoryCalendarPage(),
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
      builder: (context, state) => const CollectionsPage(),
      routes: [
        GoRoute(
          path: 'detail',
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) {
            final collection = state.extra as MovieCollection;
            return CollectionDetailPage(collection: collection);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/draw-from',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final args = state.extra as ({List<String> movieIds, String title});
        return DrawPage(presetMovieIds: args.movieIds, presetTitle: args.title);
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late final Animation<double> _fade = _controller.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );

  @override
  void didUpdateWidget(covariant _BranchTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
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
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              child: ExcludeFocus(
                excluding: i != widget.index,
                child: FadeTransition(
                  opacity: _fade,
                  child: RepaintBoundary(child: widget.children[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
