import 'package:random_movie/models/movie.dart';
import 'package:random_movie/models/draw_filter.dart';
import 'package:random_movie/services/draw_service.dart';

class DrawFilterOption {
  final String label;
  final DrawFilter removed;
  const DrawFilterOption(this.label, this.removed);
}

List<DrawFilterOption> activeDrawFilters(DrawFilter f) => [
  if (f.maxDurationMinutes != null)
    DrawFilterOption(
      '${f.maxDurationMinutes}分钟内',
      f.copyWith(clearMaxDuration: true),
    ),
  if (f.genres.isNotEmpty) DrawFilterOption('类型', f.copyWith(genres: {})),
  if (f.minYear != null || f.maxYear != null)
    DrawFilterOption('年代', f.copyWith(clearMinYear: true, clearMaxYear: true)),
  if (f.regions.isNotEmpty) DrawFilterOption('地区', f.copyWith(regions: {})),
  if (f.minRating != null || f.maxRating != null)
    DrawFilterOption(
      '评分',
      f.copyWith(clearMinRating: true, clearMaxRating: true),
    ),
  if (f.director.trim().isNotEmpty)
    DrawFilterOption('导演', f.copyWith(director: '')),
  if (f.tagIds.isNotEmpty) DrawFilterOption('标签', f.copyWith(tagIds: {})),
];

class DrawCandidateReport {
  final int count;
  final List<String> explanations;
  DrawCandidateReport(this.count, this.explanations);

  factory DrawCandidateReport.analyze(
    List<Movie> movies,
    DrawFilter filter, {
    Set<String>? allowedByTags,
  }) {
    final count = DrawService.smartFilter(
      movies,
      filter,
      allowedMovieIds: allowedByTags,
    ).length;
    final explanations = <String>[];
    if (count == 0 && movies.isNotEmpty) {
      for (final option in activeDrawFilters(filter)) {
        final recovered = DrawService.smartFilter(
          movies,
          option.removed,
          allowedMovieIds: option.removed.tagIds.isEmpty ? null : allowedByTags,
        ).length;
        if (recovered > 0) explanations.add('取消${option.label}可选 $recovered 部');
      }
      if (explanations.isEmpty) explanations.add('多项条件组合后没有候选，可逐项取消或清空筛选');
      if (filter.maxDurationMinutes != null &&
          movies.any((m) => m.durationMinutes == null)) {
        explanations.add('缺少时长资料的影片不会进入限时候选');
      }
    }
    return DrawCandidateReport(count, explanations);
  }
}
