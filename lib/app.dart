import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/router/app_router.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/services/webdav_sync_service.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用根组件
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = StorageService().init();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _BootstrapShell(
            child: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return _BootstrapShell(
            child: Scaffold(
              body: ErrorState(
                message: '初始化失败: ${snapshot.error}',
                onRetry: () {
                  setState(() {
                    _bootstrapFuture = StorageService().init();
                  });
                },
              ),
            ),
          );
        }

        return const _AppShell();
      },
    );
  }
}

class _BootstrapShell extends StatelessWidget {
  final Widget child;

  const _BootstrapShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '片刻 0.2',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) {
          final brightness = Theme.of(context).brightness;
          final overlay = brightness == Brightness.dark
              ? AppTheme.overlayStyleLight
              : AppTheme.overlayStyleDark;
          final colorScheme = Theme.of(context).colorScheme;

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlay.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: colorScheme.surface,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => MovieProvider()),
        ChangeNotifierProvider(create: (_) => DrawHistoryProvider()),
        ChangeNotifierProvider(create: (_) => CollectionProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
      ],
      child: const _AppLifecycleShell(),
    );
  }
}

class _AppLifecycleShell extends StatefulWidget {
  const _AppLifecycleShell();

  @override
  State<_AppLifecycleShell> createState() => _AppLifecycleShellState();
}

class _AppLifecycleShellState extends State<_AppLifecycleShell>
    with WidgetsBindingObserver {
  late final Future<WebDavSyncService> _syncService;
  bool _syncRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncService = _createSyncService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncIfConfigured());
  }

  Future<WebDavSyncService> _createSyncService() async {
    final preferences = await SharedPreferences.getInstance();
    return WebDavSyncService(
      backup: BackupService(StorageService()),
      preferences: preferences,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncIfConfigured();
  }

  Future<void> _syncIfConfigured() async {
    if (_syncRunning || !mounted) return;
    _syncRunning = true;
    final movieProvider = context.read<MovieProvider>();
    final collectionProvider = context.read<CollectionProvider>();
    final drawHistoryProvider = context.read<DrawHistoryProvider>();
    final themeProvider = context.read<ThemeProvider>();
    try {
      final service = await _syncService;
      final outcome = await service.synchronizeAutomatically();
      if (!mounted) return;
      if (outcome.isConflict) {
        await _resolveAutomaticConflict(service, outcome);
        return;
      }
      if (!outcome.isSuccess) return;
      if (outcome.action == WebDavSyncAction.download) {
        await _refreshAfterSync(
          movieProvider: movieProvider,
          collectionProvider: collectionProvider,
          drawHistoryProvider: drawHistoryProvider,
          themeProvider: themeProvider,
        );
      }
    } catch (_) {
      // Automatic sync must never block or break local app startup.
    } finally {
      _syncRunning = false;
    }
  }

  Future<void> _resolveAutomaticConflict(
    WebDavSyncService service,
    WebDavSyncOutcome outcome,
  ) async {
    final navigator = rootNavigatorKey.currentState;
    final inspection = outcome.inspection;
    if (navigator == null || inspection == null || !mounted) return;
    final movieProvider = context.read<MovieProvider>();
    final collectionProvider = context.read<CollectionProvider>();
    final drawHistoryProvider = context.read<DrawHistoryProvider>();
    final themeProvider = context.read<ThemeProvider>();

    final choice = await showDialog<WebDavConflictChoice>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发现同步冲突'),
        content: Text(
          '本地：${inspection.local.updatedAt.toLocal()}\n'
          '云端：${inspection.remote?.snapshot.updatedAt.toLocal() ?? '暂无备份'}\n\n'
          '两台设备都发生了变化，请选择要保留的一侧。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('稍后处理'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(WebDavConflictChoice.remote),
            child: const Text('保留云端'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(WebDavConflictChoice.local),
            child: const Text('保留本地'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    final resolved = await service.synchronize(conflictChoice: choice);
    if (!mounted || !resolved.isSuccess) return;
    if (resolved.action == WebDavSyncAction.download) {
      await _refreshAfterSync(
        movieProvider: movieProvider,
        collectionProvider: collectionProvider,
        drawHistoryProvider: drawHistoryProvider,
        themeProvider: themeProvider,
      );
    }
  }

  Future<void> _refreshAfterSync({
    required MovieProvider movieProvider,
    required CollectionProvider collectionProvider,
    required DrawHistoryProvider drawHistoryProvider,
    required ThemeProvider themeProvider,
  }) async {
    await Future.wait([
      movieProvider.refreshAfterSync(),
      movieProvider.refreshWatchedHistory(),
      collectionProvider.refresh(),
      drawHistoryProvider.refresh(),
    ]);
    themeProvider.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => MaterialApp.router(
        title: '片刻 0.2',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeProvider.themeMode,
        routerConfig: appRouter,
        builder: (context, child) {
          final brightness = Theme.of(context).brightness;
          final overlay = brightness == Brightness.dark
              ? AppTheme.overlayStyleLight
              : AppTheme.overlayStyleDark;
          final colorScheme = Theme.of(context).colorScheme;

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlay.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: colorScheme.surface,
            ),
            child: child!,
          );
        },
      ),
    );
  }
}
