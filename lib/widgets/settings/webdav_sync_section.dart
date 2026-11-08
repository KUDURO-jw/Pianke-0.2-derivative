// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/services/backup_snapshot.dart';
import 'package:random_movie/services/webdav_client.dart';
import 'package:random_movie/services/webdav_sync_service.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';

class WebDavSyncSection extends StatefulWidget {
  final Future<WebDavSyncService> serviceFuture;
  final Future<void> Function() onRestored;

  const WebDavSyncSection({
    super.key,
    required this.serviceFuture,
    required this.onRestored,
  });

  @override
  State<WebDavSyncSection> createState() => _WebDavSyncSectionState();
}

class _WebDavSyncSectionState extends State<WebDavSyncSection> {
  late final Future<void> _loadFuture;
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _directoryController = TextEditingController(text: 'Pianke');

  WebDavSyncService? _service;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadConfig();
  }

  Future<void> _loadConfig() async {
    _service = await widget.serviceFuture;
    final config = await _service!.readConfig();
    _accountController.text = config.account;
    _directoryController.text = config.remoteDirectory;
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _directoryController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    await _service!.saveConfig(
      account: _accountController.text,
      remoteDirectory: _directoryController.text,
      applicationPassword: _passwordController.text.isEmpty
          ? null
          : _passwordController.text,
    );
    _passwordController.clear();
  }

  Future<void> _testConnection() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _saveConfig();
      await _service!.testConnection();
      _setMessage('连接成功，远程目录可用');
    } catch (error) {
      _setError(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSync(WebDavSyncDirection direction) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _progress = null;
    });

    try {
      await _saveConfig();
      final inspection = await _service!.inspect(onProgress: _updateProgress);
      if (!mounted) return;

      if (inspection.decision.action == WebDavSyncAction.none) {
        _setMessage('本地和云端数据已经是最新');
        return;
      }

      final choice = inspection.decision.action == WebDavSyncAction.conflict
          ? await _showConflictDialog(inspection)
          : null;
      if (inspection.decision.action == WebDavSyncAction.conflict &&
          choice == null) {
        _setMessage('已取消冲突处理，双方数据未改变');
        return;
      }

      final confirmationDirection = choice == WebDavConflictChoice.local
          ? WebDavSyncDirection.upload
          : choice == WebDavConflictChoice.remote
          ? WebDavSyncDirection.download
          : direction == WebDavSyncDirection.automatic
          ? inspection.decision.action == WebDavSyncAction.upload
                ? WebDavSyncDirection.upload
                : WebDavSyncDirection.download
          : direction;
      final confirmed = await _showVersionDialog(
        inspection,
        direction: confirmationDirection,
      );
      if (!confirmed || !mounted) return;

      final outcome = await _service!.synchronize(
        direction: direction,
        conflictChoice: choice,
        onProgress: _updateProgress,
      );
      if (!mounted) return;
      if (outcome.isSuccess) {
        if (outcome.action == WebDavSyncAction.download) {
          await widget.onRestored();
          if (!mounted) return;
          // 恢复是覆盖操作，明确告知兜底备份的位置，方便反悔时找回。
          _setMessage('${outcome.message}（覆盖前的数据已备份到「片刻安全备份」）');
        } else {
          _setMessage(outcome.message);
        }
      } else if (outcome.isConflict) {
        _setError('检测到新的冲突，请重新查看两侧版本');
      } else {
        _setError(outcome.message);
      }
    } catch (error) {
      if (mounted) _setError(_errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _updateProgress(int current, int total) {
    if (!mounted) return;
    setState(() {
      _progress = total > 0 ? (current / total).clamp(0, 1).toDouble() : null;
    });
  }

  void _setMessage(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = false;
    });
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = true;
    });
  }

  String _errorMessage(Object error) {
    if (error is WebDavException) return error.message;
    return '同步失败，请稍后重试';
  }

  Future<bool> _showVersionDialog(
    SyncInspection inspection, {
    required WebDavSyncDirection direction,
  }) async {
    final remote = inspection.remote?.snapshot;
    final isRestore = direction == WebDavSyncDirection.download;
    final action = isRestore ? '恢复' : '上传';
    final colorScheme = Theme.of(context).colorScheme;

    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(isRestore ? '确认用云端覆盖本地？' : '同步前确认'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本地：${_snapshotSummary(inspection.local)}'),
                const SizedBox(height: AppTheme.spacingSmall),
                Text(
                  remote == null ? '云端：暂无备份' : '云端：${_snapshotSummary(remote)}',
                ),
                const SizedBox(height: AppTheme.spacingMedium),
                if (isRestore)
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacingMedium),
                    decoration: ShapeDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.5),
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                        side: BorderSide.none,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: AppTheme.spacingSmall),
                        Expanded(
                          child: Text(
                            '本机的影片、观影记录、合集与标签将被云端备份'
                            '整份替换，本地独有的内容会丢失，且无法撤回。',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Text('将把本机数据上传覆盖云端备份。'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: isRestore
                    ? FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      )
                    : null,
                child: Text(isRestore ? '覆盖并恢复' : action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<WebDavConflictChoice?> _showConflictDialog(SyncInspection inspection) {
    return showDialog<WebDavConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发现同步冲突'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本地和云端都发生了变化，请选择要保留的一侧。'),
            const SizedBox(height: AppTheme.spacingMedium),
            Text('本地：${_snapshotSummary(inspection.local)}'),
            const SizedBox(height: AppTheme.spacingSmall),
            Text('云端：${_snapshotSummary(inspection.remote!.snapshot)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
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
  }

  String _snapshotSummary(BackupSnapshot snapshot) {
    final stamp = snapshot.updatedAt.toLocal().toString().split('.').first;
    return '$stamp，${snapshot.movieCount} 部影片，校验值 ${snapshot.checksum.substring(0, 8)}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SoftContainer(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || _service == null) {
          return const SoftContainer(child: Text('同步配置加载失败'));
        }

        final colorScheme = Theme.of(context).colorScheme;
        return SoftContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WebDAV 地址：${WebDavClient.endpoint}',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              TextField(
                controller: _accountController,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: '坚果云账号',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              TextField(
                controller: _passwordController,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '应用密码',
                  hintText: '留空表示使用已保存的应用密码',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              TextField(
                controller: _directoryController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '远程备份目录',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              if (_progress != null) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: AppTheme.spacingSmall),
              ],
              if (_message != null) ...[
                Text(
                  _message!,
                  style: TextStyle(
                    color: _messageIsError
                        ? colorScheme.error
                        : colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingSmall),
              ],
              Wrap(
                spacing: AppTheme.spacingSmall,
                runSpacing: AppTheme.spacingSmall,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _testConnection,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('测试连接'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _runSync(WebDavSyncDirection.upload),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('上传备份'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _runSync(WebDavSyncDirection.download),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('从云端恢复'),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _runSync(WebDavSyncDirection.automatic),
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('同步'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
