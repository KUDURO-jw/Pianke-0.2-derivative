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
import 'package:random_movie/pages/settings/settings_page.dart';
import 'package:random_movie/providers/movie_provider.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
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
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: '片库',
          ),
          NavigationDestination(
            icon: Icon(Icons.casino_outlined),
            selectedIcon: Icon(Icons.casino),
            label: '抽片',
          ),
          NavigationDestination(
            icon: Icon(Icons.visibility_outlined),
            selectedIcon: Icon(Icons.visibility),
            label: '观影',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/movies',
  routes: [
    StatefulShellRoute.indexedStack(
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
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const AddMoviePage(),
                ),
                GoRoute(
                  path: 'detail/:movieId',
                  parentNavigatorKey: _rootNavigatorKey,
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
                  parentNavigatorKey: _rootNavigatorKey,
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
                  parentNavigatorKey: _rootNavigatorKey,
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
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CollectionsPage(),
      routes: [
        GoRoute(
          path: 'detail',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) {
            final collection = state.extra as MovieCollection;
            return CollectionDetailPage(collection: collection);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/draw-from',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final args = state.extra as ({List<String> movieIds, String title});
        return DrawPage(presetMovieIds: args.movieIds, presetTitle: args.title);
      },
    ),
  ],
);
