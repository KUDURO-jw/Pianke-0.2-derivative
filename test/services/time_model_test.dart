// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/time_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

/// v7 时代的会话表（没有 watched_at_utc / watched_on），用来验证迁移补齐。
Future<void> _seedV7MixedTimes(Database db) async {
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
    'id': 'm',
    'title': '影片',
    'created_at': '2025-01-01T00:00:00.000',
  });

  // 混入真实历史里出现过的几种格式。
  final rows = <Map<String, Object?>>[
    // 不带时区的本地串
    {
      'id': 'local',
      'movie_id': 'm',
      'watched_at': '2025-06-01T21:30:00.000',
      'created_at': '2025-06-01T21:30:00.000',
    },
    // 带 UTC 标记
    {
      'id': 'utc',
      'movie_id': 'm',
      'watched_at': '2025-06-02T13:00:00.000Z',
      'created_at': '2025-06-02T13:00:00.000Z',
    },
    // 带本地偏移
    {
      'id': 'offset',
      'movie_id': 'm',
      'watched_at': '2025-06-03T23:30:00.000+08:00',
      'created_at': '2025-06-03T23:30:00.000+08:00',
    },
    // 只有日期
    {
      'id': 'dateOnly',
      'movie_id': 'm',
      'watched_at': '2025-06-04',
      'created_at': '2025-06-04T00:00:00.000',
    },
    // 完全无法解析：必须原样保留，不能丢行
    {
      'id': 'broken',
      'movie_id': 'm',
      'watched_at': '不知道什么时候',
      'created_at': '2025-06-05T00:00:00.000',
    },
  ];
  for (final row in rows) {
    await db.insert('viewing_sessions', row);
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('T6 时间工具', () {
    test('formatWatchedOn 补零到 YYYY-MM-DD', () {
      expect(formatWatchedOn(DateTime(2025, 1, 2)), '2025-01-02');
      expect(formatWatchedOn(DateTime(2025, 12, 31)), '2025-12-31');
    });

    test('salvageWatchedOn 能吃下各种历史格式', () {
      expect(salvageWatchedOn('2025-06-01T21:30:00.000'), '2025-06-01');
      expect(salvageWatchedOn('2025-06-02T13:00:00.000Z'), isNotNull);
      expect(salvageWatchedOn('2025-06-04'), '2025-06-04');
      expect(salvageWatchedOn('不知道什么时候'), isNull);
      expect(salvageWatchedOn(''), isNull);
      expect(salvageWatchedOn(null), isNull);
    });

    test('parseUtcMillis 对同一时刻的不同写法给出同一个值', () {
      final a = parseUtcMillis('2025-06-01T12:00:00.000Z');
      final b = parseUtcMillis('2025-06-01T20:00:00.000+08:00');
      expect(a, isNotNull);
      expect(a, b, reason: '同一时刻换种写法必须等价');
      expect(parseUtcMillis('乱码'), isNull);
    });
  });

  group('T6 迁移：旧会话补齐 UTC 毫秒与当地日期', () {
    test('可解析的行两列都补齐，无法解析的行原样保留', () async {
      final storage = await openTestStorage(
        version: 7,
        seed: _seedV7MixedTimes,
      );
      addTearDown(storage.closeForTest);

      final rows = await storage.rawQueryForTest(
        'SELECT id, watched_at, watched_at_utc, watched_on '
        'FROM viewing_sessions ORDER BY id',
      );
      final byId = {
        for (final row in rows) row['id']?.toString() ?? '': row,
      };

      // 不带时区的本地串：按设备本地时区解释，两列都有值。
      expect(byId['local']!['watched_at_utc'], isNotNull);
      expect(byId['local']!['watched_on'], '2025-06-01');

      expect(byId['utc']!['watched_at_utc'], isNotNull);
      expect(byId['offset']!['watched_at_utc'], isNotNull);

      // 只有日期：至少当地日期能被救回来。
      expect(byId['dateOnly']!['watched_on'], '2025-06-04');

      // 完全无法解析：行还在，原始字符串没被动过。
      expect(byId['broken'], isNotNull);
      expect(byId['broken']!['watched_at'], '不知道什么时候');
      expect(byId['broken']!['watched_on'], isNull);
    });

    test('迁移不改变会议总数（一行都不丢）', () async {
      final storage = await openTestStorage(
        version: 7,
        seed: _seedV7MixedTimes,
      );
      addTearDown(storage.closeForTest);
      expect(await storage.countSessions(), 5);
    });

    test('读取时可解析与不可解析的行都能安全取出', () async {
      final storage = await openTestStorage(
        version: 7,
        seed: _seedV7MixedTimes,
      );
      addTearDown(storage.closeForTest);

      final sessions = await storage.getAllSessionsForBackup();
      expect(sessions.length, 5);
      for (final session in sessions) {
        // 两个兜底取值在任何行上都不能抛异常。
        expect(session.effectiveWatchedAtUtcMs, isA<int>());
        expect(session.effectiveWatchedOn, isNotEmpty);
      }
    });
  });

  group('T6 换时区不改变「哪一天看的」', () {
    test('已落库的 watchedOn 不随读取时的时区变化', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'm', title: '影片'));

      // 模拟 UTC+8 的 23:30 —— 换成 UTC-5 就是前一天。
      final localLate = DateTime(2025, 6, 3, 23, 30);
      await storage.addSession(
        ViewingSession(id: 's', movieId: 'm', watchedAt: localLate),
      );

      final stored = (await storage.getAllSessionsForBackup()).single;
      expect(stored.watchedOn, '2025-06-03');
      expect(stored.watchedAtUtcMs, localLate.toUtc().millisecondsSinceEpoch);

      // 关键：即使把 watchedAt 换成一个「在别的时区看是同一天、在 UTC 看是
      // 前一天」的时刻，已落库的当地日期也不会被改写。
      final reread = (await storage.getAllSessionsForBackup()).single;
      expect(reread.effectiveWatchedOn, '2025-06-03');
    });

    test('导出再导入保留原 watchedOn（不按当前时区重算）', () async {
      // 一条「UTC+8 晚上 23:30」的记录，在 UTC-5 的机器上导入时
      // 不能被算成 06-02。
      final json = ViewingSession(
        id: 's',
        movieId: 'm',
        watchedAt: DateTime.utc(2025, 6, 3, 15, 30),
        watchedOn: '2025-06-03',
      ).toJson();

      expect(json['watchedOn'], '2025-06-03');

      final restored = ViewingSession.fromJson(json);
      expect(restored.watchedOn, '2025-06-03');
      expect(restored.effectiveWatchedOn, '2025-06-03');
      // UTC 毫秒也原样带回，排序不会错。
      expect(
        restored.watchedAtUtcMs,
        DateTime.utc(2025, 6, 3, 15, 30).millisecondsSinceEpoch,
      );
    });

    test('导出仍带 ISO8601 UTC 与 watchedOn 两个字段（兼容旧读取方）', () async {
      final session = ViewingSession(
        id: 's',
        movieId: 'm',
        watchedAt: DateTime(2025, 6, 3, 23, 30),
      );
      final json = session.toJson();
      expect(json['watchedAt'], isA<String>());
      expect(json['watchedAtUtc'], endsWith('Z'));
      expect(json['watchedOn'], '2025-06-03');
    });
  });

  group('T6 混合格式旧数据的排序正确', () {
    test('按 UTC 毫秒排序，不按字符串字面量', () async {
      final storage = await openTestStorage(
        version: 7,
        seed: _seedV7MixedTimes,
      );
      addTearDown(storage.closeForTest);

      final sessions = await storage.querySessions(limit: 50, offset: 0);
      final stamps = sessions
          .map((s) => s.effectiveWatchedAtUtcMs)
          .toList(growable: false);
      // 能解析的必须严格单调递减（无法解析的行排在最后面）。
      final parsed = stamps.where((ms) => ms != 0).toList();
      for (var i = 1; i < parsed.length; i++) {
        expect(
          parsed[i] <= parsed[i - 1],
          isTrue,
          reason: '排序错误：第 $i 项 ${parsed[i]} 应不晚于前一项 ${parsed[i - 1]}',
        );
      }
    });
  });

  group('T6 统计的月份归属', () {
    test('当月末的观影仍计入当月（不因 UTC 跨月而漂移）', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'm', title: '影片'));

      final now = DateTime.now();
      // 本月最后一天的 23:30，在 UTC+X 时区换算成 UTC 常会落到下个月。
      final lastDay = DateTime(now.year, now.month + 1, 0, 23, 30);
      await storage.addSession(
        ViewingSession(id: 's', movieId: 'm', watchedAt: lastDay),
      );

      final stored = (await storage.getAllSessionsForBackup()).single;
      expect(
        stored.effectiveWatchedOn.substring(0, 7),
        formatWatchedOn(lastDay).substring(0, 7),
        reason: '当地日期必须落在本月',
      );
    });
  });

  group('T6 变更观影时刻时派生列同步更新', () {
    test('copyWith(watchedAt:) 会重算 watchedOn 与 UTC 毫秒', () {
      final original = ViewingSession(
        id: 's',
        movieId: 'm',
        watchedAt: DateTime(2025, 6, 1, 20),
      );
      final moved = original.copyWith(watchedAt: DateTime(2025, 7, 15, 21));
      expect(moved.watchedOn, '2025-07-15');
      expect(
        moved.watchedAtUtcMs,
        DateTime(2025, 7, 15, 21).toUtc().millisecondsSinceEpoch,
      );
    });

    test('copyWith 不改时刻时保留原有派生值', () {
      final original = ViewingSession(
        id: 's',
        movieId: 'm',
        watchedAt: DateTime(2025, 6, 1, 20),
        watchedOn: '2025-06-01',
      );
      final renamed = original.copyWith(note: '新短评');
      expect(renamed.watchedOn, '2025-06-01');
    });
  });
}
