import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/draw_service.dart';

Movie _movie(String id, {bool watched = false}) =>
    Movie(id: id, title: id, watched: watched);

void main() {
  test('all four draw modes are available', () {
    expect(DrawMode.values, hasLength(4));
    expect(
      DrawMode.values,
      containsAll(<DrawMode>[
        DrawMode.pureRandom,
        DrawMode.fair,
        DrawMode.priorityUnwatched,
        DrawMode.threePickOne,
      ]),
    );
  });

  test('threePickOne draws unique movies from the candidate pool', () {
    final candidates = [_movie('a'), _movie('b'), _movie('c'), _movie('d')];

    final picked = DrawService.threePickOne(candidates);

    expect(picked, hasLength(3));
    expect(picked.map((movie) => movie.id).toSet(), hasLength(3));
    expect(
      picked.every(
        (movie) => candidates.any((candidate) => candidate.id == movie.id),
      ),
      isTrue,
    );
  });

  test('smartFilter applies the selected movie id scope', () {
    final movies = [_movie('a'), _movie('b'), _movie('c')];

    final filtered = DrawService.smartFilter(
      movies,
      DrawFilter.none,
      allowedMovieIds: {'a', 'c'},
    );

    expect(filtered.map((movie) => movie.id), ['a', 'c']);
  });
}
