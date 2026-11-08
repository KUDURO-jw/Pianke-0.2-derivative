import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/annual_review.dart';
import 'package:random_movie/models/models.dart';

void main() {
  test(
    'annual counts distinguish sessions, titles, genres and incomplete series',
    () {
      final movies = [
        Movie(id: 'film', title: '电影', genre: ['剧情', '剧情']),
        Movie(
          id: 'tv',
          title: '剧集',
          genre: ['剧情'],
          subjectType: MovieSubjectType.tvSeries,
        ),
      ];
      final review = AnnualReview.build(2026, movies, [
        ViewingSession(
          id: '1',
          movieId: 'film',
          watchedAt: DateTime(2026, 1, 1),
          rating: 4.5,
        ),
        ViewingSession(
          id: '2',
          movieId: 'film',
          watchedAt: DateTime(2026, 1, 1),
          rating: 0,
          isRewatch: true,
        ),
        ViewingSession(
          id: '3',
          movieId: 'tv',
          watchedAt: DateTime(2026, 2, 2),
          rating: 3,
        ),
        ViewingSession(
          id: '4',
          movieId: 'missing',
          watchedAt: DateTime(2026, 2, 2),
          rating: 5,
        ),
        ViewingSession(
          id: '5',
          movieId: 'tv',
          watchedAt: DateTime(2025, 12, 31),
          rating: 5,
        ),
      ]);
      expect(review.sessionCount, 3);
      expect(review.movieCount, 1);
      expect(review.seriesCount, 1);
      expect(review.activeDays, 2);
      expect(review.rewatchCount, 1);
      expect(review.genres.single.value, 2);
      expect(review.ratingBins, [1, 0, 1, 0, 1]);
      expect(review.highlights.map((m) => m.id), ['film', 'tv']);
    },
  );

  test('empty years and missing ratings do not invent scores or titles', () {
    final film = Movie(id: 'film', title: '电影', userRating: 5);
    final session = ViewingSession(
      id: '1',
      movieId: 'film',
      watchedAt: DateTime(2024, 2, 29),
    );
    final review = AnnualReview.build(2024, [film], [session]);
    expect(review.ratingBins.every((v) => v == 0), isTrue);
    expect(review.highlights, isEmpty);
    expect(AnnualReview.build(2026, [film], [session]).sessionCount, 0);
  });
}
