import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 同步快照格式版本。改动载荷结构时递增，旧版本快照会被拒绝解析。
const int syncSnapshotFormatVersion = 1;

/// 带校验值的备份快照。
///
/// 在普通备份载荷外附加 `sync` 段（格式版本、更新时间、SHA-256 校验值），
/// 用于 WebDAV 同步时判断本地与云端是否发生变化、以及校验下载内容是否完整。
class BackupSnapshot {
  final Map<String, dynamic> payload;
  final DateTime updatedAt;
  final String checksum;

  const BackupSnapshot._({
    required this.payload,
    required this.updatedAt,
    required this.checksum,
  });

  factory BackupSnapshot.create(
    Map<String, dynamic> payload, {
    DateTime? updatedAt,
  }) {
    final timestamp = updatedAt ?? DateTime.now();
    final base = _copyMap(payload);
    base['sync'] = {
      'formatVersion': syncSnapshotFormatVersion,
      'updatedAt': timestamp.toUtc().toIso8601String(),
    };
    final checksum = _checksum(base);
    (base['sync'] as Map<String, dynamic>)['checksum'] = checksum;
    return BackupSnapshot._(
      payload: base,
      updatedAt: timestamp,
      checksum: checksum,
    );
  }

  factory BackupSnapshot.parse(Map<String, dynamic> payload) {
    final meta = payload['meta'];
    if (meta is! Map || meta['appId']?.toString() != 'Pianke') {
      throw const BackupSnapshotException('不是有效的片刻备份');
    }

    final sync = payload['sync'];
    if (sync is! Map ||
        sync['formatVersion'] != syncSnapshotFormatVersion ||
        sync['checksum']?.toString().isEmpty != false) {
      throw const BackupSnapshotException('备份缺少同步元数据');
    }

    final updatedAt = DateTime.tryParse(sync['updatedAt']?.toString() ?? '');
    final checksum = sync['checksum'].toString();
    if (updatedAt == null || checksum != _checksum(_withoutChecksum(payload))) {
      throw const BackupSnapshotException('备份校验失败，文件可能已损坏');
    }

    return BackupSnapshot._(
      payload: _copyMap(payload),
      updatedAt: updatedAt,
      checksum: checksum,
    );
  }

  Map<String, dynamic> toJson() => _copyMap(payload);

  int get movieCount => _listLength('movies');
  int get sessionCount => _listLength('viewingSessions');
  int get drawRecordCount => _listLength('drawRecords');

  int _listLength(String key) {
    final value = payload[key];
    return value is List ? value.length : 0;
  }

  static String _checksum(Map<String, dynamic> payload) {
    final stablePayload = _copyMap(payload);
    final meta = stablePayload['meta'];
    if (meta is Map<String, dynamic>) {
      meta.remove('exportedAt');
    }
    final sync = stablePayload['sync'];
    if (sync is Map<String, dynamic>) {
      sync.remove('updatedAt');
      sync.remove('checksum');
    }
    final normalized = _normalize(stablePayload);
    return sha256.convert(utf8.encode(jsonEncode(normalized))).toString();
  }

  static Map<String, dynamic> _withoutChecksum(Map<String, dynamic> payload) {
    final copy = _copyMap(payload);
    final sync = copy['sync'];
    if (sync is Map<String, dynamic>) {
      sync.remove('checksum');
    }
    return copy;
  }

  static Map<String, dynamic> _copyMap(Map<dynamic, dynamic> value) {
    return Map<String, dynamic>.from(_normalize(value) as Map);
  }

  static dynamic _normalize(dynamic value) {
    if (value is Map) {
      final sorted = SplayTreeMap<String, dynamic>();
      for (final entry in value.entries) {
        sorted[entry.key.toString()] = _normalize(entry.value);
      }
      return sorted;
    }
    if (value is Iterable) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
  }
}

class BackupSnapshotException implements Exception {
  final String message;

  const BackupSnapshotException(this.message);

  @override
  String toString() => message;
}
