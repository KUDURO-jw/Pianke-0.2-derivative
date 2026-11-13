// 端到端：勾选分集后，日历能按天显示剧集与集号。
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/history_calendar.dart';
import 'package:random_movie/models/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  /// 造一部剧：n 集，指定哪几集在哪天看过。
  Movie seriesWith({
    required String id,
    required int episodes,
    required Map<int, DateTime> watchedDays,
  }) {
    return Movie(
      id: id,
      title: '剧$id',
      subjectType: MovieSubjectType.tvSeries,
      episodes: List.generate(episodes, (i) {
        final number = i + 1;
        final at = watchedDays[number];
        return MovieEpisode(
          number: number,
          label: '第$number集',
          doubanUrl: '',
          watched: at != null,
          watchedAt: at,
        );
      }),
    );
  }

  group('分集日期进入日历', () {
    test('按集日期查询能捞出对应月份', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(
        seriesWith(
          id: 's1',
          episodes: 10,
          watchedDays: {
            1: DateTime(2026, 11, 10),
            2: DateTime(2026, 11, 10),
            3: DateTime(2026, 11, 12),
          },
        ),
      );

      final november = await storage.querySeriesEpisodesByMonth(
        DateTime(2026, 11),
      );
      expect(november, hasLength(1));
      expect(november.first.episodeNumbers, [1, 2, 3]);

      final december = await storage.querySeriesEpisodesByMonth(
        DateTime(2026, 12),
      );
      expect(december, isEmpty, reason: '12 月没有分集日期');
    });

    test('老数据（没有 watchedAt）不进入日历', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      // 全部已看，但都没有日期——模拟升级前的老数据。
      final legacy = Movie(
        id: 'legacy',
        title: '老剧',
        subjectType: MovieSubjectType.tvSeries,
        episodes: List.generate(
          5,
          (i) => MovieEpisode(
            number: i + 1,
            label: '第${i + 1}集',
            doubanUrl: '',
            watched: true,
          ),
        ),
      );
      await storage.addMovie(legacy);

      final result = await storage.querySeriesEpisodesByMonth(
        DateTime(2026, 11),
      );
      expect(
        result,
        isEmpty,
        reason: '没有日期的分集不应进入日历，也不能被补成今天',
      );
    });

    test('只统计同一部剧在该月的集号', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(
        seriesWith(
          id: 's2',
          episodes: 8,
          watchedDays: {
            1: DateTime(2026, 10, 30),
            2: DateTime(2026, 11, 3),
            3: DateTime(2026, 11, 5),
          },
        ),
      );

      final nov = await storage.querySeriesEpisodesByMonth(DateTime(2026, 11));
      expect(nov.first.episodeNumbers, [2, 3], reason: '10/30 那集不算进 11 月');
    });

    test('删除的剧不出现在日历里', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(
        seriesWith(
          id: 'gone',
          episodes: 3,
          watchedDays: {1: DateTime(2026, 11, 10)},
        ),
      );
      await storage.deleteMovie('gone');

      final result = await storage.querySeriesEpisodesByMonth(
        DateTime(2026, 11),
      );
      expect(result, isEmpty, reason: '已删除的剧不应出现在日历');
    });
  });

  group('集号压缩与实际数据配合', () {
    test('同一天看多集压缩成区间', () {
      final summary = HistoryDaySummary(
        date: DateTime(2026, 11, 12),
        movies: const [],
        episodeNumbersByMovieId: const {
          's1': [5, 6, 7],
        },
      );
      expect(
        HistoryDaySummary.formatEpisodeNumbers(summary.episodeNumbersOf('s1')),
        '第 5-7 集',
      );
    });
  });
}
