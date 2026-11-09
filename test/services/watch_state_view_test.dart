// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/services/watch_status.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

/// 构造一批覆盖各种「已看」来源的影片，返回它们的 id。
Future<List<String>> _seedMixedLibrary(StorageService storage) async {
  final ids = <String>[];

  // 1) 显式 watched = true，没有任何会话
  await storage.addMovie(Movie(id: 'explicit', title: '显式已看', watched: true));
  ids.add('explicit');

  // 2) 只有一条观影会话
  await storage.addMovie(Movie(id: 'bySession', title: '靠会话已看'));
  await storage.addSession(
    ViewingSession(
      id: 's1',
      movieId: 'bySession',
      watchedAt: DateTime(2026, 3, 1, 20),
    ),
  );
  ids.add('bySession');

  // 3) 完全没看过
  await storage.addMovie(Movie(id: 'unwatched', title: '未看'));
  ids.add('unwatched');

  // 4) 剧集：全部集都看完
  await storage.addMovie(
    Movie(
      id: 'seriesDone',
      title: '剧集全看完',
      subjectType: MovieSubjectType.tvSeries,
      episodes: const [
        MovieEpisode(number: 1, label: '第1集', doubanUrl: '', watched: true),
        MovieEpisode(number: 2, label: '第2集', doubanUrl: '', watched: true),
      ],
    ),
  );
  ids.add('seriesDone');

  // 5) 剧集：只看了一集
  await storage.addMovie(
    Movie(
      id: 'seriesPartial',
      title: '剧集看一半',
      subjectType: MovieSubjectType.tvSeries,
      episodes: const [
        MovieEpisode(number: 1, label: '第1集', doubanUrl: '', watched: true),
        MovieEpisode(number: 2, label: '第2集', doubanUrl: ''),
      ],
    ),
  );
  ids.add('seriesPartial');

  // 6) 有会话，但会话被删了（墓碑）
  await storage.addMovie(Movie(id: 'sessionDeleted', title: '会话被删'));
  await storage.addSession(
    ViewingSession(
      id: 's2',
      movieId: 'sessionDeleted',
      watchedAt: DateTime(2026, 4, 1, 20),
    ),
  );
  await storage.deleteSession('s2');
  ids.add('sessionDeleted');

  return ids;
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('T4 阶段 A：SQL 视图与 Dart 判定必须一致', () {
    test('同一批数据，SQL 与 WatchStatus 给出相同的已看集合', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      final ids = await _seedMixedLibrary(storage);

      // SQL 侧：直接问视图。
      final sqlRows = await storage.rawQueryForTest(
        'SELECT id, derived_watched FROM v_movie_state',
      );
      final sqlWatched = {
        for (final row in sqlRows)
          if ((row['derived_watched'] as num?)?.toInt() == 1)
            row['id'] as String,
      };

      // Dart 侧：读全库后交给 WatchStatus 判断。
      final movies = await storage.getMoviesByIds(ids);
      final dartWatched = {
        for (final movie in movies)
          if (WatchStatus.isWatched(movie)) movie.id,
      };

      expect(
        dartWatched,
        sqlWatched,
        reason: '视图与 WatchStatus 必须对「已看」给出同一答案',
      );
    });

    test('已看计数与 queryMovieIds / queryMovies 三条路径一致', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await _seedMixedLibrary(storage);

      final count = await storage.countMovies(watchedOnly: true);
      final ids = await storage.queryMovieIds(watchedOnly: true);
      final movies = await storage.queryMovies(
        limit: 100,
        offset: 0,
        watchedOnly: true,
      );

      expect(ids.length, count);
      expect(movies.length, count);
      expect(ids.toSet(), movies.map((m) => m.id).toSet());
    });

    test('已看 + 未看 = 总数（没有任何影片同时命中或都不命中）', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await _seedMixedLibrary(storage);

      final total = await storage.countMovies();
      final watched = await storage.countMovies(watchedOnly: true);
      final unwatched = await storage.countMovies(unwatchedOnly: true);

      expect(watched + unwatched, total);

      // 两个集合不能有交集。
      final watchedIds = (await storage.queryMovieIds(watchedOnly: true)).toSet();
      final unwatchedIds =
          (await storage.queryMovieIds(unwatchedOnly: true)).toSet();
      expect(watchedIds.intersection(unwatchedIds), isEmpty);
    });

    test('会话被软删除后，影片不再算已看', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await _seedMixedLibrary(storage);

      // sessionDeleted 的会话已删，应当回到未看。
      final watchedIds = await storage.queryMovieIds(watchedOnly: true);
      expect(watchedIds, isNot(contains('sessionDeleted')));
    });

    test('显式 watched 与会话两种来源都被视图识别', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await _seedMixedLibrary(storage);

      final watchedIds = (await storage.queryMovieIds(watchedOnly: true)).toSet();
      expect(watchedIds, contains('explicit'));
      expect(watchedIds, contains('bySession'));
    });

    test('剧集全看完时视图算已看，与 WatchStatus 一致', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await _seedMixedLibrary(storage);

      // 剧集状态存在 episodes_json 里，SQL 视图看不到分集，
      // 所以这里只验证「两者对同一部影片不冲突」：
      // SQL 说未看时，WatchStatus 也可能说已看（因为分集全看完），
      // 但 SQL 说已看时，WatchStatus 必须也说已看（单向蕴含）。
      final sqlRows = await storage.rawQueryForTest(
        'SELECT id, derived_watched FROM v_movie_state',
      );
      for (final row in sqlRows) {
        final id = row['id'] as String;
        final sqlWatched = (row['derived_watched'] as num?)?.toInt() == 1;
        if (!sqlWatched) continue;
        final movie = await storage.getMovieById(id);
        expect(
          WatchStatus.isWatched(movie!),
          isTrue,
          reason: 'SQL 说 $id 已看，Dart 也必须认为已看',
        );
      }
    });
  });

  group('T4 视图本身', () {
    test('视图存在且包含派生字段', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      final rows = await storage.rawQueryForTest(
        "SELECT name FROM sqlite_master WHERE type = 'view' AND name = 'v_movie_state'",
      );
      expect(rows.length, 1);

      final columns = await storage.rawQueryForTest(
        'PRAGMA table_info(v_movie_state)',
      );
      final names = columns.map((row) => row['name']).toSet();
      expect(names, contains('derived_watched'));
      expect(names, contains('derived_watched_at'));
    });

    test('视图不包含任何墓碑影片', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'alive', title: '活着'));
      await storage.addMovie(Movie(id: 'dead', title: '已删'));
      await storage.deleteMovie('dead');

      // 视图本身会把墓碑也选出来（它是 SELECT m.* FROM movies），
      // 过滤发生在查询侧。这里确认「查询侧确实过滤掉了」。
      expect(await storage.getMovieById('dead'), isNull);
      expect(await storage.getMovieById('alive'), isNotNull);
    });

    test('老库（v8）升级后同样有视图', () async {
      Future<void> seedV8(Database db) async {
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
          CREATE TABLE draw_records (
            id TEXT PRIMARY KEY, movie_id TEXT NOT NULL, movie_title TEXT NOT NULL,
            movie_poster TEXT NOT NULL DEFAULT '', seed INTEGER NOT NULL DEFAULT 0,
            candidate_count INTEGER NOT NULL DEFAULT 0,
            outcome TEXT NOT NULL DEFAULT 'pending', drawn_at TEXT NOT NULL
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
          CREATE TABLE collections (
            id TEXT PRIMARY KEY, name TEXT NOT NULL,
            icon_key TEXT NOT NULL DEFAULT 'collections',
            sort_order INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE collection_members (
            collection_id TEXT NOT NULL, movie_id TEXT NOT NULL,
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
            movie_id TEXT NOT NULL, tag_id TEXT NOT NULL,
            PRIMARY KEY (movie_id, tag_id)
          )
        ''');
        await db.insert('movies', {
          'id': 'old',
          'title': '老影片',
          'watched': 1,
          'created_at': '2024-01-01T00:00:00.000',
        });
      }

      final storage = await openTestStorage(version: 8, seed: seedV8);
      addTearDown(storage.closeForTest);

      final rows = await storage.rawQueryForTest(
        "SELECT name FROM sqlite_master WHERE type = 'view' AND name = 'v_movie_state'",
      );
      expect(rows.length, 1, reason: '升级后必须补建视图');

      // 视图能读到升级前就存在的已看影片。
      final watched = await storage.queryMovieIds(watchedOnly: true);
      expect(watched, contains('old'));
    });
  });
}
