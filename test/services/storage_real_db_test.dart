// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

/// v1 时代的建表语句：只有 movies / draw_records，且 draw_records 还带着
/// 后来被 v6 删掉的旧列。用真实的旧版结构做夹具，才能验证迁移链。
Future<void> _seedV1(Database db) async {
  await db.execute('''
    CREATE TABLE movies (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      year TEXT NOT NULL DEFAULT '',
      director TEXT NOT NULL DEFAULT '',
      cast_text TEXT NOT NULL DEFAULT '',
      rating REAL NOT NULL DEFAULT 0,
      genre_json TEXT NOT NULL DEFAULT '[]',
      region TEXT NOT NULL DEFAULT '',
      poster TEXT NOT NULL DEFAULT '',
      douban_url TEXT NOT NULL DEFAULT '',
      watched INTEGER NOT NULL DEFAULT 0,
      watched_at TEXT,
      user_rating REAL,
      user_review TEXT,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_movies_created_at ON movies(created_at DESC)');
  await db.execute('''
    CREATE TABLE draw_records (
      id TEXT PRIMARY KEY,
      movie_id TEXT NOT NULL,
      movie_title TEXT NOT NULL,
      movie_poster TEXT NOT NULL DEFAULT '',
      seed INTEGER NOT NULL DEFAULT 0,
      candidate_count INTEGER NOT NULL DEFAULT 0,
      mode TEXT NOT NULL DEFAULT 'solo',
      room_code TEXT,
      participants_json TEXT,
      drawn_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_draw_records_drawn_at ON draw_records(drawn_at DESC)',
  );

  await db.insert('movies', {
    'id': 'v1_movie',
    'title': 'v1 老影片',
    'watched': 1,
    'watched_at': '2025-05-01T20:00:00.000',
    'user_rating': 4.5,
    'user_review': '很好看',
    'created_at': '2025-05-01T19:00:00.000',
  });
  await db.insert('draw_records', {
    'id': 'v1_draw',
    'movie_id': 'v1_movie',
    'movie_title': 'v1 老影片',
    'seed': 42,
    'candidate_count': 10,
    'mode': 'solo',
    'drawn_at': '2025-05-01T19:30:00.000',
  });
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('T5a 迁移链：旧版夹具升到最新，数据不丢', () {
    test('v1 → 最新：影片、抽片记录都在，旧列被清理', () async {
      final storage = await openTestStorage(version: 1, seed: _seedV1);
      addTearDown(storage.closeForTest);

      final movies = await storage.queryMovies(limit: 50, offset: 0);
      expect(movies.length, 1);
      expect(movies.single.id, 'v1_movie');
      expect(movies.single.title, 'v1 老影片');
      expect(movies.single.userRating, 4.5);
      expect(movies.single.userReview, '很好看');

      final draws = await storage.queryDrawRecords(limit: 50, offset: 0);
      expect(draws.length, 1);
      expect(draws.single.id, 'v1_draw');

      // v6 应把遗留的 mode/room_code/participants_json 列删掉。
      final columns = await storage.rawQueryForTest(
        'PRAGMA table_info(draw_records)',
      );
      final names = columns.map((row) => row['name']).toSet();
      expect(names, isNot(contains('mode')));
      expect(names, isNot(contains('room_code')));
      expect(names, isNot(contains('participants_json')));
    });

    test('v1 → 最新：watched=1 的影片被补出观影会话（v4 回填）', () async {
      final storage = await openTestStorage(version: 1, seed: _seedV1);
      addTearDown(storage.closeForTest);

      final sessions = await storage.querySessionsByMovie('v1_movie');
      expect(sessions, isNotEmpty);
      expect(sessions.single.rating, 4.5);
      expect(sessions.single.note, '很好看');
    });

    test('v1 → 最新：数据库版本号到达当前值', () async {
      final storage = await openTestStorage(version: 1, seed: _seedV1);
      addTearDown(storage.closeForTest);

      final version = await storage.rawQueryForTest('PRAGMA user_version');
      expect(version.single.values.single, currentDatabaseVersion);
    });

    test('重复打开同一版本不重复迁移（幂等）', () async {
      final path = newTestDbPath();
      final storage = await openTestStorage(
        version: 1,
        seed: _seedV1,
        path: path,
      );
      final before = await storage.countSessions();
      await storage.closeForTest();

      // 用同一路径重新打开（已是当前版本），不应再次回填会话。
      final again = await openTestStorage(path: path);
      addTearDown(again.closeForTest);
      expect(await again.countSessions(), before);
    });
  });

  group('T5a 搜索：LIKE 通配符必须当字面量', () {
    test(r'输入 100% / a_b / \ 只匹配字面量', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      for (final title in ['100%纯爱', '100部电影', 'a_b', 'axb', r'反斜杠\测试']) {
        await storage.addMovie(Movie(id: 'm_$title', title: title));
      }

      Future<List<String>> search(String query) async {
        final result = await storage.queryMovies(
          limit: 50,
          offset: 0,
          searchQuery: query,
        );
        return result.map((m) => m.title).toList();
      }

      expect(await search('100%'), ['100%纯爱']);
      expect(await search('100%纯'), ['100%纯爱']);
      // 未转义时 `_` 会匹配任意单字符，从而把 axb 也带出来。
      expect(await search('a_b'), ['a_b']);
      // 未转义时 `\` 是转义符，可能整条查询失败或匹配异常。
      expect(await search(r'\'), [r'反斜杠\测试']);
    });

    test('中文搜索正常', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'c1', title: '霸王别姬', director: '陈凯歌'));

      final byTitle = await storage.queryMovies(
        limit: 10,
        offset: 0,
        searchQuery: '霸王',
      );
      expect(byTitle.map((m) => m.id), ['c1']);

      final byDirector = await storage.queryMovies(
        limit: 10,
        offset: 0,
        searchQuery: '陈凯歌',
      );
      expect(byDirector.map((m) => m.id), ['c1']);
    });

    test('searchQuery 里的 % 不会变成「匹配全部」', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'x1', title: '普通影片'));
      await storage.addMovie(Movie(id: 'x2', title: '含%号'));

      final result = await storage.queryMovies(
        limit: 10,
        offset: 0,
        searchQuery: '%',
      );
      expect(result.map((m) => m.id), ['x2']);
    });
  });

  group('T5a 已看判定：三种来源在列表与计数上必须一致', () {
    test('显式 watched / 仅有会话 / 剧集全看完', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      // 1) 显式 watched=true，没有任何会话
      await storage.addMovie(
        Movie(id: 'explicit', title: '显式已看', watched: true),
      );
      // 2) 影片本身 watched=false，但存在一条观影会话
      await storage.addMovie(Movie(id: 'bySession', title: '靠会话已看'));
      await storage.addSession(
        ViewingSession(
          id: 's1',
          movieId: 'bySession',
          watchedAt: DateTime(2026, 3, 1, 20),
        ),
      );
      // 3) 未看
      await storage.addMovie(Movie(id: 'unwatched', title: '未看'));

      final watchedCount = await storage.countMovies(watchedOnly: true);
      final unwatchedCount = await storage.countMovies(unwatchedOnly: true);
      final total = await storage.countMovies();

      expect(total, 3);
      expect(watchedCount, 2);
      expect(unwatchedCount, 1);
      // 两种筛选加起来必须等于总数，不能出现既算已看又算未看的重叠。
      expect(watchedCount + unwatchedCount, total);

      final watched = await storage.queryMovies(
        limit: 50,
        offset: 0,
        watchedOnly: true,
      );
      expect(watched.map((m) => m.id).toSet(), {'explicit', 'bySession'});

      final unwatched = await storage.queryMovies(
        limit: 50,
        offset: 0,
        unwatchedOnly: true,
      );
      expect(unwatched.map((m) => m.id), ['unwatched']);
    });

    test('列表条数与 queryMovieIds 结果一致', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'a', title: 'A', watched: true));
      await storage.addMovie(Movie(id: 'b', title: 'B'));

      for (final watchedOnly in [true, false]) {
        final ids = await storage.queryMovieIds(watchedOnly: watchedOnly);
        final count = await storage.countMovies(watchedOnly: watchedOnly);
        final list = await storage.queryMovies(
          limit: 100,
          offset: 0,
          watchedOnly: watchedOnly,
        );
        expect(ids.length, count, reason: 'watchedOnly=$watchedOnly');
        expect(list.length, count, reason: 'watchedOnly=$watchedOnly');
        expect(
          ids.toSet(),
          list.map((m) => m.id).toSet(),
          reason: 'watchedOnly=$watchedOnly',
        );
      }
    });
  });

  group('T5a 备份往返：导出再导入内容一致', () {
    test('影片 + 会话 + 抽片记录往返后一致', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(
        Movie(
          id: 'rt1',
          title: '往返影片',
          year: '2020',
          director: '某人',
          genre: const ['剧情'],
          watched: true,
        ),
      );
      await storage.addSession(
        ViewingSession(
          id: 'rt_session',
          movieId: 'rt1',
          watchedAt: DateTime(2026, 5, 1, 21),
          note: '好片',
          rating: 5,
        ),
      );
      await storage.addDrawRecord(
        DrawRecord(
          id: 'rt_draw',
          movieId: 'rt1',
          movieTitle: '往返影片',
          moviePoster: '',
          seed: 7,
          candidateCount: 3,
          drawnAt: DateTime(2026, 5, 1, 21),
        ),
      );

      final moviesBefore = await storage.getAllMoviesForBackup();
      final sessionsBefore = await storage.getAllSessionsForBackup();
      final drawsBefore = await storage.getAllDrawRecordsForBackup();

      // 复原到新库：用 addMovieDirectly（备份恢复路径），它不是「新增」入口。
      final restored = await openTestStorage();
      addTearDown(restored.closeForTest);
      for (final movie in moviesBefore) {
        await restored.addMovieDirectly(movie);
      }
      for (final session in sessionsBefore) {
        await restored.addSessionIfNotExists(session);
      }
      for (final draw in drawsBefore) {
        await restored.addDrawRecord(draw);
      }

      final moviesAfter = await restored.getAllMoviesForBackup();
      expect(moviesAfter.single.id, 'rt1');
      expect(moviesAfter.single.title, '往返影片');
      expect(moviesAfter.single.director, '某人');
      expect(moviesAfter.single.genre, ['剧情']);
      expect(moviesAfter.single.watched, isTrue);

      final sessionsAfter = await restored.getAllSessionsForBackup();
      expect(sessionsAfter.single.id, 'rt_session');
      expect(sessionsAfter.single.note, '好片');
      expect(sessionsAfter.single.rating, 5);

      final drawsAfter = await restored.getAllDrawRecordsForBackup();
      expect(drawsAfter.single.id, 'rt_draw');
      expect(drawsAfter.single.seed, 7);
    });
  });

  group('T5a 删除影片的关联清理', () {
    test('删影片后会话、合集成员、标签关联都不再可见（不留可见孤儿）', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'del', title: '待删'));
      await storage.addSession(
        ViewingSession(
          id: 's_del',
          movieId: 'del',
          watchedAt: DateTime(2026, 1, 1),
        ),
      );
      final collection = await storage.addCollection(
        MovieCollection(id: '', name: '合集'),
      );
      await storage.addMovieToCollection(collection.id, 'del');
      final tag = await storage.addTag(
        MovieTag(id: '', name: '标签', colorValue: 0xFF000000),
      );
      await storage.setMovieTags('del', [tag.id]);

      await storage.deleteMovie('del');

      // T3 之后删除是「软删除」：行还在（带墓碑），但所有面向用户的
      // 查询都不再返回它们。这里断言的是「界面看不到孤儿」，
      // 而不是「物理行消失」——墓碑正是同步能传达删除的依据。
      expect(await storage.getMovieById('del'), isNull);
      expect(await storage.querySessionsByMovie('del'), isEmpty);
      expect(await storage.queryCollectionMemberIds(collection.id), isEmpty);
      expect(await storage.queryTagsForMovie('del'), isEmpty);

      // 墓碑确实写进了库（否则另一台设备无法得知这次删除）。
      final tombstoned = await storage.rawQueryForTest(
        "SELECT deleted_at FROM movies WHERE id = 'del'",
      );
      expect(tombstoned.single['deleted_at'], isNotNull);
    });

    test('墓碑满保留期后可被物理清理', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'gone', title: '要清理的'));
      await storage.deleteMovie('gone');

      // 默认保留 90 天：刚删的不会被清掉。
      await storage.purgeTombstones();
      expect(
        (await storage.rawQueryForTest(
          "SELECT id FROM movies WHERE id = 'gone'",
        ))
            .length,
        1,
      );

      // retentionDays = 0 视为「立即过期」，用于验证清理路径本身可用。
      await storage.purgeTombstones(retentionDays: -1);
      expect(
        (await storage.rawQueryForTest(
          "SELECT id FROM movies WHERE id = 'gone'",
        )),
        isEmpty,
      );
    });
  });
}
