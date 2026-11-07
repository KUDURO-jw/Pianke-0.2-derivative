import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:random_movie/services/backup_snapshot.dart';

/// 上传 / 下载进度回调；[total] 小于 0 表示服务端未返回总长度。
typedef WebDavProgress = void Function(int current, int total);

/// 坚果云 WebDAV 连接配置。
class WebDavConfig {
  final String account;
  final String applicationPassword;
  final String remoteDirectory;

  const WebDavConfig({
    required this.account,
    required this.applicationPassword,
    required this.remoteDirectory,
  });

  bool get isComplete =>
      account.trim().isNotEmpty && applicationPassword.isNotEmpty;
}

class WebDavResponse {
  final int statusCode;
  final List<int> body;
  final Map<String, String> headers;

  const WebDavResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });
}

abstract interface class WebDavTransport {
  Future<WebDavResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    List<int>? body,
    WebDavProgress? onProgress,
    Duration timeout = const Duration(seconds: 30),
  });
}

class HttpWebDavTransport implements WebDavTransport {
  final HttpClient _client;

  HttpWebDavTransport({HttpClient? client}) : _client = client ?? HttpClient();

  @override
  Future<WebDavResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    List<int>? body,
    WebDavProgress? onProgress,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    HttpClientRequest? request;
    try {
      request = await _client.openUrl(method, uri).timeout(timeout);
      headers.forEach(request.headers.set);
      if (body != null) {
        request.contentLength = body.length;
        const chunkSize = 16 * 1024;
        var sent = 0;
        for (var offset = 0; offset < body.length; offset += chunkSize) {
          final end = (offset + chunkSize).clamp(0, body.length).toInt();
          final chunk = body.sublist(offset, end);
          request.add(chunk);
          sent += chunk.length;
          onProgress?.call(sent, body.length);
        }
      }

      final response = await request.close().timeout(timeout);
      final bytes = <int>[];
      final total = response.contentLength;
      var received = 0;
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        received += chunk.length;
        onProgress?.call(received, total > 0 ? total : -1);
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(',');
      });
      return WebDavResponse(
        statusCode: response.statusCode,
        body: bytes,
        headers: responseHeaders,
      );
    } on TimeoutException {
      request?.abort();
      throw const WebDavException('网络请求超时，请稍后重试');
    } on SocketException {
      request?.abort();
      throw const WebDavException('网络不可用，请检查网络连接');
    } catch (error) {
      request?.abort();
      if (error is WebDavException) rethrow;
      throw const WebDavException('网络请求失败，请稍后重试');
    }
  }

  void close() => _client.close(force: true);
}

class WebDavBackup {
  final BackupSnapshot snapshot;
  final int bytes;

  const WebDavBackup({required this.snapshot, required this.bytes});
}

class WebDavClient {
  static const endpoint = 'https://dav.jianguoyun.com/dav/';
  static const backupFileName = 'pianke_backup.json';

  final WebDavTransport _transport;
  final Uri _endpoint;

  WebDavClient({WebDavTransport? transport, Uri? endpointUri})
    : _transport = transport ?? HttpWebDavTransport(),
      _endpoint = endpointUri ?? Uri.parse(endpoint);

  Future<void> testConnection(WebDavConfig config) async {
    _validateConfig(config);
    await _ensureDirectory(config);
    final response = await _send(
      'PROPFIND',
      _directoryUri(config.remoteDirectory),
      config,
      headers: {'Depth': '0', 'Content-Type': 'application/xml'},
      body: utf8.encode('<?xml version="1.0"?><propfind xmlns="DAV:"/>'),
    );
    _ensureSuccess(response, operation: '测试连接');
  }

  Future<WebDavBackup?> download(
    WebDavConfig config, {
    WebDavProgress? onProgress,
  }) async {
    _validateConfig(config);
    final response = await _send(
      'GET',
      _fileUri(config.remoteDirectory),
      config,
      onProgress: onProgress,
    );
    if (response.statusCode == HttpStatus.notFound) return null;
    _ensureSuccess(response, operation: '下载备份');
    try {
      final payload = jsonDecode(utf8.decode(response.body));
      if (payload is! Map) throw const FormatException();
      return WebDavBackup(
        snapshot: BackupSnapshot.parse(Map<String, dynamic>.from(payload)),
        bytes: response.body.length,
      );
    } on BackupSnapshotException {
      rethrow;
    } catch (_) {
      throw const WebDavException('云端备份格式无效');
    }
  }

  Future<void> upload(
    WebDavConfig config,
    BackupSnapshot snapshot, {
    WebDavProgress? onProgress,
  }) async {
    _validateConfig(config);
    await _ensureDirectory(config);
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
    );
    final tempUri = _fileUri(
      config.remoteDirectory,
      fileName: '.pianke_backup.json.part',
    );
    final finalUri = _fileUri(config.remoteDirectory);
    final put = await _send(
      'PUT',
      tempUri,
      config,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: bytes,
      onProgress: onProgress,
    );
    _ensureSuccess(put, operation: '上传备份');

    var move = await _send(
      'MOVE',
      tempUri,
      config,
      headers: {'Destination': finalUri.toString(), 'Overwrite': 'T'},
    );

    // 坚果云即使带 Overwrite: T，也可能用 409 拒绝 MOVE 覆盖。
    // 此时先删掉旧目标文件再重试，新数据此时仍停留在临时文件里，不会丢。
    if (move.statusCode == HttpStatus.conflict) {
      final deletion = await _send('DELETE', finalUri, config);
      if (deletion.statusCode != HttpStatus.notFound) {
        _ensureSuccess(deletion, operation: '删除旧备份');
      }
      move = await _send(
        'MOVE',
        tempUri,
        config,
        headers: {'Destination': finalUri.toString(), 'Overwrite': 'T'},
      );
    }
    _ensureSuccess(move, operation: '提交备份');
  }

  Future<void> _ensureDirectory(WebDavConfig config) async {
    final parts = _directoryParts(config.remoteDirectory);
    for (var index = 0; index < parts.length; index++) {
      final path = parts.take(index + 1).join('/');
      final response = await _send('MKCOL', _directoryUri(path), config);
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const WebDavException('坚果云账号或应用密码无效');
      }
      if (response.statusCode != HttpStatus.created &&
          response.statusCode != HttpStatus.methodNotAllowed &&
          response.statusCode != HttpStatus.conflict) {
        _ensureSuccess(response, operation: '创建远程目录');
      }
    }
  }

  Future<WebDavResponse> _send(
    String method,
    Uri uri,
    WebDavConfig config, {
    Map<String, String> headers = const {},
    List<int>? body,
    WebDavProgress? onProgress,
    bool skipAuth = false,
  }) {
    final requestHeaders = <String, String>{
      'User-Agent': 'Pianke-Derivative-WebDAV/0.2',
      if (!skipAuth) 'Authorization': _authorization(config),
      ...headers,
    };
    return _transport.send(
      method,
      uri,
      headers: requestHeaders,
      body: body,
      onProgress: onProgress,
    );
  }

  String _authorization(WebDavConfig config) =>
      'Basic ${base64Encode(utf8.encode('${config.account}:${config.applicationPassword}'))}';

  void _validateConfig(WebDavConfig config) {
    if (!config.isComplete) {
      throw const WebDavException('请先填写坚果云账号和应用密码');
    }
  }

  void _ensureSuccess(WebDavResponse response, {required String operation}) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    switch (response.statusCode) {
      case HttpStatus.unauthorized:
        throw WebDavException('$operation失败：账号或应用密码无效');
      case HttpStatus.forbidden:
        throw WebDavException('$operation失败：没有远程目录权限');
      case HttpStatus.requestTimeout:
        throw WebDavException('$operation失败：服务器响应超时');
      case HttpStatus.notFound:
        throw WebDavException('$operation失败：远程目录不存在');
      default:
        throw WebDavException('$operation失败（HTTP ${response.statusCode}）');
    }
  }

  Uri _directoryUri(String directory) =>
      _buildUri(directory, trailingSlash: true);

  Uri _fileUri(String directory, {String fileName = backupFileName}) =>
      _buildUri(directory, fileName: fileName);

  Uri _buildUri(
    String directory, {
    String? fileName,
    bool trailingSlash = false,
  }) {
    final baseSegments = _endpoint.path
        .split('/')
        .where((part) => part.isNotEmpty);
    final segments = <String>[...baseSegments, ..._directoryParts(directory)];
    if (fileName != null) segments.add(fileName);
    final path = '/${segments.map(Uri.encodeComponent).join('/')}';
    return _endpoint.replace(path: '$path${trailingSlash ? '/' : ''}');
  }

  List<String> _directoryParts(String directory) {
    final value = directory.trim().replaceAll('\\', '/');
    if (value.isEmpty) return const [];
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.any((part) => part == '.' || part == '..')) {
      throw const WebDavException('远程目录路径无效');
    }
    return parts;
  }
}

class WebDavException implements Exception {
  final String message;

  const WebDavException(this.message);

  @override
  String toString() => message;
}
