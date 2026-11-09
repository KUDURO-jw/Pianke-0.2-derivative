import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/backup_snapshot.dart';
import 'package:random_movie/services/webdav_client.dart';
import 'package:random_movie/services/webdav_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自动同步的「省流量捷径」测试：本地没改、云端没变时，不应下载整份备份。

BackupSnapshot _snapshot(String marker) => BackupSnapshot.create({
  'meta': {'appId': 'Pianke', 'schemaVersion': 3},
  'settings': {'themeMode': 'system'},
  'movies': [
    {'id': marker, 'title': marker, 'poster': 'https://example.com/p.jpg'},
  ],
  'drawRecords': <Map<String, dynamic>>[],
  'viewingSessions': <Map<String, dynamic>>[],
  'collections': <Map<String, dynamic>>[],
  'collectionMembers': <Map<String, dynamic>>[],
  'tags': <Map<String, dynamic>>[],
  'movieTags': <Map<String, dynamic>>[],
}, updatedAt: DateTime.utc(2026, 1, 1));

String _propfind(String etag) =>
    '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:"><D:response>'
    '<D:propstat><D:prop>'
    '<D:getetag>$etag</D:getetag>'
    '<D:getlastmodified>Mon, 09 Nov 2026 08:00:00 GMT</D:getlastmodified>'
    '<D:getcontentlength>10</D:getcontentlength>'
    '</D:prop></D:propstat></D:response></D:multistatus>';

String _fingerprint(String etag) => '$etag|Mon, 09 Nov 2026 08:00:00 GMT|10';

WebDavResponse _propfindResponse(String etag) =>
    WebDavResponse(statusCode: 207, body: utf8.encode(_propfind(etag)));

class _FakeTransport implements WebDavTransport {
  final List<String> methods = [];
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
    if (responses.isEmpty) throw StateError('No fake response');
    return responses.removeAt(0);
  }
}

class _FakeCredentials implements SyncCredentialStore {
  @override
  Future<String?> readPassword() async => 'secret';

  @override
  Future<void> writePassword(String password) async {}

  @override
  Future<void> deletePassword() async {}
}

class _FakeBackupStore implements SyncBackupStore {
  BackupSnapshot local;
  BackupSnapshot? restored;

  _FakeBackupStore(this.local);

  @override
  Future<BackupSnapshot> createSyncSnapshot() async => local;

  @override
  Future<String?> createLocalSafetyBackup() async => '/tmp/safety.json';

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

final _now = DateTime.utc(2026, 11, 9, 8);

Future<({WebDavSyncService service, _FakeTransport transport, _FakeBackupStore store})>
_build({
  required BackupSnapshot local,
  required List<WebDavResponse> responses,
  required Map<String, Object> prefs,
  BackupSnapshot? storeLocal,
}) async {
  SharedPreferences.setMockInitialValues({
    'pianke_webdav_account': 'user',
    ...prefs,
  });
  final transport = _FakeTransport(responses);
  final store = _FakeBackupStore(storeLocal ?? local);
  final service = WebDavSyncService(
    backup: store,
    preferences: await SharedPreferences.getInstance(),
    credentials: _FakeCredentials(),
    client: WebDavClient(transport: transport),
    now: () => _now,
  );
  return (service: service, transport: transport, store: store);
}

void main() {
  final local = _snapshot('local');

  test('unchanged local and remote: only one tiny PROPFIND, no download', () async {
    final built = await _build(
      local: local,
      responses: [_propfindResponse('etag1')],
      prefs: {
        'pianke_webdav_base_local_checksum': local.checksum,
        'pianke_webdav_remote_fingerprint': _fingerprint('etag1'),
        'pianke_webdav_last_remote_check_at': DateTime.utc(
          2026, 11, 9, 7, 40,
        ).toIso8601String(),
      },
    );

    final outcome = await built.service.synchronizeAutomatically();

    expect(outcome.isSuccess, isTrue);
    expect(outcome.action, WebDavSyncAction.none);
    expect(built.transport.methods, ['PROPFIND']);
    expect(built.store.restored, isNull);
  });

  test('checked less than 5 minutes ago: no network request at all', () async {
    final built = await _build(
      local: local,
      responses: [],
      prefs: {
        'pianke_webdav_base_local_checksum': local.checksum,
        'pianke_webdav_remote_fingerprint': _fingerprint('etag1'),
        'pianke_webdav_last_remote_check_at': DateTime.utc(
          2026, 11, 9, 7, 59,
        ).toIso8601String(),
      },
    );

    final outcome = await built.service.synchronizeAutomatically();

    expect(outcome.isSuccess, isTrue);
    expect(built.transport.methods, isEmpty);
  });

  test('remote fingerprint changed: falls back to full sync and downloads', () async {
    final remote = _snapshot('remote');
    final built = await _build(
      local: local,
      responses: [
        _propfindResponse('etag2'),
        _propfindResponse('etag2'),
        WebDavResponse(
          statusCode: 200,
          body: utf8.encode(jsonEncode(remote.toJson())),
        ),
      ],
      prefs: {
        'pianke_webdav_base_local_checksum': local.checksum,
        'pianke_webdav_base_remote_checksum': 'older-remote-checksum',
        'pianke_webdav_remote_fingerprint': _fingerprint('etag1'),
        'pianke_webdav_last_remote_check_at': DateTime.utc(
          2026, 11, 9, 7, 40,
        ).toIso8601String(),
      },
    );

    final outcome = await built.service.synchronizeAutomatically();
    final prefs = await SharedPreferences.getInstance();

    expect(outcome.isSuccess, isTrue);
    expect(outcome.action, WebDavSyncAction.download);
    expect(built.transport.methods, ['PROPFIND', 'PROPFIND', 'GET']);
    expect(built.store.restored?.checksum, remote.checksum);
    expect(
      prefs.getString('pianke_webdav_remote_fingerprint'),
      _fingerprint('etag2'),
    );
  });
}
