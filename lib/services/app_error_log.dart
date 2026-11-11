// 全局错误边界，Apache-2.0。
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 应用级错误收集。
///
/// 之前项目里没有任何全局错误处理：Flutter 层异常只会打到控制台，
/// 用户侧表现为「点了一下没反应」或白屏，事后完全无从排查。
///
/// 这里做三件事：
/// 1. 接管 [FlutterError.onError]（构建/布局/绘制异常）；
/// 2. 接管 [PlatformDispatcher.onError]（Zone 外的异步异常）；
/// 3. 把最近若干条错误写到应用私有目录，供设置页导出。
///
/// 刻意**不**做崩溃上报——本项目没有服务端，也不该悄悄上传数据。
/// 日志只留在本机，由用户主动导出。
abstract final class AppErrorLog {
  static const int _maxEntries = 50;

  /// 内存中的环形缓冲，导出时直接取，不必回读文件。
  static final List<String> _entries = <String>[];

  static File? _file;
  static bool _installed = false;

  /// 安装全局处理器。在 `runApp` 之前调用一次。
  static void install() {
    if (_installed) return;
    _installed = true;

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      // 保留默认行为（debug 下打印红屏信息），同时落一份到日志。
      previous?.call(details);
      record(
        'FlutterError: ${details.exceptionAsString()}',
        stack: details.stack?.toString(),
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      record('Uncaught: $error', stack: stack.toString());
      // 返回 true 表示已处理，避免再次冒泡成进程级崩溃。
      return true;
    };
  }

  /// 记录一条错误。可从任意位置调用。
  static void record(String message, {String? stack}) {
    final stamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer('[$stamp] $message');
    if (stack != null && stack.isNotEmpty) {
      // 只保留前若干行栈，完整栈对定位通常没帮助，还会撑爆日志。
      final lines = stack.split('\n').take(12).join('\n');
      buffer.write('\n$lines');
    }
    _entries.add(buffer.toString());
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    // 落盘是尽力而为：日志写失败绝不能反过来影响应用。
    unawaited(_flush(buffer.toString()));
  }

  /// 记录一次「被业务代码接住的失败」。
  ///
  /// [install] 里的两个处理器只抓**没人接的**异常。但本项目大量错误是
  /// 这样处理的：
  ///
  /// ```dart
  /// } catch (error) {
  ///   _error = '保存失败: $error';   // 显示在界面上，不算未捕获异常
  /// }
  /// ```
  ///
  /// 这类失败在 Dart 看来已经「处理完毕」，全局处理器收不到，
  /// 用户导出诊断日志时是空的——可它恰恰是用户真正遇到的问题
  /// （比如主键冲突导致添加影片失败）。
  ///
  /// 因此业务层在 catch 里显式调用本方法，把失败连同上下文记下来。
  static void recordHandled(
    String scope,
    Object error, {
    StackTrace? stack,
    String? detail,
  }) {
    final buffer = StringBuffer('[handled:$scope] $error');
    if (detail != null && detail.isNotEmpty) {
      buffer.write('\n  上下文: $detail');
    }
    record(buffer.toString(), stack: stack?.toString());
  }

  static Future<void> _flush(String text) async {
    try {
      final file = _file ?? await _resolveFile();
      if (file == null) return;
      await file.writeAsString('$text\n\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // 忽略：磁盘满、权限、路径异常都不该影响主流程。
    }
  }

  static Future<File?> _resolveFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/error-log.txt');
      // 首次创建时清掉过大的旧日志，避免无限增长。
      if (await file.exists() && await file.length() > 256 * 1024) {
        await file.writeAsString('');
      }
      _file = file;
      return file;
    } catch (_) {
      return null;
    }
  }

  /// 当前内存中的日志（最新在最后）。
  static List<String> get entries => List.unmodifiable(_entries);

  static bool get isEmpty => _entries.isEmpty;

  /// 供设置页导出。返回 null 表示当前没有可导出的内容。
  static Future<File?> exportToTemp() async {
    if (_entries.isEmpty) return null;
    try {
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/pianke-diagnostics.txt');
      final header =
          '片刻诊断日志\n'
          '导出时间：${DateTime.now().toIso8601String()}\n'
          '条目数：${_entries.length}\n'
          '${'=' * 40}\n\n';
      await out.writeAsString('$header${_entries.join('\n\n')}');
      return out;
    } catch (_) {
      return null;
    }
  }

  /// 仅供测试：清空状态。
  @visibleForTesting
  static void resetForTest() {
    _entries.clear();
    _file = null;
    _installed = false;
  }
}
