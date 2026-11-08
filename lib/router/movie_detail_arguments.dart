// Personal UI edition, 2026-11-08. Apache-2.0.
import 'package:random_movie/models/movie.dart';

/// Optional presentation data; direct detail URLs continue to work without it.
class MovieDetailArguments {
  final Movie movie;
  final String? posterTag;

  const MovieDetailArguments(this.movie, {this.posterTag});
}
