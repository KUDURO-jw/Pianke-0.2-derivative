import 'package:random_movie/models/movie.dart';

/// Single model-level watch-state predicate shared by library and draw logic.
/// StorageService derives Movie.watched from both persisted flags and sessions.
class WatchStatus {
  const WatchStatus._();

  static bool isWatched(Movie movie) {
    if (movie.watched) return true;

    final isSeries = movie.subjectType == MovieSubjectType.tvSeries;
    return isSeries &&
        movie.episodes.isNotEmpty &&
        movie.episodes.every((episode) => episode.watched);
  }

  static List<Movie> unwatchedMovies(Iterable<Movie> movies) =>
      movies.where((movie) => !isWatched(movie)).toList(growable: false);
}
