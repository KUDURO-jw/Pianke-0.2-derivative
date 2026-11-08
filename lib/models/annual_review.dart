import 'package:random_movie/models/movie.dart';
import 'package:random_movie/models/viewing_session.dart';

/// Counts viewing sessions separately from distinct titles. No duration estimates.
class AnnualReview {
  final int year;
  final int sessionCount;
  final int movieCount;
  final int seriesCount;
  final int activeDays;
  final int rewatchCount;
  final List<MapEntry<String, int>> genres;
  final List<int> ratingBins;
  final List<Movie> highlights;

  AnnualReview._(
    this.year,
    this.sessionCount,
    this.movieCount,
    this.seriesCount,
    this.activeDays,
    this.rewatchCount,
    this.genres,
    this.ratingBins,
    this.highlights,
  );

  factory AnnualReview.build(
    int year,
    List<Movie> movies,
    List<ViewingSession> sessions,
  ) {
    final byId = {for (final movie in movies) movie.id: movie};
    final valid = sessions
        .where(
          (s) =>
              s.watchedAt.toLocal().year == year && byId.containsKey(s.movieId),
        )
        .toList();
    final unique = valid
        .map((s) => s.movieId)
        .toSet()
        .map((id) => byId[id]!)
        .toList();
    final genres = <String, int>{};
    for (final movie in unique) {
      for (final genre in movie.genre.toSet()) {
        if (genre.trim().isNotEmpty) {
          genres.update(genre, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }
    final orderedGenres = genres.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final bins = List.filled(5, 0);
    final ratings = <String, double>{};
    for (final session in valid) {
      final rating = session.rating;
      if (rating == null || !rating.isFinite || rating < 0 || rating > 5) {
        continue;
      }
      bins[(rating.ceil() - 1).clamp(0, 4)]++;
      if (rating > (ratings[session.movieId] ?? -1)) {
        ratings[session.movieId] = rating;
      }
    }
    final ranked = ratings.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : byId[a.key]!.title.compareTo(byId[b.key]!.title);
      });
    return AnnualReview._(
      year,
      valid.length,
      unique.where((m) => m.subjectType == MovieSubjectType.movie).length,
      unique.where((m) => m.subjectType == MovieSubjectType.tvSeries).length,
      valid
          .map((s) {
            final d = s.watchedAt.toLocal();
            return DateTime(d.year, d.month, d.day);
          })
          .toSet()
          .length,
      valid.where((s) => s.isRewatch).length,
      orderedGenres.take(3).toList(),
      bins,
      ranked.take(5).map((r) => byId[r.key]!).toList(),
    );
  }
}
