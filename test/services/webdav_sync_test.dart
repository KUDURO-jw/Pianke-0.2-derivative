import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/backup_snapshot.dart';
import 'package:random_movie/services/webdav_client.dart';
import 'package:random_movie/services/webdav_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  _FakeBackupStore(this.local);

  @override
  Future<BackupSnapshot> createSyncSnapshot() async => local;

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
}
