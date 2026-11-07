import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/backup_snapshot.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:share_plus/share_plus.dart';

const int _kSchemaVersion = 3;

class BackupResult {
  final bool success;
  final String? message;
  final BackupStats? stats;

  const BackupResult({required this.success, this.message, this.stats});
}

class BackupStats {
  final int movieCount;
  final int drawRecordCount;
  final int sessionCount;
  final DateTime exportedAt;

  const BackupStats({
    required this.movieCount,
    required this.drawRecordCount,
    required this.sessionCount,
    required this.exportedAt,
  });
}

class RestoreResult {
  final bool success;
  final String? message;
  final RestoreStats? stats;

  const RestoreResult({required this.success, this.message, this.stats});
}

class RestoreStats {
  final int moviesImported;
  final int moviesSkipped;
  final int drawRecordsImported;
  final int drawRecordsSkipped;
  final int sessionsImported;

  const RestoreStats({
    required this.moviesImported,
    required this.moviesSkipped,
    required this.drawRecordsImported,
    required this.drawRecordsSkipped,
    this.sessionsImported = 0,
  });
}

abstract interface class SyncBackupStore {
  Future<BackupSnapshot> createSyncSnapshot();
  Future<RestoreStats> restoreSyncSnapshot(BackupSnapshot snapshot);

  /// 覆盖本地数据前的兜底备份。实现返回落盘路径，失败返回 null。
  /// 失败不应阻断同步流程。
  Future<String?> createLocalSafetyBackup();
}

class BackupService implements SyncBackupStore {
  final StorageService _storage;

  BackupService(this._storage);

  /// 启动兜底：「从云端恢复」会整份替换本地数据，这里先把当前状态
  /// 静默写入应用文档目录，恢复后若发现选错，用户还能找回上一次数据。
  ///
  /// 与 [exportBackup] 的区别：不弹分享面板，直接落盘，返回文件路径。
  @override
  Future<String?> createLocalSafetyBackup() async {
    try {
      final payload = await _collectPayload(includeUserIdentity: true);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/pianke_safety');
      if (!folder.existsSync()) {
        await folder.create(recursive: true);
      }
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${folder.path}/safety_$stamp.json');
      await file.writeAsString(jsonStr, encoding: utf8);
      await _pruneSafetyBackups(folder);
      return file.path;
    } catch (_) {
      // 兜底备份失败不应阻断同步流程，交由调用方继续。
      return null;
    }
  }

  /// 只保留最近 [keep] 份兜底备份，避免无限增长。
  Future<void> _pruneSafetyBackups(Directory folder, {int keep = 5}) async {
    try {
      final files = <File>[];
      await for (final entity in folder.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          files.add(entity);
        }
      }
      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      for (final file in files.skip(keep)) {
        await file.delete();
      }
    } catch (_) {
      // 清理失败不影响主流程。
    }
  }

  /// 导出完整备份，通过系统分享面板让用户选择保存位置
  Future<BackupResult> exportBackup() async {
    try {
      final now = DateTime.now();
      final payload = await _collectPayload(includeUserIdentity: true);
      final movies = payload['movies'] as List<dynamic>;
      final drawRecords = payload['drawRecords'] as List<dynamic>;
      final sessions = payload['viewingSessions'] as List<dynamic>;

      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      final fileName =
          'pianke_backup_${DateFormat('yyyyMMdd_HHmmss').format(now)}.json';

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(jsonStr, encoding: utf8);

      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/json'),
      ], subject: '片刻备份文件');

      return BackupResult(
        success: true,
        message: '备份已导出',
        stats: BackupStats(
          movieCount: movies.length,
          drawRecordCount: drawRecords.length,
          sessionCount: sessions.length,
          exportedAt: now,
        ),
      );
    } catch (e) {
      return BackupResult(success: false, message: '导出失败：$e');
    }
  }

  @override
  Future<BackupSnapshot> createSyncSnapshot() async {
    final payload = await _collectPayload(includeUserIdentity: false);
    return BackupSnapshot.create(payload);
  }

  @override
  Future<RestoreStats> restoreSyncSnapshot(BackupSnapshot snapshot) async {
    final validated = BackupSnapshot.parse(snapshot.toJson());
    final payload = validated.toJson();
    final movies = _parseMovies(payload['movies']);
    final drawRecords = _parseDrawRecords(payload['drawRecords']);
    final sessions = _parseSessions(payload['viewingSessions']);
    final tableData = _parseTableData(payload);

    await _storage.replaceBackupData(
      movies: movies,
      drawRecords: drawRecords,
      sessions: sessions,
      tableData: tableData,
    );

    final settings = payload['settings'];
    if (settings is Map) {
      final userName = settings['userName']?.toString().trim() ?? '';
      if (userName.isNotEmpty) await _storage.updateUserName(userName);
      final themeMode = settings['themeMode']?.toString();
      if (themeMode == 'system' ||
          themeMode == 'light' ||
          themeMode == 'dark') {
        await _storage.setThemeMode(themeMode!);
      }
    }

    return RestoreStats(
      moviesImported: movies.length,
      moviesSkipped: 0,
      drawRecordsImported: drawRecords.length,
      drawRecordsSkipped: 0,
      sessionsImported: sessions.length,
    );
  }

  Future<Map<String, dynamic>> _collectPayload({
    required bool includeUserIdentity,
  }) async {
    final movies = await _storage.getAllMoviesForBackup();
    final drawRecords = await _storage.getAllDrawRecordsForBackup();
    final sessions = await _storage.getAllSessionsForBackup();
    final collectionsAndTags = await _storage.getCollectionsAndTagsForBackup();
    return {
      'meta': {
        'appId': 'Pianke',
        'schemaVersion': _kSchemaVersion,
        'exportedAt': DateTime.now().toIso8601String(),
      },
      if (includeUserIdentity)
        'user': {'id': _storage.userId, 'name': _storage.userName},
      'settings': {
        'themeMode': _storage.getThemeMode(),
        'userName': _storage.userName,
      },
      'movies': movies.map((m) => m.toJson()).toList(),
      'drawRecords': drawRecords.map((r) => r.toJson()).toList(),
      'viewingSessions': sessions.map((s) => s.toJson()).toList(),
      'collections': collectionsAndTags['collections'],
      'collectionMembers': collectionsAndTags['collectionMembers'],
      'tags': collectionsAndTags['tags'],
      'movieTags': collectionsAndTags['movieTags'],
    };
  }

  List<Movie> _parseMovies(dynamic raw) {
    if (raw is! List) throw const BackupSnapshotException('备份缺少片库数据');
    final result = <Movie>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map) throw const BackupSnapshotException('片库数据格式错误');
      final movie = Movie.fromJson(Map<String, dynamic>.from(item));
      if (movie.id.trim().isEmpty || !ids.add(movie.id)) {
        throw const BackupSnapshotException('片库包含无效或重复 ID');
      }
      result.add(movie);
    }
    return result;
  }

  List<DrawRecord> _parseDrawRecords(dynamic raw) {
    if (raw is! List) {
      throw const BackupSnapshotException('备份缺少抽片记录');
    }
    final result = <DrawRecord>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map) throw const BackupSnapshotException('抽片记录格式错误');
      final record = DrawRecord.fromJson(Map<String, dynamic>.from(item));
      if (record.id.trim().isEmpty || !ids.add(record.id)) {
        throw const BackupSnapshotException('抽片记录包含无效或重复 ID');
      }
      result.add(record);
    }
    return result;
  }

  List<ViewingSession> _parseSessions(dynamic raw) {
    if (raw is! List) {
      throw const BackupSnapshotException('备份缺少观影记录');
    }
    final result = <ViewingSession>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map) throw const BackupSnapshotException('观影记录格式错误');
      final session = ViewingSession.fromJson(Map<String, dynamic>.from(item));
      if (session.id.trim().isEmpty ||
          session.movieId.trim().isEmpty ||
          !ids.add(session.id)) {
        throw const BackupSnapshotException('观影记录包含无效或重复 ID');
      }
      result.add(session);
    }
    return result;
  }

  Map<String, List<Map<String, Object?>>> _parseTableData(
    Map<String, dynamic> payload,
  ) {
    final result = <String, List<Map<String, Object?>>>{};
    for (final key in const [
      'collections',
      'collectionMembers',
      'tags',
      'movieTags',
    ]) {
      final raw = payload[key];
      if (raw is! List) throw BackupSnapshotException('备份缺少 $key 数据');
      result[key] = raw
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
    }
    return result;
  }

  /// 从文件选择器读取备份文件，合并恢复数据
  Future<RestoreResult> importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return const RestoreResult(success: false, message: '已取消');
      }

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        return const RestoreResult(success: false, message: '无法读取文件内容');
      }

      final jsonStr = utf8.decode(bytes);
      final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        return const RestoreResult(
          success: false,
          message: '文件格式错误，不是有效的 JSON',
        );
      }

      final meta = payload['meta'] as Map<String, dynamic>?;
      if (meta == null) {
        return const RestoreResult(success: false, message: '不是片刻的备份文件');
      }
      final appId = meta['appId']?.toString();
      if (appId != 'Pianke' && appId != 'RandoMov') {
        return const RestoreResult(success: false, message: '不是片刻的备份文件');
      }

      final schemaVersion = meta['schemaVersion'] as int? ?? 0;
      if (schemaVersion > _kSchemaVersion) {
        return const RestoreResult(
          success: false,
          message: '备份文件版本太新，请升级应用后再恢复',
        );
      }

      final stats = await _restorePayload(payload);
      return RestoreResult(success: true, message: '恢复完成', stats: stats);
    } catch (e) {
      return RestoreResult(success: false, message: '恢复失败：$e');
    }
  }

  Future<RestoreStats> _restorePayload(Map<String, dynamic> payload) async {
    int moviesImported = 0;
    int moviesSkipped = 0;
    int drawRecordsImported = 0;
    int drawRecordsSkipped = 0;
    int sessionsImported = 0;

    final moviesJson = payload['movies'] as List<dynamic>? ?? [];
    for (final raw in moviesJson) {
      if (raw is! Map) continue;
      try {
        final movie = Movie.fromJson(Map<String, dynamic>.from(raw));
        if (movie.id.isEmpty) {
          moviesSkipped++;
          continue;
        }
        final existing = await _storage.getMovieById(movie.id);
        if (existing != null) {
          moviesSkipped++;
          continue;
        }
        await _storage.addMovieDirectly(movie);
        moviesImported++;
      } catch (_) {
        moviesSkipped++;
      }
    }

    final recordsJson = payload['drawRecords'] as List<dynamic>? ?? [];
    for (final raw in recordsJson) {
      if (raw is! Map) continue;
      try {
        final record = DrawRecord.fromJson(Map<String, dynamic>.from(raw));
        if (record.id.isEmpty) {
          drawRecordsSkipped++;
          continue;
        }
        final imported = await _storage.addDrawRecordIfNotExists(record);
        if (imported) {
          drawRecordsImported++;
        } else {
          drawRecordsSkipped++;
        }
      } catch (_) {
        drawRecordsSkipped++;
      }
    }

    final sessionsRaw = payload['viewingSessions'];
    if (sessionsRaw is List) {
      // schemaVersion >= 2：直接恢复会话
      for (final raw in sessionsRaw) {
        if (raw is! Map) continue;
        try {
          final session = ViewingSession.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (await _storage.addSessionIfNotExists(session)) {
            sessionsImported++;
          }
        } catch (_) {}
      }
    } else {
      // 旧版备份（无会话）：为标记看过的影片补一条会话，避免观影记录丢失
      for (final raw in moviesJson) {
        if (raw is! Map) continue;
        try {
          final json = Map<String, dynamic>.from(raw);
          if (json['watched'] != true) continue;
          final movieId =
              json['id']?.toString() ?? json['_id']?.toString() ?? '';
          if (movieId.isEmpty) continue;
          if (await _storage.movieHasSession(movieId)) continue;
          final watchedAt = json['watchedAt'] != null
              ? DateTime.tryParse(json['watchedAt'].toString())
              : null;
          final session = ViewingSession(
            id: 'vs_imported_$movieId',
            movieId: movieId,
            watchedAt: watchedAt ?? DateTime.now(),
            note: json['userReview']?.toString() ?? '',
            rating: (json['userRating'] as num?)?.toDouble(),
          );
          if (await _storage.addSessionIfNotExists(session)) {
            sessionsImported++;
          }
        } catch (_) {}
      }
    }

    // schemaVersion >= 3：恢复合集与标签（主键冲突则忽略）。
    try {
      await _storage.restoreCollectionsAndTags(payload);
    } catch (_) {}

    return RestoreStats(
      moviesImported: moviesImported,
      moviesSkipped: moviesSkipped,
      drawRecordsImported: drawRecordsImported,
      drawRecordsSkipped: drawRecordsSkipped,
      sessionsImported: sessionsImported,
    );
  }
}
