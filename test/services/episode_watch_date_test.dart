// 回归：电视剧分集记录日期，让观影日历能显示追剧过程。
//
// 背景：电影在详情页点「记录观影」会写一条带日期的观影会话，日历能读到。
// 但电视剧是逐集勾选的，原来 `MovieEpisode` 只有 `watched` 布尔值、
// 没有日期，于是花几天看完的剧在日历上全是空白。
//
// 本次改动：
// - `MovieEpisode` 新增 `watchedAt`
// - 勾选时写当天日期，取消时清空
// - 日历按「每一集的日期」聚合，同一天可显示「第 5-7 集」
// - 老数据没有日期 → 不补假日期、不参与聚合
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/history_calendar.dart';
import 'package:random_movie/models/movie.dart';

void main() {
  group('MovieEpisode.watchedAt 序列化', () {
    test('带日期往返后保留', () {
      final at = DateTime(2026, 11, 12, 20, 30);
      final episode = MovieEpisode(
        number: 5,
        label: '第5集',
        doubanUrl: '',
        watched: true,
        watchedAt: at,
      );

      final json = episode.toJson();
      expect(json['watchedAt'], at.toIso8601String());

      final restored = MovieEpisode.fromJson(json);
      expect(restored.watchedAt, at);
      expect(restored.number, 5);
      expect(restored.watched, isTrue);
    });

    test('老数据没有 watchedAt 时解析为 null，不报错', () {
      // 这是升级前存下来的形状：只有 watched。
      final restored = MovieEpisode.fromJson({
        'number': 3,
        'label': '第3集',
        'doubanUrl': '',
        'watched': true,
      });

      expect(restored.watched, isTrue);
      expect(restored.watchedAt, isNull, reason: '老数据不补假日期');
    });

    test('watchedAt 格式损坏时退回 null，不影响其它字段', () {
      final restored = MovieEpisode.fromJson({
        'number': 2,
        'label': '第2集',
        'doubanUrl': '',
        'watched': true,
        'watchedAt': '不是日期',
      });

      expect(restored.watched, isTrue);
      expect(restored.watchedAt, isNull);
    });

    test('没有日期时不写出 watchedAt 字段（保持旧 JSON 形状）', () {
      final episode = MovieEpisode(
        number: 1,
        label: '第1集',
        doubanUrl: '',
        watched: false,
      );
      expect(episode.toJson().containsKey('watchedAt'), isFalse);
    });

    test('copyWith 能写入日期', () {
      final episode = MovieEpisode(
        number: 1,
        label: '第1集',
        doubanUrl: '',
        watched: false,
      );
      final at = DateTime(2026, 11, 12);

      final updated = episode.copyWith(watched: true, watchedAt: at);
      expect(updated.watchedAt, at);
      expect(updated.watched, isTrue);
    });

    test('copyWith(clearWatchedAt) 能真正清空日期', () {
      final episode = MovieEpisode(
        number: 1,
        label: '第1集',
        doubanUrl: '',
        watched: true,
        watchedAt: DateTime(2026, 11, 12),
      );

      // 只传 null 无法表达「清空」，必须用显式开关。
      final unchanged = episode.copyWith(watched: false);
      expect(unchanged.watchedAt, isNotNull, reason: '不传 clear 时日期应保留');

      final cleared = episode.copyWith(
        watched: false,
        clearWatchedAt: true,
      );
      expect(cleared.watchedAt, isNull, reason: '取消勾选要真的抹掉日期');
    });
  });

  group('集号区间压缩', () {
    test('连续集号合并成区间', () {
      expect(
        HistoryDaySummary.formatEpisodeNumbers([5, 6, 7]),
        '第 5-7 集',
      );
    });

    test('单集不带连字符', () {
      expect(HistoryDaySummary.formatEpisodeNumbers([5]), '第 5 集');
    });

    test('不连续用顿号分隔', () {
      expect(
        HistoryDaySummary.formatEpisodeNumbers([5, 7, 9]),
        '第 5、7、9 集',
      );
    });

    test('混合区间与单集', () {
      expect(
        HistoryDaySummary.formatEpisodeNumbers([3, 4, 5, 8, 10, 11]),
        '第 3-5、8、10-11 集',
      );
    });

    test('乱序输入也能正确压缩', () {
      expect(
        HistoryDaySummary.formatEpisodeNumbers([7, 5, 6]),
        '第 5-7 集',
      );
    });

    test('空列表返回空串', () {
      expect(HistoryDaySummary.formatEpisodeNumbers([]), '');
    });
  });

  group('HistoryDaySummary 携带集号明细', () {
    test('按影片 id 取集号，未记录时返回空', () {
      final summary = HistoryDaySummary(
        date: DateTime(2026, 11, 12),
        movies: const [],
        episodeNumbersByMovieId: const {
          'douban_1': [5, 6, 7],
        },
      );

      expect(summary.episodeNumbersOf('douban_1'), [5, 6, 7]);
      expect(summary.episodeNumbersOf('douban_2'), isEmpty);
    });

    test('默认构造时集号为空，不报错', () {
      final summary = HistoryDaySummary(
        date: DateTime(2026, 11, 12),
        movies: const [],
      );
      expect(summary.episodeNumbersOf('any'), isEmpty);
    });
  });
}
