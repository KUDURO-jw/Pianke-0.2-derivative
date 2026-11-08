// Personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:random_movie/services/update_download_service.dart';
import 'package:random_movie/services/update_service.dart';

enum _DownloadPhase { idle, downloading, verifying, ready, installing, failed }

class UpdateDownloadDialog extends StatefulWidget {
  final AppUpdateInfo update;
  final UpdateDownloadService service;
  const UpdateDownloadDialog({
    super.key,
    required this.update,
    required this.service,
  });

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  _DownloadPhase _phase = _DownloadPhase.idle;
  CancelToken? _cancelToken;
  int _received = 0;
  int _total = -1;
  String? _file;
  String? _message;
  bool _messageIsError = false;
  final Stopwatch _progressClock = Stopwatch();

  bool get _busy =>
      _phase == _DownloadPhase.downloading ||
      _phase == _DownloadPhase.verifying ||
      _phase == _DownloadPhase.installing;
  bool get _downloading =>
      _phase == _DownloadPhase.downloading ||
      _phase == _DownloadPhase.verifying;

  @override
  void dispose() {
    _cancelToken?.cancel('Dialog closed');
    _progressClock.stop();
    super.dispose();
  }

  Future<void> _download() async {
    if (_busy) return;
    final token = CancelToken();
    _cancelToken = token;
    _progressClock
      ..reset()
      ..start();
    setState(() {
      _phase = _DownloadPhase.downloading;
      _received = 0;
      _total = -1;
      _message = null;
      _file = null;
      _messageIsError = false;
    });
    try {
      final file = await widget.service.download(
        widget.update,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted || token.isCancelled) return;
          if (_received > 0 &&
              _progressClock.elapsedMilliseconds < 100 &&
              received != total) {
            return;
          }
          _progressClock.reset();
          setState(() {
            _phase = _DownloadPhase.downloading;
            _received = received;
            _total = total;
          });
        },
        onVerifying: () {
          if (mounted && !token.isCancelled) {
            setState(() => _phase = _DownloadPhase.verifying);
          }
        },
      );
      if (token.isCancelled) throw token.cancelError!;
      if (!mounted) return;
      setState(() {
        _file = file;
        _phase = _DownloadPhase.ready;
        _message = '下载完成，安装包校验通过';
      });
    } on DioException catch (error) {
      if (!mounted) return;
      if (CancelToken.isCancel(error)) {
        setState(() {
          _phase = _DownloadPhase.idle;
          _message = '已取消下载';
          _messageIsError = false;
        });
      } else {
        _fail(_networkError(error));
      }
    } on UpdateDownloadException catch (error) {
      _fail(error.message);
    } on FileSystemException {
      _fail('无法保存安装包，请检查手机剩余空间后重试');
    } catch (_) {
      _fail('下载失败，请检查网络后重试');
    } finally {
      _progressClock.stop();
      _cancelToken = null;
    }
  }

  String _networkError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return '下载超时，请确认代理已覆盖片刻后重试';
    }
    if (error.response?.statusCode == 404) return '安装包暂不可用，请关闭后重新检查更新';
    if (error.response?.statusCode == 403 ||
        error.response?.statusCode == 429) {
      return '下载被服务器暂时拒绝，请稍后重试';
    }
    return '无法连接下载服务器，请确认代理已覆盖片刻后重试';
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _DownloadPhase.failed;
      _message = message;
      _messageIsError = true;
    });
  }

  Future<void> _install() async {
    final file = _file;
    final code = widget.update.versionCode;
    if (_busy || file == null || code == null) return;
    setState(() {
      _phase = _DownloadPhase.installing;
      _message = '正在检查安装包…';
      _messageIsError = false;
    });
    try {
      final result = await widget.service.install(file, code);
      if (!mounted) return;
      setState(() {
        _phase = _DownloadPhase.ready;
        _message = result == UpdateInstallResult.permissionRequired
            ? '请在系统设置中允许片刻安装应用，返回后再次点击“安装新版”'
            : '已打开系统安装确认；取消后也可以再次点击“安装新版”';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == 'invalid_update') {
          _file = null;
          _phase = _DownloadPhase.failed;
        } else {
          _phase = _DownloadPhase.ready;
        }
        _message = error.message ?? '无法打开系统安装界面，请重试';
        _messageIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _DownloadPhase.ready;
        _message = '无法打开系统安装界面，请重试';
        _messageIsError = true;
      });
    }
  }

  String _bytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final update = widget.update;
    final colorScheme = Theme.of(context).colorScheme;
    final fraction = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _downloading) _cancelToken?.cancel('User cancelled');
      },
      child: AlertDialog(
        title: const Text('发现焕新版更新'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${update.displayTitle}\n版本 ${update.versionName}'),
                if (update.changelog.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final item in update.changelog)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $item'),
                    ),
                ],
                if (_downloading || _phase == _DownloadPhase.installing) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _phase == _DownloadPhase.downloading
                        ? fraction
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _phase == _DownloadPhase.verifying
                        ? '正在校验安装包…'
                        : _phase == _DownloadPhase.installing
                        ? '正在打开系统安装界面…'
                        : fraction == null
                        ? '已下载 ${_bytes(_received)}'
                        : '${(fraction * 100).floor()}% · ${_bytes(_received)} / ${_bytes(_total)}',
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: _messageIsError
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_downloading)
            TextButton(
              onPressed: () => _cancelToken?.cancel('User cancelled'),
              child: const Text('取消下载'),
            )
          else if (!_busy)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_phase == _DownloadPhase.idle ? '稍后' : '关闭'),
            ),
          if (!_busy)
            FilledButton(
              onPressed: _file != null ? _install : _download,
              child: Text(
                _file != null
                    ? '安装新版'
                    : _phase == _DownloadPhase.failed
                    ? '重试下载'
                    : '下载新版',
              ),
            ),
        ],
      ),
    );
  }
}
