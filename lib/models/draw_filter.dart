/// 抽片决策模式。
enum DrawMode {
  /// 纯随机：所有候选等概率
  pureRandom('pureRandom', '纯随机', '所有候选等概率，听天由命'),

  /// 公平模式：避开最近抽过/看过的
  fair('fair', '公平模式', '最近抽过、看过的降权，雨露均沾'),

  /// 优先未看：没看过的权重更高
  priorityUnwatched('priorityUnwatched', '优先未看', '没看过的优先抽中，消化片单'),

  /// 抽 3 选 1：一次抽 3 部让你挑
  threePickOne('threePickOne', '三选一', '一次抽 3 部，自己挑一部');

  final String value;
  final String label;
  final String description;

  const DrawMode(this.value, this.label, this.description);

  static DrawMode fromValue(String? value) {
    for (final mode in DrawMode.values) {
      if (mode.value == value) return mode;
    }
    return DrawMode.pureRandom;
  }
}

/// 抽片筛选条件 —— 在抽取前缩小候选池。
///
/// 所有字段为空/null 表示该维度不限制。值对象，用 [copyWith] 派生新实例。
class DrawFilter {
  /// 时长预算上限（分钟）。null 表示不限。仅对有 durationMinutes 的影片生效。
  final int? maxDurationMinutes;

  /// 类型筛选（命中任一即通过）。空表示不限。
  final Set<String> genres;

  /// 年代区间起（含），如 1990。null 表示不限。
  final int? minYear;

  /// 年代区间止（含），如 1999。null 表示不限。
  final int? maxYear;

  /// 地区筛选（命中任一即通过，子串匹配）。空表示不限。
  final Set<String> regions;

  /// 最低评分（含）。null 表示不限。
  final double? minRating;

  /// 最高评分（含）。null 表示不限。
  final double? maxRating;

  /// 导演关键词（子串匹配，忽略大小写）。空表示不限。
  final String director;

  /// 标签 id 筛选（命中任一即通过）。空表示不限。
  /// 注：标签为影片级关联，过滤在调用方解析为影片 id 集合后注入。
  final Set<String> tagIds;

  const DrawFilter({
    this.maxDurationMinutes,
    this.genres = const {},
    this.minYear,
    this.maxYear,
    this.regions = const {},
    this.minRating,
    this.maxRating,
    this.director = '',
    this.tagIds = const {},
  });

  /// 无任何限制的空筛选。
  static const DrawFilter none = DrawFilter();

  /// 是否设置了任意筛选条件。
  bool get isActive =>
      maxDurationMinutes != null ||
      genres.isNotEmpty ||
      minYear != null ||
      maxYear != null ||
      regions.isNotEmpty ||
      minRating != null ||
      maxRating != null ||
      director.trim().isNotEmpty ||
      tagIds.isNotEmpty;

  /// 生效的筛选维度数量，用于在 UI 上显示徽标。
  int get activeCount {
    var count = 0;
    if (maxDurationMinutes != null) count++;
    if (genres.isNotEmpty) count++;
    if (minYear != null || maxYear != null) count++;
    if (regions.isNotEmpty) count++;
    if (minRating != null || maxRating != null) count++;
    if (director.trim().isNotEmpty) count++;
    if (tagIds.isNotEmpty) count++;
    return count;
  }

  DrawFilter copyWith({
    int? maxDurationMinutes,
    bool clearMaxDuration = false,
    Set<String>? genres,
    int? minYear,
    bool clearMinYear = false,
    int? maxYear,
    bool clearMaxYear = false,
    Set<String>? regions,
    double? minRating,
    bool clearMinRating = false,
    double? maxRating,
    bool clearMaxRating = false,
    String? director,
    Set<String>? tagIds,
  }) {
    return DrawFilter(
      maxDurationMinutes: clearMaxDuration
          ? null
          : (maxDurationMinutes ?? this.maxDurationMinutes),
      genres: genres ?? this.genres,
      minYear: clearMinYear ? null : (minYear ?? this.minYear),
      maxYear: clearMaxYear ? null : (maxYear ?? this.maxYear),
      regions: regions ?? this.regions,
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
      maxRating: clearMaxRating ? null : (maxRating ?? this.maxRating),
      director: director ?? this.director,
      tagIds: tagIds ?? this.tagIds,
    );
  }
}
