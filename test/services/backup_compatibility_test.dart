import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/storage_service.dart';

// Exercise the original importer; only platform I/O is replaced in this test.
class _MemoryStore implements StorageService {
  final movies = <String, Movie>{};
  final sessions = <String, ViewingSession>{};
  Map<String, dynamic>? tables;

  @override
  Future<Movie?> getMovieById(String id) async => movies[id];
  @override
  Future<void> addMovieDirectly(Movie movie) async => movies[movie.id] = movie;
  @override
  Future<bool> movieHasSession(String movieId) async =>
      sessions.values.any((session) => session.movieId == movieId);
  @override
  Future<bool> addSessionIfNotExists(ViewingSession session) async {
    if (sessions.containsKey(session.id)) return false;
    sessions[session.id] = session;
    return true;
  }

  @override
  Future<int> restoreCollectionsAndTags(Map<String, dynamic> data) async {
    tables = data;
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _JsonPicker extends FilePicker {
  final Map<String, dynamic> payload;
  _JsonPicker(this.payload);

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    return FilePickerResult([
      PlatformFile(name: 'backup.json', size: bytes.length, bytes: bytes),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'legacy JSON merge preserves existing movies and synthesizes one session',
    () async {
      final store = _MemoryStore();
      FilePicker.platform = _JsonPicker({
        'meta': {'appId': 'RandoMov', 'schemaVersion': 1},
        'movies': [
          {
            'id': 'legacy',
            'title': '旧影片',
            'watched': true,
            'watchedAt': '2024-06-01T19:00:00',
            'userRating': 4.5,
            'userReview': '旧短评',
          },
        ],
        'drawRecords': [],
      });
      final service = BackupService(store);
      final first = await service.importBackup();
      expect(first.success, isTrue);
      expect(first.stats?.moviesImported, 1);
      expect(first.stats?.sessionsImported, 1);
      expect(store.sessions.values.single.note, '旧短评');
      expect(store.sessions.values.single.rating, 4.5);
      final second = await service.importBackup();
      expect(second.stats?.moviesSkipped, 1);
      expect(second.stats?.sessionsImported, 0);
      expect(store.sessions.length, 1);
    },
  );
  test(
    'schema 3 restores independent sessions and passes collection/tag payload',
    () async {
      final store = _MemoryStore();
      final sessions = [
        for (var i = 1; i <= 2; i++)
          ViewingSession(
            id: 's$i',
            movieId: 'movie',
            watchedAt: DateTime(2026, 1, i),
            watchedWith: '自定义同伴',
            note: '第$i次',
            isRewatch: i == 2,
          ).toJson(),
      ];
      FilePicker.platform = _JsonPicker({
        'meta': {'appId': 'Pianke', 'schemaVersion': 3},
        'movies': [Movie(id: 'movie', title: '影片').toJson()],
        'viewingSessions': sessions,
        'drawRecords': [],
        'collections': [
          {'id': 'collection', 'name': '合集'},
        ],
        'collectionMembers': [
          {'collection_id': 'collection', 'movie_id': 'movie'},
        ],
        'tags': [
          {'id': 'tag', 'name': '标签'},
        ],
        'movieTags': [
          {'movie_id': 'movie', 'tag_id': 'tag'},
        ],
      });
      final result = await BackupService(store).importBackup();
      expect(result.success, isTrue);
      expect(result.stats?.sessionsImported, 2);
      expect(store.sessions['s2']?.isRewatch, isTrue);
      expect(store.sessions['s1']?.watchedWith, '自定义同伴');
      expect((store.tables?['collections'] as List).single['id'], 'collection');
      expect((store.tables?['movieTags'] as List).single['tag_id'], 'tag');
    },
  );
}
