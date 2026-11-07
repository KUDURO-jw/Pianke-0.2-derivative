import 'package:random_movie/models/movie.dart';

/// 全库唯一的「是否已看」判定入口，片库与抽片逻辑共用。
///
/// [Movie.watched] 由 StorageService 依据显式状态与观影会话派生；
/// 对剧集，本类额外要求所有分集都已看完才算已看。
class WatchStatus {
  const WatchStatus._();

  /// 判断一部影片是否已看。
  static bool isWatched(Movie movie) {
    if (movie.watched) return true;

    final isSeries = movie.subjectType == MovieSubjectType.tvSeries;
    return isSeries &&
        movie.episodes.isNotEmpty &&
        movie.episodes.every((episode) => episode.watched);
  }

  /// 过滤出尚未观看的影片。
  static List<Movie> unwatchedMovies(Iterable<Movie> movies) =>
      movies.where((movie) => !isWatched(movie)).toList(growable: false);
}
