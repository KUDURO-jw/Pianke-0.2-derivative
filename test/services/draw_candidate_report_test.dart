import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/draw_candidate_report.dart';

void main() {
  final films = [
    Movie(id: 'a', title: '短片', genre: ['剧情'], durationMinutes: 30),
    Movie(id: 'b', title: '长片', genre: ['喜剧'], durationMinutes: 150),
    Movie(id: 'c', title: '时长未知'),
  ];
  test('counts exactly the filtered pool and explains unknown durations', () {
    expect(
      DrawCandidateReport.analyze(
        films,
        const DrawFilter(maxDurationMinutes: 60),
      ).count,
      1,
    );
    final empty = DrawCandidateReport.analyze(
      films,
      const DrawFilter(maxDurationMinutes: 20),
    );
    expect(empty.count, 0);
    expect(empty.explanations.join(), contains('取消20分钟内可选 3 部'));
    expect(empty.explanations.join(), contains('缺少时长'));
  });
  test('can remove only the tag filter and retains other constraints', () {
    final filter = DrawFilter(maxDurationMinutes: 60, tagIds: {'tag'});
    final empty = DrawCandidateReport.analyze(
      films,
      filter,
      allowedByTags: {'b'},
    );
    expect(empty.count, 0);
    expect(empty.explanations, contains('取消标签可选 1 部'));
    final removed = activeDrawFilters(
      filter,
    ).firstWhere((f) => f.label == '标签').removed;
    expect(removed.tagIds, isEmpty);
    expect(removed.maxDurationMinutes, 60);
  });
  test('explains combinations when no single removal restores candidates', () {
    final empty = DrawCandidateReport.analyze(
      films,
      const DrawFilter(maxDurationMinutes: 10, genres: {'动画'}),
    );
    expect(empty.explanations.first, contains('多项条件组合'));
  });
}
