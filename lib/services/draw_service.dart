import 'dart:math';

import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/watch_status.dart';

/// Result of a draw computation
class DrawResultData {
  final Movie selectedMovie;
  final int seed;
  final int index;

  DrawResultData({
    required this.selectedMovie,
    required this.seed,
    required this.index,
  });
}

/// 抽片所需的上下文：用于公平 / 优先未看模式计算权重。
class DrawContext {
  /// 最近窗口内抽过的影片 id（公平模式降权）
  final Set<String> recentlyDrawnIds;

  /// 最近窗口内看过的影片 id（公平模式降权）
  final Set<String> recentlyWatchedIds;

  const DrawContext({
    this.recentlyDrawnIds = const {},
    this.recentlyWatchedIds = const {},
  });

  static const DrawContext empty = DrawContext();
}

/// Draw logic — pure static methods, no state
class DrawService {
  /// 公平模式：最近抽过/看过的影片的权重系数（越小越不容易被抽中）
  static const double _recentPenalty = 0.2;

  /// 优先未看模式：未看影片的权重系数（越大越容易被抽中）
  static const double _unwatchedBoost = 4.0;

  /// 兼容旧调用：纯随机抽一部。
  static DrawResultData soloRandom(List<Movie> candidates) {
    return draw(candidates, mode: DrawMode.pureRandom);
  }

  /// 统一抽片入口：按 [mode] 计算权重并抽取一部。
  ///
  /// 返回结果携带 [DrawResultData.seed]，供前端做确定性洗牌动画。
  static DrawResultData draw(
    List<Movie> candidates, {
    required DrawMode mode,
    DrawContext context = DrawContext.empty,
  }) {
    if (candidates.isEmpty) {
      throw ArgumentError('候选影片列表不能为空');
    }

    final seed = DateTime.now().microsecondsSinceEpoch;
    final weights = _buildWeights(candidates, mode: mode, context: context);
    final index = _weightedIndex(weights, seed);

    return DrawResultData(
      selectedMovie: candidates[index],
      seed: seed,
      index: index,
    );
  }

  /// 三选一：按 [mode] 的权重抽取最多 3 部不重复的影片。
  static List<Movie> threePickOne(
    List<Movie> candidates, {
    DrawMode mode = DrawMode.pureRandom,
    DrawContext context = DrawContext.empty,
  }) {
    if (candidates.isEmpty) {
      throw ArgumentError('候选影片列表不能为空');
    }

    final pickCount = min(3, candidates.length);
    final pool = List<Movie>.from(candidates);
    final weights = _buildWeights(pool, mode: mode, context: context);
    final picked = <Movie>[];

    var seed = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < pickCount; i++) {
      final index = _weightedIndex(weights, seed);
      picked.add(pool.removeAt(index));
      weights.removeAt(index);
      // 让后续抽取使用不同的确定性种子
      seed = (seed ~/ 7) + 0x9E3779B9;
    }
    return picked;
  }

  /// 按筛选条件过滤候选影片。
  ///
  /// 时长按 [DrawFilter.maxDurationMinutes] 上限筛选；无时长信息的影片
  /// 在设置了时长上限时会被排除（避免把未知时长的片混进预算）。
  ///
  /// [allowedMovieIds] 非空时，仅保留 id 在集合中的影片（用于标签维度，
  /// 标签为影片级关联，由调用方解析为 id 集合后注入）。
  static List<Movie> smartFilter(
    List<Movie> movies,
    DrawFilter filter, {
    Set<String>? allowedMovieIds,
  }) {
    if (!filter.isActive && allowedMovieIds == null) return movies;

    final director = filter.director.trim().toLowerCase();

    return movies.where((movie) {
      if (allowedMovieIds != null && !allowedMovieIds.contains(movie.id)) {
        return false;
      }

      if (filter.maxDurationMinutes != null) {
        final duration = movie.durationMinutes;
        if (duration == null || duration > filter.maxDurationMinutes!) {
          return false;
        }
      }

      if (filter.genres.isNotEmpty) {
        final hit = movie.genre.any(filter.genres.contains);
        if (!hit) return false;
      }

      if (filter.minYear != null || filter.maxYear != null) {
        final year = _movieYear(movie);
        if (year == null) return false;
        if (filter.minYear != null && year < filter.minYear!) return false;
        if (filter.maxYear != null && year > filter.maxYear!) return false;
      }

      if (filter.regions.isNotEmpty) {
        final region = movie.region;
        final hit = filter.regions.any(region.contains);
        if (!hit) return false;
      }

      if (filter.minRating != null && movie.rating < filter.minRating!) {
        return false;
      }
      if (filter.maxRating != null && movie.rating > filter.maxRating!) {
        return false;
      }

      if (director.isNotEmpty &&
          !movie.director.toLowerCase().contains(director)) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Build a DrawRecord for a draw result.
  static DrawRecord buildSoloRecord({
    required DrawResultData result,
    required int candidateCount,
    DrawOutcome outcome = DrawOutcome.pending,
  }) {
    return DrawRecord(
      id: 'draw_${DateTime.now().millisecondsSinceEpoch}',
      movieId: result.selectedMovie.id,
      movieTitle: result.selectedMovie.title,
      moviePoster: result.selectedMovie.poster,
      seed: result.seed,
      candidateCount: candidateCount,
      outcome: outcome,
      drawnAt: DateTime.now(),
    );
  }

  // ========== 内部权重计算 ==========

  static List<double> _buildWeights(
    List<Movie> candidates, {
    required DrawMode mode,
    required DrawContext context,
  }) {
    return candidates.map((movie) {
      switch (mode) {
        case DrawMode.pureRandom:
        case DrawMode.threePickOne:
          return 1.0;
        case DrawMode.fair:
          var weight = 1.0;
          if (context.recentlyDrawnIds.contains(movie.id)) {
            weight *= _recentPenalty;
          }
          if (WatchStatus.isWatched(movie) ||
              context.recentlyWatchedIds.contains(movie.id)) {
            weight *= _recentPenalty;
          }
          return weight;
        case DrawMode.priorityUnwatched:
          return WatchStatus.isWatched(movie) ? 1.0 : _unwatchedBoost;
      }
    }).toList();
  }

  /// 用 [seed] 在加权分布上确定性地选出一个下标。
  /// 全部权重为 0 时退化为均匀分布。
  static int _weightedIndex(List<double> weights, int seed) {
    final total = weights.fold<double>(0, (sum, w) => sum + w);
    if (total <= 0) {
      return seed.abs() % weights.length;
    }

    // 用 seed 派生一个 [0, total) 的确定性目标值
    final fraction = (seed.abs() % 1000000) / 1000000;
    var target = fraction * total;
    for (var i = 0; i < weights.length; i++) {
      target -= weights[i];
      if (target < 0) return i;
    }
    return weights.length - 1;
  }

  static int? _movieYear(Movie movie) {
    final match = RegExp(r'\d{4}').firstMatch(movie.year);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }
}
