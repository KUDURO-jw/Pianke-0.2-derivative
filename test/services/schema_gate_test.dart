// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/backup_snapshot.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/services/webdav_client.dart';
import 'package:random_movie/services/webdav_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 构造一份可被 [BackupSnapshot.create] 序列化的完整载荷。
Map<String, dynamic> _payload({required int schema}) => {
  'meta': {'appId': 'Pianke', 'schemaVersion': schema},
  'settings': {'themeMode': 'system'},
  'movies': [
    {'id': 'm1', 'title': '本地影片', 'poster': 'https://example.com/p.jpg'},
  ],
  'drawRecords': <Map<String, dynamic>>[],
  'viewingSessions': <Map<String, dynamic>>[],
  'collections': <Map<String, dynamic>>[],
  'collectionMembers': <Map<String, dynamic>>[],
  'tags': <Map<String, dynamic>>[],
  'movieTags': <Map<String, dynamic>>[],
};

class _Credentials implements SyncCredentialStore {
  @override
  Future<String?> readPassword() async => 'secret';

  @override
  Future<void> writePassword(String value) async {}

  @override
  Future<void> deletePassword() async {}
}

class _FakeBackupStore implements SyncBackupStore {
  BackupSnapshot local;
  bool restored = false;

  _FakeBackupStore(this.local);

  @override
  Future<BackupSnapshot> createSyncSnapshot() async => local;

  @override
  Future<String?> createLocalSafetyBackup() async => '/tmp/safety.json';

  @override
  Future<RestoreStats> restoreSyncSnapshot(BackupSnapshot snapshot) async {
    restored = true;
    return const RestoreStats(
      moviesImported: 1,
      moviesSkipped: 0,
      drawRecordsImported: 0,
      drawRecordsSkipped: 0,
    );
  }
}

/// 只提供 GET/PROPFIND 的最小 WebDAV 传输：下载返回指定 JSON。
class _DownloadTransport implements WebDavTransport {
  final String remoteJson;
  final List<String> methods = [];

  _DownloadTransport(this.remoteJson);

  @override
  Future<WebDavResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    List<int>? body,
    WebDavProgress? onProgress,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    methods.add(method);
    if (method == 'GET') {
      return WebDavResponse(
        statusCode: HttpStatus.ok,
        body: utf8.encode(remoteJson),
      );
    }
    return const WebDavResponse(statusCode: HttpStatus.ok, body: <int>[]);
  }
}

void main() {
  group('T1 版本兼容闸门', () {
    test('云端 schema 比本机新：BackupSnapshot.parse 抛 BackupTooNewException', () {
      final snapshot = BackupSnapshot.create(_payload(schema: 4));
      expect(
        () => BackupSnapshot.parse(snapshot.toJson()),
        throwsA(
          isA<BackupTooNewException>().having(
            (e) => e.remoteSchema,
            'remoteSchema',
            4,
          ),
        ),
      );
    });

    test('提示语明确要求先升级这台设备', () {
      final snapshot = BackupSnapshot.create(_payload(schema: 9));
      try {
        BackupSnapshot.parse(snapshot.toJson());
        fail('应当抛出 BackupTooNewException');
      } on BackupTooNewException catch (error) {
        expect(error.message, contains('升级'));
        expect(error.message, isNot(contains('缺少同步元数据')));
      }
    });

    test('云端 schema == 本机：行为与之前一致（回归）', () {
      final snapshot = BackupSnapshot.create(_payload(schema: 3));
      final parsed = BackupSnapshot.parse(snapshot.toJson());
      expect(parsed.schemaVersion, 3);
      expect(parsed.checksum, snapshot.checksum);
    });

    test('旧备份（schemaVersion 1 / 2）仍能解析并通过导入预览', () {
      for (final schema in [1, 2]) {
        final payload = _payload(schema: schema);
        final parsed = BackupSnapshot.parse(
          BackupSnapshot.create(payload).toJson(),
        );
        expect(parsed.schemaVersion, schema);

        final preview = BackupImportPreview.parse(payload);
        expect(preview.schemaVersion, schema);
        expect(preview.inventory.movies, 1);
      }
    });

    test('备份文件版本太新：导入预览给出可读提示', () {
      expect(
        () => BackupImportPreview.parse(_payload(schema: 99)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('升级'),
          ),
        ),
      );
    });

    test('未知字段不会被静默丢弃：schema 相同则内容逐字保留', () {
      final payload = _payload(schema: 3);
      (payload['movies'] as List).first['futureField'] = 'keep-me';
      final roundTrip = BackupSnapshot.parse(
        BackupSnapshot.create(payload).toJson(),
      ).toJson();
      expect(
        ((roundTrip['movies'] as List).first as Map)['futureField'],
        'keep-me',
      );
    });

    test('formatVersion 高于当前：同样抛 BackupTooNewException', () {
      final payload = _payload(schema: 3)..['sync'] = {'formatVersion': 2};
      expect(
        () => BackupSnapshot.parse(payload),
        throwsA(isA<BackupTooNewException>()),
      );
    });

    test('未来 formatVersion 但数据版本相同也不会被当成「缺少同步元数据」', () {
      final payload = _payload(schema: 3)..['sync'] = {'formatVersion': 2};
      try {
        BackupSnapshot.parse(payload);
        fail('应当抛出');
      } on BackupSnapshotException catch (error) {
        expect(error.message, isNot(contains('缺少同步元数据')));
      }
    });
  });

  group('T1 同步闸门：老设备绝不覆盖新云端', () {
    test('云端 schema=4、本机=3：同步失败且没有任何 PUT / MOVE', () async {
      SharedPreferences.setMockInitialValues({
        'pianke_webdav_account': 'user',
        'pianke_webdav_directory': 'Pianke',
      });
      final remoteJson = jsonEncode(
        BackupSnapshot.create(_payload(schema: 4)).toJson(),
      );
      final transport = _DownloadTransport(remoteJson);
      final store = _FakeBackupStore(
        BackupSnapshot.create(_payload(schema: 3)),
      );
      final service = WebDavSyncService(
        backup: store,
        preferences: await SharedPreferences.getInstance(),
        client: WebDavClient(transport: transport),
        credentials: _Credentials(),
      );

      final outcome = await service.synchronize();

      expect(outcome.state, WebDavSyncState.failure);
      expect(outcome.action, WebDavSyncAction.none);
      expect(outcome.message, contains('升级'));
      expect(transport.methods, isNot(contains('PUT')));
      expect(transport.methods, isNot(contains('MOVE')));
      expect(store.restored, isFalse);
    });

    test('云端 schema=4 时即使强制上传也被拦下', () async {
      SharedPreferences.setMockInitialValues({
        'pianke_webdav_account': 'user',
        'pianke_webdav_directory': 'Pianke',
      });
      final remoteJson = jsonEncode(
        BackupSnapshot.create(_payload(schema: 4)).toJson(),
      );
      final transport = _DownloadTransport(remoteJson);
      final service = WebDavSyncService(
        backup: _FakeBackupStore(BackupSnapshot.create(_payload(schema: 3))),
        preferences: await SharedPreferences.getInstance(),
        client: WebDavClient(transport: transport),
        credentials: _Credentials(),
      );

      final outcome = await service.synchronize(
        direction: WebDavSyncDirection.upload,
      );

      expect(outcome.state, WebDavSyncState.failure);
      expect(transport.methods, isNot(contains('PUT')));
    });

    test('云端 schema=3 时照常上传（回归）', () async {
      SharedPreferences.setMockInitialValues({
        'pianke_webdav_account': 'user',
        'pianke_webdav_directory': 'Pianke',
        // 让本地被判定为「有改动」，从而走上传分支。
        'pianke_webdav_base_local_checksum': 'stale-local',
        'pianke_webdav_base_remote_checksum': 'stale-remote',
      });
      final remoteJson = jsonEncode(
        BackupSnapshot.create(_payload(schema: 3)).toJson(),
      );
      final transport = _DownloadTransport(remoteJson);
      final service = WebDavSyncService(
        backup: _FakeBackupStore(BackupSnapshot.create(_payload(schema: 3))),
        preferences: await SharedPreferences.getInstance(),
        client: WebDavClient(transport: transport),
        credentials: _Credentials(),
      );

      final outcome = await service.synchronize(
        direction: WebDavSyncDirection.upload,
      );

      expect(outcome.state, WebDavSyncState.success);
      expect(transport.methods, contains('PUT'));
    });
  });

  group('T1 数据库降级', () {
    test('DatabaseTooNewException 的提示指向「安装不低于该版本」', () {
      const error = DatabaseTooNewException(8, 7);
      expect(error.message, contains('更新版本'));
      expect(error.message, contains('v8'));
      expect(error.fileVersion, 8);
      expect(error.appVersion, 7);
    });  });
}
