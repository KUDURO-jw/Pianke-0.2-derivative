import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:random_movie/models/models.dart';
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

class BackupService {
  final StorageService _storage;

  BackupService(this._storage);

  /// 导出完整备份，通过系统分享面板让用户选择保存位置
  Future<BackupResult> exportBackup() async {
    try {
      final userId = _storage.userId;
      final userName = _storage.userName;
      final movies = await _storage.getAllMoviesForBackup();
      final drawRecords = await _storage.getAllDrawRecordsForBackup();
      final sessions = await _storage.getAllSessionsForBackup();
      final collectionsAndTags = await _storage
          .getCollectionsAndTagsForBackup();

      final now = DateTime.now();
      final payload = {
        'meta': {
          'appId': 'Pianke',
          'schemaVersion': _kSchemaVersion,
          'exportedAt': now.toIso8601String(),
        },
        'user': {'id': userId, 'name': userName},
        'movies': movies.map((m) => m.toJson()).toList(),
        'drawRecords': drawRecords.map((r) => r.toJson()).toList(),
        'viewingSessions': sessions.map((s) => s.toJson()).toList(),
        'collections': collectionsAndTags['collections'],
        'collectionMembers': collectionsAndTags['collectionMembers'],
        'tags': collectionsAndTags['tags'],
        'movieTags': collectionsAndTags['movieTags'],
      };

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
