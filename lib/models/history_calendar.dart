import 'package:random_movie/models/movie.dart';

class HistoryMonthKey {
  final int year;
  final int month;

  const HistoryMonthKey({required this.year, required this.month});

  factory HistoryMonthKey.fromDate(DateTime date) {
    return HistoryMonthKey(year: date.year, month: date.month);
  }

  DateTime get firstDay => DateTime(year, month);

  DateTime get lastDay => DateTime(year, month + 1, 0, 23, 59, 59, 999);

  HistoryMonthKey previous() {
    final previousMonth = DateTime(year, month - 1);
    return HistoryMonthKey.fromDate(previousMonth);
  }

  HistoryMonthKey next() {
    final nextMonth = DateTime(year, month + 1);
    return HistoryMonthKey.fromDate(nextMonth);
  }

  @override
  bool operator ==(Object other) {
    return other is HistoryMonthKey &&
        other.year == year &&
        other.month == month;
  }

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}

class HistoryDaySummary {
  final DateTime date;
  final List<Movie> movies;

  /// 每部剧在这一天看了哪几集：影片 id → 集号列表（升序）。
  ///
  /// 只有通过「勾选分集」进日历的剧才有条目；电影和「记录观影」
  /// 进来的是空映射。日历格子仍只显示海报与影片数，
  /// 集号明细在点击某天后的弹层里展示。
  final Map<String, List<int>> episodeNumbersByMovieId;

  const HistoryDaySummary({
    required this.date,
    required this.movies,
    this.episodeNumbersByMovieId = const {},
  });

  bool get hasMovies => movies.isNotEmpty;

  int get count => movies.length;

  String get primaryPoster {
    for (final movie in movies) {
      if (movie.poster.isNotEmpty) {
        return movie.poster;
      }
    }
    return '';
  }

  /// 取某部剧当天看的集号；没有则返回空列表。
  List<int> episodeNumbersOf(String movieId) =>
      episodeNumbersByMovieId[movieId] ?? const [];

  /// 把集号压缩成人类可读的区间文本。
  ///
  /// `[5,6,7]` → `第 5-7 集`；`[5,7,9]` → `第 5、7、9 集`；
  /// `[5]` → `第 5 集`。
  static String formatEpisodeNumbers(List<int> numbers) {
    if (numbers.isEmpty) return '';
    final sorted = [...numbers]..sort();
    final parts = <String>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final n = sorted[i];
      if (n == prev + 1) {
        prev = n;
        continue;
      }
      parts.add(start == prev ? '$start' : '$start-$prev');
      start = n;
      prev = n;
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    return '第 ${parts.join('、')} 集';
  }
}

class HistoryMonthData {
  final HistoryMonthKey month;
  final Map<int, HistoryDaySummary> summariesByDay;

  const HistoryMonthData({required this.month, required this.summariesByDay});

  bool get isEmpty => summariesByDay.isEmpty;

  HistoryDaySummary? summaryForDay(int day) => summariesByDay[day];
}
