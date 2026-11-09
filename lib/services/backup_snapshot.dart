// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 同步快照格式版本。改动载荷结构时递增，旧版本快照会被拒绝解析。
const int syncSnapshotFormatVersion = 1;

/// 数据合约版本：备份文件 `meta.schemaVersion` 与本地数据库共同遵守的版本。
///
/// 云端文件用它声明「这份数据由第几版结构写出」。本机版本低于它时说明云端
/// 比这台设备新，本机绝不允许上传覆盖（见 [BackupTooNewException]）。
const int kDataSchemaVersion = 3;

/// 读取载荷声明的数据版本；缺失或格式不对时按 0（最老的备份）处理。
int readPayloadSchemaVersion(Map<String, dynamic> payload) {
  final meta = payload['meta'];
  if (meta is! Map) return 0;
  final raw = meta['schemaVersion'];
  if (raw is int) return raw < 0 ? 0 : raw;
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

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

    // 先读版本、再校验内容：版本比本机新时，内容根本无从解读，
    // 也不能让它在后续流程里被「理解成缺字段」再写回云端。
    final remoteSchema = readPayloadSchemaVersion(payload);
    if (remoteSchema > kDataSchemaVersion) {
      throw BackupTooNewException(remoteSchema);
    }

    final sync = payload['sync'];
    if (sync is! Map) {
      throw const BackupSnapshotException('备份缺少同步元数据');
    }
    final formatVersion = sync['formatVersion'] is int
        ? sync['formatVersion'] as int
        : int.tryParse(sync['formatVersion']?.toString() ?? '');
    if (formatVersion == null) {
      throw const BackupSnapshotException('备份缺少同步元数据');
    }
    if (formatVersion > syncSnapshotFormatVersion) {
      // 用数据版本表述更贴近用户认知，也不泄露内部格式细节。
      throw BackupTooNewException(remoteSchema, remoteFormat: formatVersion);
    }
    if (formatVersion < 1 || sync['checksum']?.toString().isEmpty != false) {
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

  /// 这份数据声明的结构版本（`meta.schemaVersion`），缺失按 0 处理。
  int get schemaVersion => readPayloadSchemaVersion(payload);

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

/// 云端数据来自更新版本的片刻。
///
/// 这个异常是「单向闸门」的信号：一旦抛出，本机就不能上传、不能覆盖云端，
/// 否则老版本的 [Movie.fromJson] 会把不认识的字段丢掉，再写回就永久丢失。
class BackupTooNewException extends BackupSnapshotException {
  /// 云端声明的数据结构版本（`meta.schemaVersion`）。
  final int remoteSchema;

  /// 云端声明的快照格式版本（`sync.formatVersion`），未知时为 null。
  final int? remoteFormat;

  const BackupTooNewException(this.remoteSchema, {this.remoteFormat})
    : super('云端数据来自更新版本的片刻，请先在这台设备上升级应用后再同步');
  @override
  String toString() => '$message（云端 v$remoteSchema，本机 v$kDataSchemaVersion）';
}
