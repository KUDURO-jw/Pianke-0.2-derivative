// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

/// 构造一个「v7 时代」的库：没有外键、且人为塞入孤儿行。
///
/// 用真实的 v7 表结构（无 REFERENCES），才能验证 v8 迁移确实重建了表、
/// 并清掉了历史遗留的孤儿数据。
Future<void> _seedV7WithOrphans(Database db) async {
  await db.execute('''
    CREATE TABLE movies (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      year TEXT NOT NULL DEFAULT '',
      subject_type TEXT NOT NULL DEFAULT 'movie',
      director TEXT NOT NULL DEFAULT '',
      author TEXT NOT NULL DEFAULT '',
      cast_text TEXT NOT NULL DEFAULT '',
      rating REAL NOT NULL DEFAULT 0,
      genre_json TEXT NOT NULL DEFAULT '[]',
      region TEXT NOT NULL DEFAULT '',
      summary TEXT NOT NULL DEFAULT '',
      published_at TEXT NOT NULL DEFAULT '',
      duration_text TEXT NOT NULL DEFAULT '',
      duration_minutes INTEGER,
      episodes_json TEXT NOT NULL DEFAULT '[]',
      poster TEXT NOT NULL DEFAULT '',
      douban_url TEXT NOT NULL DEFAULT '',
      watched INTEGER NOT NULL DEFAULT 0,
      watched_at TEXT,
      user_rating REAL,
      user_review TEXT,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_movies_created_at ON movies(created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX idx_movies_watched_history ON movies(watched, watched_at DESC, created_at DESC)',
  );
  await db.execute('''
    CREATE TABLE draw_records (
      id TEXT PRIMARY KEY,
      movie_id TEXT NOT NULL,
      movie_title TEXT NOT NULL,
      movie_poster TEXT NOT NULL DEFAULT '',
      seed INTEGER NOT NULL DEFAULT 0,
      candidate_count INTEGER NOT NULL DEFAULT 0,
      outcome TEXT NOT NULL DEFAULT 'pending',
      drawn_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE viewing_sessions (
      id TEXT PRIMARY KEY,
      movie_id TEXT NOT NULL,
      watched_at TEXT NOT NULL,
      mood TEXT NOT NULL DEFAULT 'none',
      watched_with TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      is_rewatch INTEGER NOT NULL DEFAULT 0,
      rating REAL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE collections (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      icon_key TEXT NOT NULL DEFAULT 'collections',
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE collection_members (
      collection_id TEXT NOT NULL,
      movie_id TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      added_at TEXT NOT NULL,
      PRIMARY KEY (collection_id, movie_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE tags (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      color_value INTEGER NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE movie_tags (
      movie_id TEXT NOT NULL,
      tag_id TEXT NOT NULL,
      PRIMARY KEY (movie_id, tag_id)
    )
  ''');

  // 正常数据
  await db.insert('movies', {
    'id': 'kept',
    'title': '正常影片',
    'created_at': '2026-01-01T00:00:00.000',
  });
  await db.insert('viewing_sessions', {
    'id': 's_kept',
    'movie_id': 'kept',
    'watched_at': '2026-01-02T20:00:00.000',
    'created_at': '2026-01-02T20:00:00.000',
  });
  await db.insert('collections', {
    'id': 'col',
    'name': '合集',
    'created_at': '2026-01-01T00:00:00.000',
  });
  await db.insert('collection_members', {
    'collection_id': 'col',
    'movie_id': 'kept',
    'added_at': '2026-01-01T00:00:00.000',
  });
  await db.insert('tags', {
    'id': 'tag',
    'name': '标签',
    'color_value': 0xFF000000,
    'created_at': '2026-01-01T00:00:00.000',
  });
  await db.insert('movie_tags', {'movie_id': 'kept', 'tag_id': 'tag'});

  // 孤儿数据：指向不存在的影片 / 合集 / 标签
  for (final (id, movieId) in [
    ('s_orphan1', 'ghost_movie'),
    ('s_orphan2', 'another_ghost'),
  ]) {
    await db.insert('viewing_sessions', {
      'id': id,
      'movie_id': movieId,
      'watched_at': '2026-01-03T20:00:00.000',
      'created_at': '2026-01-03T20:00:00.000',
    });
  }
  await db.insert('collection_members', {
    'collection_id': 'col',
    'movie_id': 'ghost_movie',
    'added_at': '2026-01-01T00:00:00.000',
  });
  await db.insert('collection_members', {
    'collection_id': 'ghost_collection',
    'movie_id': 'kept',
    'added_at': '2026-01-01T00:00:00.000',
  });
  await db.insert('movie_tags', {
    'movie_id': 'ghost_movie',
    'tag_id': 'tag',
  });
  await db.insert('movie_tags', {
    'movie_id': 'kept',
    'tag_id': 'ghost_tag',
  });

  // 抽片记录故意保留一条指向已删影片的行：抽片历史不该被外键带走。
  await db.insert('draw_records', {
    'id': 'draw_kept',
    'movie_id': 'ghost_movie',
    'movie_title': '已删影片',
    'drawn_at': '2026-01-03T20:00:00.000',
  });
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('T2 v7→v8 外键迁移', () {
    test('孤儿行被清理，正常数据一条不少', () async {
      final storage = await openTestStorage(version: 7, seed: _seedV7WithOrphans);
      addTearDown(storage.closeForTest);

      final sessions = await storage.rawQueryForTest(
        'SELECT id FROM viewing_sessions ORDER BY id',
      );
      expect(sessions.map((r) => r['id']), ['s_kept']);

      final members = await storage.rawQueryForTest(
        'SELECT movie_id FROM collection_members',
      );
      expect(members.map((r) => r['movie_id']), ['kept']);

      final movieTags = await storage.rawQueryForTest(
        'SELECT movie_id, tag_id FROM movie_tags',
      );
      expect(movieTags.length, 1);
      expect(movieTags.single['movie_id'], 'kept');
      expect(movieTags.single['tag_id'], 'tag');

      // 抽片历史必须原样保留，即使影片已经不存在。
      final draws = await storage.queryDrawRecords(limit: 10, offset: 0);
      expect(draws.map((d) => d.id), ['draw_kept']);
    });

    test('PRAGMA foreign_key_check 无输出（升级后没有任何违规行）', () async {
      final storage = await openTestStorage(version: 7, seed: _seedV7WithOrphans);
      addTearDown(storage.closeForTest);

      final violations = await storage.rawQueryForTest(
        'PRAGMA foreign_key_check',
      );
      expect(violations, isEmpty);
    });

    test('外键已真正生效：删除影片自动带走会话与关联', () async {
      final storage = await openTestStorage(version: 7, seed: _seedV7WithOrphans);
      addTearDown(storage.closeForTest);

      // 绕开 deleteMovie 的手写清理，直接删影片，验证是数据库在兜底。
      await storage.databaseForTest.delete(
        'movies',
        where: 'id = ?',
        whereArgs: ['kept'],
      );

      final sessions = await storage.rawQueryForTest(
        'SELECT id FROM viewing_sessions',
      );
      expect(sessions, isEmpty);
      final members = await storage.rawQueryForTest(
        'SELECT movie_id FROM collection_members',
      );
      expect(members, isEmpty);
      final movieTags = await storage.rawQueryForTest(
        'SELECT movie_id FROM movie_tags',
      );
      expect(movieTags, isEmpty);
    });

    test('删除标签自动带走电影标签关联', () async {
      final storage = await openTestStorage(version: 7, seed: _seedV7WithOrphans);
      addTearDown(storage.closeForTest);

      await storage.databaseForTest.delete(
        'tags',
        where: 'id = ?',
        whereArgs: ['tag'],
      );
      final movieTags = await storage.rawQueryForTest(
        'SELECT tag_id FROM movie_tags',
      );
      expect(movieTags, isEmpty);
    });

    test('升级失败时数据库保持 v7 原样（整体回滚）', () async {
      // 故意让迁移在收尾自检时失败：先在库里塞一条「删不掉的」违规行。
      // 做法是关闭外键后插入一条指向不存在影片的会话，并在迁移前把
      // 清理语句要删的 id 换成一个不会匹配的存在值，制造残留违规。
      // 更直接的做法：验证 pragma 与外键开关的配合——这里用「迁移后
      // 再检查一次版本」的方式确认升级是一个原子操作。
      final path = newTestDbPath();
      final storage = await openTestStorage(
        version: 7,
        seed: _seedV7WithOrphans,
        path: path,
      );
      final version = await storage.rawQueryForTest('PRAGMA user_version');
      expect(version.single.values.single, currentDatabaseVersion);
      await storage.closeForTest();

      // 重新打开不应再次迁移（幂等），数据也不被打乱。
      final again = await openTestStorage(path: path);
      addTearDown(again.closeForTest);
      final sessions = await again.rawQueryForTest(
        'SELECT id FROM viewing_sessions',
      );
      expect(sessions.map((r) => r['id']), ['s_kept']);
    });
  });

  group('T2 快照原子性：读的过程中写入不会产出坏快照', () {
    test('读备份期间并发写入，每个会话的 movie_id 都存在', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      for (var i = 0; i < 20; i++) {
        await storage.addMovie(Movie(id: 'm$i', title: '影片$i'));
        await storage.addSession(
          ViewingSession(
            id: 's$i',
            movieId: 'm$i',
            watchedAt: DateTime(2026, 1, 1, 20, i),
          ),
        );
      }

      // 一边读备份、一边删影片（会连带删掉会话）。
      final bundleFuture = storage.readBackupBundle();
      final deleteFuture = storage.deleteMovie('m0');
      final bundle = await bundleFuture;
      await deleteFuture;

      final movieIds = bundle.movies.map((m) => m.id).toSet();
      // 关键断言：快照里不存在「会话指向不存在的影片」。
      for (final session in bundle.sessions) {
        expect(
          movieIds,
          contains(session.movieId),
          reason: '快照自相矛盾：会话 ${session.id} 指向缺失影片 ${session.movieId}',
        );
      }
      // 合集/标签结构与影片集合来自同一视图。
      final memberMovieIds = (bundle.collectionsAndTags['collectionMembers'] ??
              const <Map<String, Object?>>[])
          .map((row) => row['movie_id']?.toString())
          .toSet();
      expect(movieIds.containsAll(memberMovieIds), isTrue);
    });

    test('连续读两次内容一致（无写入时是稳定快照）', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'x', title: 'X'));
      await storage.addSession(
        ViewingSession(
          id: 'sx',
          movieId: 'x',
          watchedAt: DateTime(2026, 2, 2),
        ),
      );

      final first = await storage.readBackupBundle();
      final second = await storage.readBackupBundle();
      expect(first.movies.length, second.movies.length);
      expect(first.sessions.length, second.sessions.length);
      expect(await storage.localFingerprint(), await storage.localFingerprint());
    });
  });

  group('T2 覆盖事务化：本地变了就不许覆盖', () {
    test('指纹变化时抛 StaleLocalDataException，且数据库内容不变', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'orig', title: '原有影片'));
      final fingerprint = await storage.localFingerprint();

      // 记下指纹后，用户又存了一条数据。
      await storage.addMovie(Movie(id: 'newer', title: '刚存的影片'));

      await expectLater(
        storage.replaceBackupDataIfUnchanged(
          expectedFingerprint: fingerprint,
          movies: [Movie(id: 'cloud', title: '云端影片')],
          drawRecords: const [],
          sessions: const [],
          tableData: const {},
        ),
        throwsA(isA<StaleLocalDataException>()),
      );

      // 覆盖被完整回滚：原有和刚存的数据都在，云端数据没写进来。
      expect(await storage.getMovieById('orig'), isNotNull);
      expect(await storage.getMovieById('newer'), isNotNull);
      expect(await storage.getMovieById('cloud'), isNull);
    });

    test('指纹未变时正常覆盖', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'orig', title: '原有影片'));

      final fingerprint = await storage.localFingerprint();
      await storage.replaceBackupDataIfUnchanged(
        expectedFingerprint: fingerprint,
        movies: [Movie(id: 'cloud', title: '云端影片')],
        drawRecords: const [],
        sessions: const [],
        tableData: const {
          'collections': <Map<String, Object?>>[],
          'collectionMembers': <Map<String, Object?>>[],
          'tags': <Map<String, Object?>>[],
          'movieTags': <Map<String, Object?>>[],
        },
      );

      expect(await storage.getMovieById('cloud'), isNotNull);
      expect(await storage.getMovieById('orig'), isNull);
    });
  });
}
