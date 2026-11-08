// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/app_components.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/services/update_service.dart';
import 'package:random_movie/services/update_download_service.dart';
import 'package:random_movie/services/webdav_sync_service.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:random_movie/widgets/settings/webdav_sync_section.dart';
import 'package:random_movie/widgets/settings/update_download_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  final UpdateService? updateService;
  final UpdateDownloadService? updateDownloadService;

  const SettingsPage({
    super.key,
    this.updateService,
    this.updateDownloadService,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final BackupService _backupService;
  late final UpdateService _updateService;
  late final Future<WebDavSyncService> _syncServiceFuture;
  late final Future<PackageInfo> _packageInfoFuture;
  bool _exportLoading = false;
  bool _importLoading = false;
  bool _updateLoading = false;
  bool _updateDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _backupService = BackupService(StorageService());
    _updateService = widget.updateService ?? UpdateService();
    _syncServiceFuture = _createSyncService();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  Future<WebDavSyncService> _createSyncService() async {
    final preferences = await SharedPreferences.getInstance();
    return WebDavSyncService(backup: _backupService, preferences: preferences);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.pageSurface,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Spacing.page,
          MediaQuery.of(context).padding.top + Spacing.sm,
          Spacing.page,
          DockMetrics.insetOf(context) + Spacing.xxl,
        ),
        children: [
          const PageHeader(
            title: '设置',
            padding: EdgeInsets.symmetric(vertical: Spacing.lg),
          ),
          _SectionHeader(label: '外观'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: const _ThemeModeSelector(),
          ),
          const SizedBox(height: Spacing.xxl),
          _SectionHeader(label: '数据备份'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.upload_rounded,
                  iconColor: const Color(0xFF2F6BFF),
                  title: '导出备份',
                  loading: _exportLoading,
                  onTap: _handleExport,
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: colorScheme.outline.withValues(alpha: 0.12),
                ),
                _SettingsTile(
                  icon: Icons.download_rounded,
                  iconColor: const Color(0xFF34C759),
                  title: '从备份恢复',
                  loading: _importLoading,
                  onTap: _handleImport,
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xxl),
          _SectionHeader(label: '坚果云同步'),
          const SizedBox(height: Spacing.sm),
          WebDavSyncSection(
            serviceFuture: _syncServiceFuture,
            onRestored: _refreshAfterWebDavRestore,
          ),
          const SizedBox(height: Spacing.xxl),
          _SectionHeader(label: '关于'),
          const SizedBox(height: Spacing.sm),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.system_update_rounded,
                  iconColor: const Color(0xFFFFB020),
                  title: '检查更新',
                  loading: _updateLoading,
                  onTap: _handleCheckUpdate,
                ),
                Divider(
                  height: 1,
                  indent: 56,
                  color: colorScheme.outline.withValues(alpha: 0.12),
                ),
                _SettingsTile(
                  icon: Icons.description_outlined,
                  iconColor: const Color(0xFF8A8D93),
                  title: '开源声明',
                  loading: false,
                  onTap: _showLicenseNotice,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingSmall,
            ),
            child: FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                final info = snapshot.data;
                final label = info == null
                    ? '片刻·焕新版'
                    : '片刻·焕新版 · ${info.version}（${info.buildNumber}）';
                return Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: TypeScale.caption,
                    color: colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 二创版的开源声明：来源、许可与改动范围。
  void _showLicenseNotice() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开源声明'),
        content: const SingleChildScrollView(
          child: Text(
            '片刻·焕新版以 KUDURO-jw/Pianke-0.2-derivative 为功能基础，保留原有功能与数据格式。'
            'UI 独立实现，视觉与交互参考 FlClash，未复制其 GPL 源码。\n\n'
            '片刻 0.2 是基于 ShareWinter/Pianke 的二次创作版本，'
            '遵循 Apache License 2.0 分发。\n\n'
            '原始项目：github.com/ShareWinter/Pianke\n'
            '本仓库：github.com/KUDURO-jw/Pianke-0.2-derivative\n\n'
            'Copyright 2026 ShareWinter（原始项目）\n'
            'Copyright 2026 KUDURO-jw（二次创作部分）\n\n'
            '本版本与原项目作者无隶属关系，也未获得其对本次改动的认可。'
            '应用名称与原始版权声明均予保留。\n\n'
            '本版本新增了坚果云 WebDAV 跨设备备份功能。'
            '该功能需要你主动填写账号才会启用，数据只在你自己的坚果云账号中流转，'
            '不会上传到本项目维护者或任何第三方服务器。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCheckUpdate() async {
    if (_updateLoading || _updateDialogOpen) return;
    setState(() => _updateLoading = true);
    try {
      final result = await _updateService.checkForUpdate();
      if (!mounted) return;
      if (!result.hasUpdate) {
        AppToast.show(
          context,
          '当前已是最新版本（${result.current.version}）',
          type: ToastType.success,
        );
        return;
      }
      setState(() => _updateLoading = false);
      _updateDialogOpen = true;
      await _showUpdateDialog(result.update!);
    } on UpdateCheckException catch (error) {
      if (!mounted) return;
      AppToast.show(context, error.message, type: ToastType.error);
    } on DioException catch (error) {
      if (!mounted) return;
      final timeout =
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout;
      AppToast.error(
        context,
        timeout ? '检查更新超时，请检查网络后重试' : '无法连接更新服务器，请检查网络后重试',
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '检查更新失败，请稍后再试', type: ToastType.error);
    } finally {
      _updateDialogOpen = false;
      if (mounted) setState(() => _updateLoading = false);
    }
  }

  Future<void> _showUpdateDialog(AppUpdateInfo update) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => UpdateDownloadDialog(
        update: update,
        service: widget.updateDownloadService ?? UpdateDownloadService(),
      ),
    );
  }

  Future<void> _handleExport() async {
    if (_exportLoading) return;
    setState(() => _exportLoading = true);
    try {
      final result = await _backupService.exportBackup();
      if (!mounted) return;
      if (result.success) {
        final stats = result.stats;
        if (stats != null) {
          AppToast.show(
            context,
            '已导出 ${stats.movieCount} 部影片、${stats.sessionCount} 条观影记录、${stats.drawRecordCount} 条抽片记录',
            type: ToastType.success,
          );
        }
      } else if (result.message != '已取消') {
        AppToast.show(context, result.message ?? '导出失败', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  Future<void> _handleImport() async {
    if (_importLoading) return;

    final confirmed = await _showImportConfirmDialog();
    if (!confirmed || !mounted) return;

    final movieProvider = context.read<MovieProvider>();
    final collectionProvider = context.read<CollectionProvider>();
    final drawHistoryProvider = context.read<DrawHistoryProvider>();

    setState(() => _importLoading = true);
    try {
      final result = await _backupService.importBackup();
      if (!mounted) return;
      if (result.success) {
        await _refreshAfterImport(
          movieProvider: movieProvider,
          collectionProvider: collectionProvider,
          drawHistoryProvider: drawHistoryProvider,
        );
        if (!mounted) return;
        final stats = result.stats;
        if (stats != null) {
          AppToast.show(
            context,
            '已导入 ${stats.moviesImported} 部影片'
            '${stats.moviesSkipped > 0 ? '（跳过 ${stats.moviesSkipped} 条重复）' : ''}'
            '、${stats.drawRecordsImported} 条抽片记录'
            '${stats.drawRecordsSkipped > 0 ? '（跳过 ${stats.drawRecordsSkipped} 条重复）' : ''}'
            '${stats.sessionsImported > 0 ? '、${stats.sessionsImported} 条观影记录' : ''}',
            type: ToastType.success,
          );
        }
      } else if (result.message != '已取消') {
        AppToast.show(context, result.message ?? '恢复失败', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _importLoading = false);
    }
  }

  Future<void> _refreshAfterImport({
    required MovieProvider movieProvider,
    required CollectionProvider collectionProvider,
    required DrawHistoryProvider drawHistoryProvider,
  }) async {
    await Future.wait([
      movieProvider.refreshLibrary(),
      movieProvider.refreshWatchedHistory(),
      movieProvider.refreshHistoryCalendarMonth(forceRefresh: true),
      collectionProvider.refresh(),
      drawHistoryProvider.refresh(),
    ]);
  }

  Future<void> _refreshAfterWebDavRestore() async {
    await _refreshAfterImport(
      movieProvider: context.read<MovieProvider>(),
      collectionProvider: context.read<CollectionProvider>(),
      drawHistoryProvider: context.read<DrawHistoryProvider>(),
    );
    if (mounted) context.read<ThemeProvider>().load();
  }

  Future<bool> _showImportConfirmDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    return await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.3),
          builder: (ctx) => AlertDialog(
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            title: const Text('从备份恢复'),
            content: const Text(
              '将从备份文件合并数据，已有记录不会被覆盖或删除。\n\n请选择之前导出的 .json 备份文件。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
                child: const Text(
                  '选择文件',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTheme.spacingSmall,
        bottom: AppTheme.spacingXSmall,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.45),
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// 主题模式三档选择：跟随系统 / 浅色 / 深色。
class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context) {
    final current = context.watch<ThemeProvider>().themeMode;
    const options = [
      (ThemeMode.system, Icons.brightness_auto_rounded, '跟随系统'),
      (ThemeMode.light, Icons.light_mode_rounded, '浅色'),
      (ThemeMode.dark, Icons.dark_mode_rounded, '深色'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        segments: [
          for (final option in options)
            ButtonSegment(
              value: option.$1,
              label: Text(option.$3, textAlign: TextAlign.center),
              icon: Icon(option.$2, size: 18),
            ),
        ],
        selected: {current},
        onSelectionChanged: (values) =>
            context.read<ThemeProvider>().setMode(values.single),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool loading;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: AppTheme.spacingMedium,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: ShapeDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.2 : 0.12),
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide.none,
                ),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingSmall),
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }
}
