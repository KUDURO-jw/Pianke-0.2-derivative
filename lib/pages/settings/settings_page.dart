import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/services/update_service.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final BackupService _backupService;
  late final UpdateService _updateService;
  bool _exportLoading = false;
  bool _importLoading = false;
  bool _updateLoading = false;

  @override
  void initState() {
    super.initState();
    _backupService = BackupService(StorageService());
    _updateService = UpdateService();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppTheme.spacingLarge,
          AppTheme.spacingMedium,
          AppTheme.spacingLarge,
          MediaQuery.of(context).padding.bottom + AppTheme.spacingXLarge,
        ),
        children: [
          _SectionHeader(label: '外观'),
          const SizedBox(height: AppTheme.spacingSmall),
          SoftContainer(
            padding: const EdgeInsets.symmetric(
              vertical: AppTheme.spacingSmall,
            ),
            child: const _ThemeModeSelector(),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          _SectionHeader(label: '数据备份'),
          const SizedBox(height: AppTheme.spacingSmall),
          SoftContainer(
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.upload_rounded,
                  iconColor: const Color(0xFF4ECDC4),
                  title: '导出备份',
                  subtitle: '将片库和抽片记录导出为 JSON 文件',
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
                  iconColor: const Color(0xFF45B7D1),
                  title: '从备份恢复',
                  subtitle: '从 JSON 备份文件合并恢复数据',
                  loading: _importLoading,
                  onTap: _handleImport,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingSmall,
            ),
            child: Text(
              '备份文件为明文 JSON，可手动查看。恢复时只补充不存在的数据，不会覆盖已有记录。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.45),
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          _SectionHeader(label: '关于'),
          const SizedBox(height: AppTheme.spacingSmall),
          SoftContainer(
            child: _SettingsTile(
              icon: Icons.system_update_rounded,
              iconColor: const Color(0xFFFFB703),
              title: '检查更新',
              subtitle: '从 Gitee 检查片刻新版本',
              loading: _updateLoading,
              onTap: _handleCheckUpdate,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCheckUpdate() async {
    if (_updateLoading) return;
    setState(() => _updateLoading = true);
    try {
      final result = await _updateService.checkForUpdate();
      if (!mounted) return;
      if (!result.hasUpdate) {
        AppToast.show(
          context,
          '当前已是最新版本 ${result.current.version}',
          type: ToastType.success,
        );
        return;
      }
      await _showUpdateDialog(result.update!);
    } on UpdateCheckException catch (error) {
      if (!mounted) return;
      AppToast.show(context, error.message, type: ToastType.error);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '检查更新失败，请稍后再试', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _updateLoading = false);
    }
  }

  Future<void> _showUpdateDialog(AppUpdateInfo update) async {
    final colorScheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      barrierDismissible: !update.forceUpdate,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        title: Text(update.displayTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '版本 ${update.versionName}',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            if (update.changelog.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingMedium),
              for (final item in update.changelog)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $item'),
                ),
            ],
          ],
        ),
        actions: [
          if (!update.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('稍后'),
            ),
          TextButton(
            onPressed: () async {
              final url = Uri.tryParse(update.downloadUrl);
              if (url == null || !url.hasScheme) {
                AppToast.show(context, '下载地址无效', type: ToastType.error);
                return;
              }
              final launched = await launchUrl(
                url,
                mode: LaunchMode.externalApplication,
              );
              if (!launched && mounted) {
                AppToast.show(context, '无法打开下载地址', type: ToastType.error);
                return;
              }
              if (launched && ctx.mounted) {
                Navigator.of(ctx).pop();
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
            child: const Text(
              '去下载',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
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

  Future<bool> _showImportConfirmDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    return await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.3),
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
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
    const options = <(ThemeMode, IconData, String, String)>[
      (ThemeMode.system, Icons.brightness_auto_rounded, '跟随系统', '随系统深浅色自动切换'),
      (ThemeMode.light, Icons.light_mode_rounded, '浅色', '始终使用浅色主题'),
      (ThemeMode.dark, Icons.dark_mode_rounded, '深色', '始终使用深色主题'),
    ];

    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0)
            Divider(height: 1, indent: 56, color: colorScheme.outlineVariant),
          _ThemeModeTile(
            icon: options[i].$2,
            title: options[i].$3,
            subtitle: options[i].$4,
            selected: current == options[i].$1,
            onTap: () => context.read<ThemeProvider>().setMode(options[i].$1),
          ),
        ],
      ],
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
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
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.16)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected
                    ? AppTheme.accent
                    : colorScheme.onSurfaceVariant,
              ),
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingSmall),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.accent)
            else
              Icon(
                Icons.circle_outlined,
                size: 20,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
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
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(10),
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
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
