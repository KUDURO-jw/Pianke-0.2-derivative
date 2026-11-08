// Personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:random_movie/services/update_service.dart';

enum UpdateInstallResult { launched, permissionRequired }

class UpdateDownloadException implements Exception {
  final String message;
  const UpdateDownloadException(this.message);
  @override
  String toString() => message;
}

/// Only runs after a user starts a download. APKs remain in private cache.
class UpdateDownloadService {
  static const installerChannel = MethodChannel('app.pianke.personal/update');
  static const maxApkBytes = 200 * 1024 * 1024;
  final Dio _dio;
  final Future<Directory> Function() _cacheDirectory;
  bool _active = false;

  UpdateDownloadService({
    Dio? dio,
    Future<Directory> Function()? cacheDirectory,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 60),
             ),
           ),
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory;

  Future<String> download(
    AppUpdateInfo update, {
    required CancelToken cancelToken,
    required ProgressCallback onProgress,
    VoidCallback? onVerifying,
  }) async {
    if (_active) throw const UpdateDownloadException('已有下载正在处理，请稍候');
    final uri = Uri.tryParse(update.downloadUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const UpdateDownloadException('下载地址无效，请重新检查更新');
    }
    if (update.versionCode == null ||
        update.versionCode! <= 0 ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(update.sha256)) {
      throw const UpdateDownloadException('此更新缺少安装包校验信息，请重新检查更新');
    }
    _active = true;
    File? partial;
    try {
      _checkCancelled(cancelToken);
      final directory = Directory(
        p.join((await _cacheDirectory()).path, 'updates'),
      );
      await directory.create(recursive: true);
      final target = File(
        p.join(directory.path, 'Pianke-UI-${update.versionCode}.apk'),
      );
      if (await target.exists()) {
        onVerifying?.call();
        if (await _matches(target, update.sha256, cancelToken)) {
          return target.path;
        }
        await target.delete();
      }
      partial = File('${target.path}.part');
      if (await partial.exists()) await partial.delete();
      await _receive(update.downloadUrl, partial, cancelToken, onProgress);
      _checkCancelled(cancelToken);
      onVerifying?.call();
      if (!await _matches(partial, update.sha256, cancelToken)) {
        throw const UpdateDownloadException('安装包校验失败，请重新下载');
      }
      _checkCancelled(cancelToken);
      await partial.rename(target.path);
      // Retain just the latest verified APK, without touching other cache data.
      await for (final entry in directory.list()) {
        if (entry is File &&
            entry.path != target.path &&
            RegExp(
              r'^Pianke-UI-\d+\.apk(?:\.part)?$',
            ).hasMatch(p.basename(entry.path))) {
          try {
            await entry.delete();
          } on FileSystemException {
            /* Best effort. */
          }
        }
      }
      return target.path;
    } finally {
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } finally {
        _active = false;
      }
    }
  }

  Future<void> _receive(
    String url,
    File file,
    CancelToken token,
    ProgressCallback onProgress,
  ) async {
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        maxRedirects: 5,
        receiveDataWhenStatusError: false,
        headers: {
          'Accept': 'application/octet-stream',
          'Accept-Encoding': 'identity',
        },
        validateStatus: (status) => status == 200,
      ),
    );
    final body = response.data;
    if (body == null) throw const UpdateDownloadException('服务器未返回安装包，请重试');
    var consumed = false;
    try {
      if (response.realUri.scheme != 'https') {
        throw const UpdateDownloadException('下载地址发生不安全跳转，请重新检查更新');
      }
      final total =
          int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
      if (total > maxApkBytes) {
        throw const UpdateDownloadException('安装包体积异常，已停止下载');
      }
      final output = await file.open(mode: FileMode.write);
      try {
        var received = 0;
        consumed = true;
        await for (final chunk in body.stream) {
          _checkCancelled(token);
          received += chunk.length;
          if (received > maxApkBytes) {
            throw const UpdateDownloadException('安装包体积异常，已停止下载');
          }
          await output.writeFrom(chunk);
          _checkCancelled(token);
          onProgress(received, total);
        }
      } finally {
        // Close the handle before cancellation/error cleanup, including on Windows.
        await output.close();
      }
    } finally {
      if (!consumed) await body.stream.listen(null).cancel();
    }
  }

  Future<bool> _matches(File file, String expected, CancelToken token) async {
    _checkCancelled(token);
    final length = await file.length();
    if (length == 0 || length > maxApkBytes) return false;
    final digest = await crypto.sha256.bind(file.openRead()).first;
    _checkCancelled(token);
    return digest.toString() == expected.toLowerCase();
  }

  Future<UpdateInstallResult> install(String path, int versionCode) async {
    final result = await installerChannel.invokeMethod<String>(
      'installUpdate',
      {'path': path, 'versionCode': versionCode},
    );
    if (result == 'permissionRequired') {
      return UpdateInstallResult.permissionRequired;
    }
    if (result != 'launched') {
      throw const UpdateDownloadException('未能打开系统安装界面，请重试');
    }
    return UpdateInstallResult.launched;
  }

  void _checkCancelled(CancelToken token) {
    if (token.isCancelled) throw token.cancelError!;
  }
}
