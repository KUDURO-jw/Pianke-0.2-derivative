// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/hlc.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

/// 造一个 v8 库（有外键、有时间列，但没有合并元数据）。
Future<void> _seedV8(Database db) async {
  await db.execute('''
    CREATE TABLE movies (
      id TEXT PRIMARY KEY, title TEXT NOT NULL,
      year TEXT NOT NULL DEFAULT '', subject_type TEXT NOT NULL DEFAULT 'movie',
      director TEXT NOT NULL DEFAULT '', author TEXT NOT NULL DEFAULT '',
      cast_text TEXT NOT NULL DEFAULT '', rating REAL NOT NULL DEFAULT 0,
      genre_json TEXT NOT NULL DEFAULT '[]', region TEXT NOT NULL DEFAULT '',
      summary TEXT NOT NULL DEFAULT '', published_at TEXT NOT NULL DEFAULT '',
      duration_text TEXT NOT NULL DEFAULT '', duration_minutes INTEGER,
      episodes_json TEXT NOT NULL DEFAULT '[]', poster TEXT NOT NULL DEFAULT '',
      douban_url TEXT NOT NULL DEFAULT '', watched INTEGER NOT NULL DEFAULT 0,
      watched_at TEXT, user_rating REAL, user_review TEXT,
      poster_color INTEGER, created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE viewing_sessions (
      id TEXT PRIMARY KEY,
      movie_id TEXT NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
      watched_at TEXT NOT NULL, watched_at_utc INTEGER, watched_on TEXT,
      mood TEXT NOT NULL DEFAULT 'none', watched_with TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '', is_rewatch INTEGER NOT NULL DEFAULT 0,
      rating REAL, created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE draw_records (
      id TEXT PRIMARY KEY, movie_id TEXT NOT NULL, movie_title TEXT NOT NULL,
      movie_poster TEXT NOT NULL DEFAULT '', seed INTEGER NOT NULL DEFAULT 0,
      candidate_count INTEGER NOT NULL DEFAULT 0,
      outcome TEXT NOT NULL DEFAULT 'pending', drawn_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE collections (
      id TEXT PRIMARY KEY, name TEXT NOT NULL,
      icon_key TEXT NOT NULL DEFAULT 'collections',
      sort_order INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE collection_members (
      collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
      movie_id TEXT NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
      sort_order INTEGER NOT NULL DEFAULT 0, added_at TEXT NOT NULL,
      PRIMARY KEY (collection_id, movie_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE tags (
      id TEXT PRIMARY KEY, name TEXT NOT NULL,
      color_value INTEGER NOT NULL, created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE movie_tags (
      movie_id TEXT NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
      tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
      PRIMARY KEY (movie_id, tag_id)
    )
  ''');

  // 真实历史数据：不同时间入库的影片。
  for (final (id, created) in [
    ('m1', '2024-01-01T10:00:00.000'),
    ('m2', '2025-06-01T10:00:00.000'),
    ('m3', '2026-01-01T10:00:00.000'),
  ]) {
    await db.insert('movies', {
      'id': id,
      'title': '片$id',
      'created_at': created,
    });
  }
  await db.insert('viewing_sessions', {
    'id': 's1',
    'movie_id': 'm1',
    'watched_at': '2025-03-01T20:00:00.000',
    'watched_at_utc': DateTime.parse(
      '2025-03-01T20:00:00.000',
    ).toUtc().millisecondsSinceEpoch,
    'watched_on': '2025-03-01',
    'created_at': '2025-03-01T20:00:00.000',
  });
  await db.insert('collections', {
    'id': 'c1',
    'name': '合集',
    'created_at': '2024-05-01T00:00:00.000',
  });
  await db.insert('collection_members', {
    'collection_id': 'c1',
    'movie_id': 'm1',
    'added_at': '2024-05-02T00:00:00.000',
  });
  await db.insert('tags', {
    'id': 't1',
    'name': '标签',
    'color_value': 0xFF000000,
    'created_at': '2024-06-01T00:00:00.000',
  });
  await db.insert('movie_tags', {'movie_id': 'm1', 'tag_id': 't1'});
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('T3 v8→v9 合并元数据迁移', () {
    test('所有同步表都有 updated_at / deleted_at 列', () async {
      final storage = await openTestStorage(version: 8, seed: _seedV8);
      addTearDown(storage.closeForTest);

      for (final table in [
        'movies',
        'viewing_sessions',
        'collections',
        'collection_members',
        'tags',
        'movie_tags',
      ]) {
        final columns = await storage.rawQueryForTest('PRAGMA table_info($table)');
        final names = columns.map((row) => row['name']).toSet();
        expect(names, contains('updated_at'), reason: '$table 缺 updated_at');
        expect(names, contains('deleted_at'), reason: '$table 缺 deleted_at');
      }
    });

    test('历史记录都拿到了可解析的 HLC，且没有任何行被标成已删', () async {
      final storage = await openTestStorage(version: 8, seed: _seedV8);
      addTearDown(storage.closeForTest);

      for (final table in [
        'movies',
        'viewing_sessions',
        'collections',
        'collection_members',
        'tags',
        'movie_tags',
      ]) {
        final rows = await storage.rawQueryForTest(
          'SELECT updated_at, deleted_at FROM $table',
        );
        expect(rows, isNotEmpty, reason: '$table 应当有数据');
        for (final row in rows) {
          final raw = row['updated_at']?.toString() ?? '';
          expect(
            Hlc.tryParse(raw),
            isNotNull,
            reason: '$table 的 updated_at 不是合法 HLC：$raw',
          );
          expect(
            row['deleted_at'],
            isNull,
            reason: '$table 的历史行不该被凭空标成已删',
          );
        }
      }
    });

    test('回填顺序反映原始时间先后（新影片的时间戳不旧于老影片）', () async {
      final storage = await openTestStorage(version: 8, seed: _seedV8);
      addTearDown(storage.closeForTest);

      final rows = await storage.rawQueryForTest(
        'SELECT id, updated_at FROM movies ORDER BY id',
      );
      final clocks = {
        for (final row in rows)
          row['id'] as String: Hlc.tryParse(row['updated_at'] as String)!,
      };
      // m1 入库最早，m3 最晚。
      expect(clocks['m1']! < clocks['m2']!, isTrue);
      expect(clocks['m2']! < clocks['m3']!, isTrue);
    });

    test('影片与会话保留原始 created_at，不被迁移改写', () async {
      final storage = await openTestStorage(version: 8, seed: _seedV8);
      addTearDown(storage.closeForTest);

      final movie = await storage.getMovieById('m1');
      expect(movie, isNotNull);
      expect(movie!.createdAt.year, 2024);

      final sessions = await storage.querySessionsByMovie('m1');
      expect(sessions.single.watchedAt.year, 2025);
    });

    test('迁移后数据条数不变', () async {
      final storage = await openTestStorage(version: 8, seed: _seedV8);
      addTearDown(storage.closeForTest);
      expect(await storage.countMovies(), 3);
      expect(await storage.countSessions(), 1);
    });

    test('movie_tags 这种无时间列的表也能拿到时间戳', () async {
      final storage = await openTestStorage(version: 8, seed: _seedV8);
      addTearDown(storage.closeForTest);

      final rows = await storage.rawQueryForTest(
        'SELECT updated_at FROM movie_tags',
      );
      expect(rows.length, 1);
      expect(Hlc.tryParse(rows.single['updated_at'] as String), isNotNull);
    });

    test('新建的库（非升级路径）同样带合并元数据', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'fresh', title: '新影片'));
      final rows = await storage.rawQueryForTest(
        'SELECT updated_at, deleted_at FROM movies',
      );
      expect(Hlc.tryParse(rows.single['updated_at'] as String), isNotNull);
      expect(rows.single['deleted_at'], isNull);
    });
  });

  group('T3 合并元数据与既有功能共存', () {
    test('增删改电影照常工作，合并列不影响读取', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'm', title: '影片'));
      await storage.updateMovie(
        Movie(id: 'm', title: '改名后'),
      );
      expect((await storage.getMovieById('m'))!.title, '改名后');

      await storage.addSession(
        ViewingSession(
          id: 's',
          movieId: 'm',
          watchedAt: DateTime(2026, 3, 1),
        ),
      );
      expect((await storage.querySessionsByMovie('m')).length, 1);
    });

    test('备份往返不受新增列影响', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'm', title: '影片', posterColor: 0xFF112233));

      final movies = await storage.getAllMoviesForBackup();
      expect(movies.single.posterColor, 0xFF112233);
      // Movie.toJson 不应混入数据库内部列。
      final json = movies.single.toJson();
      expect(json.containsKey('updated_at'), isFalse);
      expect(json.containsKey('deleted_at'), isFalse);
    });
  });
}
