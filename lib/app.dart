import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/router/app_router.dart';
import 'package:random_movie/services/storage_service.dart';
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
      title: '片刻',
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
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp.router(
          title: '片刻',
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
      ),
    );
  }
}
