import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/draw_selection.dart';
import 'package:random_movie/services/watch_status.dart';

Movie _movie(String id, {bool watched = false}) =>
    Movie(id: id, title: id, watched: watched);

void main() {
  test('restrictToScope normalizes and de-duplicates ids', () {
    final result = DrawSelection.restrictToScope(
      [' a ', 'b', 'a', '', 'outside'],
      scope: ['a', 'b'],
    );

    expect(result, ['a', 'b']);
  });

  test('restrictToScope keeps all ids when no scope is provided', () {
    final result = DrawSelection.restrictToScope(['a', ' a ', 'b']);

    expect(result, ['a', 'b']);
  });

  test('selection count is based on the scoped pool, not the page size', () {
    final allIds = List.generate(62, (index) => 'movie_$index');
    final unwatchedIds = allIds.take(48);

    final selected = DrawSelection.restrictToScope(unwatchedIds, scope: allIds);

    expect(selected, hasLength(48));
  });

  test('select all replaces the current mode with the complete scope', () {
    final state = DrawSelectionState();
    final allIds = List.generate(62, (index) => 'movie_$index');
    state.replace(
      DrawMode.pureRandom,
      DrawSelection.selectAll(allIds),
      scope: allIds,
    );

    expect(state.selectedIds(DrawMode.pureRandom), allIds.toSet());
    expect(state.count(DrawMode.pureRandom), 62);
  });

  test('select unwatched keeps watched ids out of the selection', () {
    final state = DrawSelectionState();
    final movies = [_movie('unwatched_1'), _movie('watched_1', watched: true)];
    state.replace(
      DrawMode.priorityUnwatched,
      DrawSelection.selectUnwatched(
        WatchStatus.unwatchedMovies(movies).map((movie) => movie.id),
        scope: movies.map((movie) => movie.id),
      ),
    );

    expect(state.selectedIds(DrawMode.priorityUnwatched), {'unwatched_1'});
  });

  test('all four draw modes keep independent selections', () {
    final state = DrawSelectionState();
    for (var index = 0; index < DrawMode.values.length; index++) {
      state.replace(DrawMode.values[index], ['movie_$index']);
    }

    for (var index = 0; index < DrawMode.values.length; index++) {
      expect(state.selectedIds(DrawMode.values[index]), {'movie_$index'});
    }
  });

  test('watched movies are excluded by the shared watch predicate', () {
    final movies = [_movie('watched', watched: true), _movie('unwatched')];

    expect(WatchStatus.unwatchedMovies(movies).map((movie) => movie.id), [
      'unwatched',
    ]);
  });

  test(
    'a completed series is watched even when its aggregate flag is stale',
    () {
      final movie = Movie(
        id: 'series',
        title: 'series',
        subjectType: MovieSubjectType.tvSeries,
        episodes: const [
          MovieEpisode(number: 1, label: '1', doubanUrl: '', watched: true),
          MovieEpisode(number: 2, label: '2', doubanUrl: '', watched: true),
        ],
      );

      expect(WatchStatus.isWatched(movie), isTrue);
      expect(WatchStatus.unwatchedMovies([movie]), isEmpty);
    },
  );

  test(
    'no unwatched movies produces zero selected while total stays intact',
    () {
      final allIds = ['a', 'b', 'c'];
      final state = DrawSelectionState();
      state.replace(
        DrawMode.threePickOne,
        DrawSelection.selectUnwatched(const [], scope: allIds),
      );

      expect(state.count(DrawMode.threePickOne), 0);
      expect(allIds, hasLength(3));
    },
  );
}
