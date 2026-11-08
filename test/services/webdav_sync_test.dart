import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/backup_snapshot.dart';
import 'package:random_movie/services/webdav_client.dart';
import 'package:random_movie/services/webdav_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:random_movie/services/local_data_guard.dart';

BackupSnapshot _snapshot(String marker) => BackupSnapshot.create({
  'meta': {'appId': 'Pianke', 'schemaVersion': 3},
  'settings': {'themeMode': 'system'},
  'movies': [
    {'id': marker, 'title': marker, 'poster': 'https://example.com/poster.jpg'},
  ],
  'drawRecords': <Map<String, dynamic>>[],
  'viewingSessions': <Map<String, dynamic>>[],
  'collections': <Map<String, dynamic>>[],
  'collectionMembers': <Map<String, dynamic>>[],
  'tags': <Map<String, dynamic>>[],
  'movieTags': <Map<String, dynamic>>[],
}, updatedAt: DateTime.utc(2026, 1, 1));

class _FakeTransport implements WebDavTransport {
  final List<String> methods = [];
  final List<Uri> uris = [];
  final List<Map<String, String>> headers = [];
  final List<WebDavResponse> responses;

  _FakeTransport(this.responses);

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
    uris.add(uri);
    this.headers.add(headers);
    onProgress?.call(body?.length ?? 0, body?.length ?? -1);
    if (responses.isEmpty) {
      throw StateError('No fake response');
    }
    return responses.removeAt(0);
  }
}

class _FakeCredentials implements SyncCredentialStore {
  String password;

  _FakeCredentials(this.password);

  @override
  Future<String?> readPassword() async => password;

  @override
  Future<void> writePassword(String value) async => password = value;

  @override
  Future<void> deletePassword() async => password = '';
}

class _FakeBackupStore implements SyncBackupStore {
  BackupSnapshot local;
  BackupSnapshot? restored;
  int safetyBackupCount = 0;

  _FakeBackupStore(this.local);

  @override
  Future<BackupSnapshot> createSyncSnapshot() async => local;

  @override
  Future<String?> createLocalSafetyBackup() async {
    safetyBackupCount++;
    return '/tmp/safety_backup.json';
  }

  @override
  Future<RestoreStats> restoreSyncSnapshot(BackupSnapshot snapshot) async {
    restored = snapshot;
    local = snapshot;
    return const RestoreStats(
      moviesImported: 1,
      moviesSkipped: 0,
      drawRecordsImported: 0,
      drawRecordsSkipped: 0,
    );
  }
}

void main() {
  test(
    'opening an editor during credential loading cancels automatic sync',
    () async {
      SharedPreferences.setMockInitialValues({'pianke_webdav_account': 'user'});
      final credentials = _DelayedCredentials('secret');
      final transport = _FakeTransport([]);
      final service = WebDavSyncService(
        backup: _FakeBackupStore(_snapshot('local')),
        preferences: await SharedPreferences.getInstance(),
        credentials: credentials,
        client: WebDavClient(transport: transport),
      );
      final result = service.synchronizeAutomatically();
      final owner = Object();
      LocalDataGuard.hold(owner);
      try {
        credentials.ready.complete();
        expect((await result).state, WebDavSyncState.idle);
        expect(transport.methods, isEmpty);
      } finally {
        LocalDataGuard.release(owner);
      }
    },
  );
  test(
    'editing skips automatic requests and releases after editor closes',
    () async {
      SharedPreferences.setMockInitialValues({'pianke_webdav_account': 'user'});
      final transport = _FakeTransport([]);
      final service = WebDavSyncService(
        backup: _FakeBackupStore(_snapshot('local')),
        preferences: await SharedPreferences.getInstance(),
        credentials: _FakeCredentials('secret'),
        client: WebDavClient(transport: transport),
      );
      final owner = Object();
      LocalDataGuard.hold(owner);
      try {
        final outcome = await service.synchronizeAutomatically();
        expect(outcome.state, WebDavSyncState.idle);
        expect(transport.methods, isEmpty);
      } finally {
        LocalDataGuard.release(owner);
      }
    },
  );

  test(
    'changed preview stops restore, records failure and preserves prior success',
    () async {
      SharedPreferences.setMockInitialValues({
        'pianke_webdav_account': 'user',
        'pianke_webdav_last_sync_at': '2026-01-01',
      });
      final remote = _snapshot('remote');
      final store = _FakeBackupStore(_snapshot('local'));
      final transport = _FakeTransport([
        for (var i = 0; i < 2; i++)
          WebDavResponse(
            statusCode: 200,
            body: utf8.encode(jsonEncode(remote.toJson())),
          ),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final service = WebDavSyncService(
        backup: store,
        preferences: prefs,
        credentials: _FakeCredentials('secret'),
        client: WebDavClient(transport: transport),
      );
      final preview = await service.inspect();
      store.local = _snapshot('changed');
      final outcome = await service.synchronize(
        direction: WebDavSyncDirection.download,
        conflictChoice: WebDavConflictChoice.remote,
        expectedInspection: preview,
      );
      expect(outcome.isSuccess, isFalse);
      expect(outcome.message, contains('预览后数据已变化'));
      expect(store.restored, isNull);
      expect(service.lastAttemptFailed, isTrue);
      expect(service.lastSuccessAt?.year, 2026);
      expect(service.lastSuccessAt?.month, 1);
      expect(service.statusMessage, outcome.message);
    },
  );

  test(
    'local change during backup creation prevents late destructive restore',
    () async {
      SharedPreferences.setMockInitialValues({'pianke_webdav_account': 'user'});
      final store = _ChangingBackupStore(_snapshot('local'));
      final remote = _snapshot('remote');
      final service = WebDavSyncService(
        backup: store,
        preferences: await SharedPreferences.getInstance(),
        credentials: _FakeCredentials('secret'),
        client: WebDavClient(
          transport: _FakeTransport([
            WebDavResponse(
              statusCode: 200,
              body: utf8.encode(jsonEncode(remote.toJson())),
            ),
          ]),
        ),
      );
      final result = await service.synchronize(
        direction: WebDavSyncDirection.download,
        conflictChoice: WebDavConflictChoice.remote,
      );
      expect(result.isSuccess, isFalse);
      expect(store.restored, isNull);
      expect(result.message, contains('本地正在编辑或已变化'));
    },
  );

  test(
    'shared running state prevents concurrent sync and notifies completion',
    () async {
      SharedPreferences.setMockInitialValues({'pianke_webdav_account': 'user'});
      final store = _BlockingBackupStore(_snapshot('local'));
      final service = WebDavSyncService(
        backup: store,
        preferences: await SharedPreferences.getInstance(),
        credentials: _FakeCredentials('secret'),
        client: WebDavClient(
          transport: _FakeTransport([
            WebDavResponse(
              statusCode: 200,
              body: utf8.encode(jsonEncode(store.local.toJson())),
            ),
          ]),
        ),
      );
      var changes = 0;
      service.addListener(() => changes++);
      final first = service.synchronize();
      expect(service.isRunning, isTrue);
      final second = await service.synchronize();
      expect(second.message, contains('已有同步任务'));
      store.ready.complete();
      expect((await first).isSuccess, isTrue);
      expect(service.isRunning, isFalse);
      expect(service.lastAttemptFailed, isFalse);
      expect(service.lastSuccessAt, isNotNull);
      expect(changes, 2);
    },
  );
  test('snapshot checksum is stable and contains no media cache fields', () {
    final original = _snapshot('movie_a');
    final parsed = BackupSnapshot.parse(original.toJson());
    final later = BackupSnapshot.create(
      original.toJson(),
      updatedAt: DateTime.utc(2027, 1, 1),
    );

    expect(parsed.checksum, original.checksum);
    expect(later.checksum, original.checksum);
    expect(parsed.payload.containsKey('videoFiles'), isFalse);
    expect(parsed.payload.containsKey('imageCache'), isFalse);
    expect(parsed.payload['movies'], hasLength(1));
  });

  test('planner identifies one-sided changes and conflicts', () {
    const base = 'base';
    final local = _snapshot('local').checksum;
    final remote = _snapshot('remote').checksum;

    expect(
      SyncPlanner.decide(
        localChecksum: local,
        remoteChecksum: base,
        baseLocalChecksum: base,
        baseRemoteChecksum: base,
      ).action,
      WebDavSyncAction.upload,
    );
    expect(
      SyncPlanner.decide(
        localChecksum: base,
        remoteChecksum: remote,
        baseLocalChecksum: base,
        baseRemoteChecksum: base,
      ).action,
      WebDavSyncAction.download,
    );
    expect(
      SyncPlanner.decide(
        localChecksum: local,
        remoteChecksum: remote,
        baseLocalChecksum: base,
        baseRemoteChecksum: base,
      ).action,
      WebDavSyncAction.conflict,
    );
  });

  test(
    'client encodes remote path and never sends plaintext password',
    () async {
      final transport = _FakeTransport([
        const WebDavResponse(statusCode: 201, body: []),
        const WebDavResponse(statusCode: 201, body: []),
        const WebDavResponse(statusCode: 201, body: []),
        const WebDavResponse(statusCode: 201, body: []),
      ]);
      final client = WebDavClient(
        transport: transport,
        endpointUri: Uri.parse('https://example.com/dav/'),
      );
      const config = WebDavConfig(
        account: 'user@example.com',
        applicationPassword: 'secret-value',
        remoteDirectory: 'Pianke Backup/Phone A',
      );

      await client.upload(config, _snapshot('movie_a'));

      expect(transport.methods, ['MKCOL', 'MKCOL', 'PUT', 'MOVE']);
      expect(transport.uris[1].toString(), contains('Pianke%20Backup'));
      expect(
        transport.headers[2]['Authorization'],
        isNot(contains('secret-value')),
      );
      expect(transport.headers[2]['Authorization'], startsWith('Basic '));
    },
  );

  test('replaces an existing remote backup after MOVE returns 409', () async {
    final transport = _FakeTransport([
      const WebDavResponse(statusCode: 201, body: []),
      const WebDavResponse(statusCode: 201, body: []),
      const WebDavResponse(statusCode: 409, body: []),
      const WebDavResponse(statusCode: 204, body: []),
      const WebDavResponse(statusCode: 201, body: []),
    ]);
    final client = WebDavClient(
      transport: transport,
      endpointUri: Uri.parse('https://example.com/dav/'),
    );

    await client.upload(
      const WebDavConfig(
        account: 'user@example.com',
        applicationPassword: 'secret-value',
        remoteDirectory: 'Pianke',
      ),
      _snapshot('movie_b'),
    );

    expect(transport.methods, ['MKCOL', 'PUT', 'MOVE', 'DELETE', 'MOVE']);
    expect(transport.uris[3].path, endsWith('/Pianke/pianke_backup.json'));
  });

  test(
    'download validates the remote snapshot and reports permission errors',
    () async {
      final snapshot = _snapshot('remote');
      final transport = _FakeTransport([
        WebDavResponse(
          statusCode: 200,
          body: utf8.encode(jsonEncode(snapshot.toJson())),
        ),
      ]);
      final client = WebDavClient(
        transport: transport,
        endpointUri: Uri.parse('https://example.com/dav/'),
      );
      const config = WebDavConfig(
        account: 'user',
        applicationPassword: 'secret',
        remoteDirectory: 'Pianke',
      );

      final backup = await client.download(config);
      expect(backup?.snapshot.checksum, snapshot.checksum);

      final denied = WebDavClient(
        transport: _FakeTransport([
          const WebDavResponse(statusCode: 403, body: []),
        ]),
        endpointUri: Uri.parse('https://example.com/dav/'),
      );
      await expectLater(
        denied.download(config),
        throwsA(
          isA<WebDavException>().having(
            (error) => error.message,
            'message',
            contains('权限'),
          ),
        ),
      );
    },
  );

  test('conflict does not overwrite until a side is chosen', () async {
    SharedPreferences.setMockInitialValues({
      'pianke_webdav_account': 'user',
      'pianke_webdav_directory': 'Pianke',
      'pianke_webdav_base_local_checksum': _snapshot('base').checksum,
      'pianke_webdav_base_remote_checksum': _snapshot('base').checksum,
    });
    final preferences = await SharedPreferences.getInstance();
    final localStore = _FakeBackupStore(_snapshot('local'));
    final remote = _snapshot('remote');
    final transport = _FakeTransport([
      WebDavResponse(
        statusCode: 200,
        body: utf8.encode(jsonEncode(remote.toJson())),
      ),
    ]);
    final service = WebDavSyncService(
      backup: localStore,
      preferences: preferences,
      credentials: _FakeCredentials('secret'),
      client: WebDavClient(
        transport: transport,
        endpointUri: Uri.parse('https://example.com/dav/'),
      ),
    );

    final conflict = await service.synchronize();
    expect(conflict.isConflict, isTrue);
    expect(localStore.restored, isNull);

    transport.responses.add(
      WebDavResponse(
        statusCode: 200,
        body: utf8.encode(jsonEncode(remote.toJson())),
      ),
    );

    final remoteChoice = await service.synchronize(
      conflictChoice: WebDavConflictChoice.remote,
    );
    expect(remoteChoice.isSuccess, isTrue);
    expect(localStore.restored?.checksum, remote.checksum);
  });

  test(
    'restoring from cloud writes a safety backup before overwriting',
    () async {
      SharedPreferences.setMockInitialValues({
        'pianke_webdav_account': 'user',
        'pianke_webdav_directory': 'Pianke',
      });
      final preferences = await SharedPreferences.getInstance();
      final localStore = _FakeBackupStore(_snapshot('local'));
      final remote = _snapshot('remote');
      final transport = _FakeTransport([
        WebDavResponse(
          statusCode: 200,
          body: utf8.encode(jsonEncode(remote.toJson())),
        ),
      ]);
      final service = WebDavSyncService(
        backup: localStore,
        preferences: preferences,
        credentials: _FakeCredentials('secret'),
        client: WebDavClient(
          transport: transport,
          endpointUri: Uri.parse('https://example.com/dav/'),
        ),
      );

      final outcome = await service.synchronize(
        direction: WebDavSyncDirection.download,
        // Download still requires an explicit side when both copies changed.
        conflictChoice: WebDavConflictChoice.remote,
      );

      expect(outcome.isSuccess, isTrue);
      expect(localStore.restored?.checksum, remote.checksum);
      // 覆盖前必须先落一份兜底备份，否则选错一侧就无法找回。
      expect(localStore.safetyBackupCount, 1);
    },
  );

  test('safety backup failure does not block the restore', () async {
    SharedPreferences.setMockInitialValues({
      'pianke_webdav_account': 'user',
      'pianke_webdav_directory': 'Pianke',
    });
    final preferences = await SharedPreferences.getInstance();
    final localStore = _FailingSafetyBackupStore(_snapshot('local'));
    final remote = _snapshot('remote');
    final transport = _FakeTransport([
      WebDavResponse(
        statusCode: 200,
        body: utf8.encode(jsonEncode(remote.toJson())),
      ),
    ]);
    final service = WebDavSyncService(
      backup: localStore,
      preferences: preferences,
      credentials: _FakeCredentials('secret'),
      client: WebDavClient(
        transport: transport,
        endpointUri: Uri.parse('https://example.com/dav/'),
      ),
    );

    final outcome = await service.synchronize(
      direction: WebDavSyncDirection.download,
      // Download still requires an explicit side when both copies changed.
      conflictChoice: WebDavConflictChoice.remote,
    );

    expect(outcome.isSuccess, isTrue);
    expect(localStore.restored?.checksum, remote.checksum);
  });
}

class _ChangingBackupStore extends _FakeBackupStore {
  _ChangingBackupStore(super.local);
  @override
  Future<String?> createLocalSafetyBackup() async {
    local = _snapshot('edited-during-network');
    return '/tmp/backup';
  }
}

class _BlockingBackupStore extends _FakeBackupStore {
  _BlockingBackupStore(super.local);
  final ready = Completer<void>();
  @override
  Future<BackupSnapshot> createSyncSnapshot() async {
    await ready.future;
    return local;
  }
}

class _DelayedCredentials extends _FakeCredentials {
  _DelayedCredentials(super.password);
  final ready = Completer<void>();
  @override
  Future<String?> readPassword() async {
    await ready.future;
    return password;
  }
}

/// 兜底备份抛异常时应被吞掉，不阻断恢复流程。
class _FailingSafetyBackupStore implements SyncBackupStore {
  BackupSnapshot local;
  BackupSnapshot? restored;

  _FailingSafetyBackupStore(this.local);

  @override
  Future<BackupSnapshot> createSyncSnapshot() async => local;

  @override
  Future<String?> createLocalSafetyBackup() async {
    throw const FileSystemException('disk full');
  }

  @override
  Future<RestoreStats> restoreSyncSnapshot(BackupSnapshot snapshot) async {
    restored = snapshot;
    local = snapshot;
    return const RestoreStats(
      moviesImported: 1,
      moviesSkipped: 0,
      drawRecordsImported: 0,
      drawRecordsSkipped: 0,
    );
  }
}
