import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/backup_snapshot.dart';

class _Store implements StorageService {
  bool replaced = false;
  @override
  Future<void> replaceBackupData({
    required List<Movie> movies,
    required List<DrawRecord> drawRecords,
    required List<ViewingSession> sessions,
    required Map<String, List<Map<String, Object?>>> tableData,
  }) async {
    replaced = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _payload() => {
  'meta': {'appId': 'Pianke', 'schemaVersion': 3},
  'movies': [Movie(id: 'a', title: '影片').toJson()],
  'viewingSessions': [],
  'drawRecords': [],
  'collections': [],
  'collectionMembers': [],
  'tags': [],
  'movieTags': [],
};

void main() {
  for (final kind in [
    'future',
    'duplicate',
    'orphan',
    'brokenTable',
    'missingSessions',
  ]) {
    test(
      'invalid cloud $kind is rejected before replacing local data',
      () async {
        final payload = _payload();
        switch (kind) {
          case 'future':
            payload['meta'] = {'appId': 'Pianke', 'schemaVersion': 99};
          case 'duplicate':
            (payload['movies'] as List).add(
              Movie(id: 'a', title: '重复').toJson(),
            );
          case 'orphan':
            payload['viewingSessions'] = [
              ViewingSession(
                id: 's',
                movieId: 'missing',
                watchedAt: DateTime(2026),
              ).toJson(),
            ];
          case 'brokenTable':
            payload['tags'] = [42];
          case 'missingSessions':
            payload.remove('viewingSessions');
        }
        final store = _Store();
        await expectLater(
          BackupService(
            store,
          ).restoreSyncSnapshot(BackupSnapshot.create(payload)),
          throwsA(anything),
        );
        expect(store.replaced, isFalse);
      },
    );
  }
}
