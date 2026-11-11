// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/router/app_router.dart';
import 'package:random_movie/services/backup_inventory.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/services/webdav_sync_service.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';

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
          // 数据库被更新版本创建过：重试永远不会成功，所以不给「重试」按钮，
          // 只把「需要装回新版本」讲清楚，避免用户反复点重试以为应用坏了。
          final error = snapshot.error;
          if (error is DatabaseTooNewException) {
            return _BootstrapShell(
              child: Scaffold(
                body: ErrorState(message: error.message),
              ),
            );
          }
          return _BootstrapShell(
            child: Scaffold(
              body: ErrorState(
                message: '初始化失败: $error',
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
      title: '片刻·焕新版',
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
    return WebDavSyncService.shared();
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
        scrollable: true,
        content: Text(
          '本地：${inspection.local.updatedAt.toLocal()}\n'
          '云端：${inspection.remote?.snapshot.updatedAt.toLocal() ?? '暂无备份'}\n\n'
          '本地内容：${BackupInventory.fromPayload(inspection.local.payload).description}\n\n'
          '云端内容：${inspection.remote == null ? "无" : BackupInventory.fromPayload(inspection.remote!.snapshot.payload).description}\n\n'
          '双方内容不同，选择后将整份替换另一侧。',
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

    final resolved = await service.synchronize(
      conflictChoice: choice,
      expectedInspection: inspection,
    );
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
        title: '片刻·焕新版',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeProvider.themeMode,
        // 关闭主题切换的逐帧颜色插值。
        //
        // MaterialApp 默认会在 kThemeAnimationDuration（200ms）内，
        // 用 Curves.linear 把整套颜色从浅色插值到深色。中途会经过大量
        // 不自然的灰调——浅底卡片、深色文字这类组合在中间态会同时变灰，
        // 观感就是「切深色时整屏闪一下」。
        //
        // 本项目大量使用固定的中性色（SurfaceLevel 的四层表面色刻意不随
        // seed 染色），这些颜色在插值过程中并不协调，插值反而暴露问题。
        // 设为零后主题立即切换，没有中间态，也就没有闪烁。
        themeAnimationDuration: Duration.zero,
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
