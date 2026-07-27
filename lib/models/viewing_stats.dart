/// 观影统计快照，用于观影页顶部仪表盘。
class ViewingStats {
  /// 本月观影会话数
  final int monthlyCount;

  /// 总观影会话数
  final int totalCount;

  /// 类型分布（类型名 -> 次数），按次数倒序
  final List<MapEntry<String, int>> genreDistribution;

  /// 我打过的最高分（null 表示尚无评分）
  final double? highestRating;

  /// 当前连续观影天数
  final int streakDays;

  const ViewingStats({
    this.monthlyCount = 0,
    this.totalCount = 0,
    this.genreDistribution = const [],
    this.highestRating,
    this.streakDays = 0,
  });

  bool get isEmpty => totalCount == 0;
}
