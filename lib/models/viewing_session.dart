import 'package:random_movie/models/movie.dart';
import 'package:random_movie/services/time_model.dart';

/// 观影时的心情标签。
enum WatchMood {
  none('none', '', null),
  loved('loved', '超爱', '🥰'),
  happy('happy', '愉快', '😄'),
  moved('moved', '感动', '🥹'),
  thrilled('thrilled', '刺激', '😲'),
  chill('chill', '放松', '😌'),
  bored('bored', '无聊', '😴'),
  meh('meh', '一般', '😐');

  final String value;
  final String label;
  final String? emoji;

  const WatchMood(this.value, this.label, this.emoji);

  static WatchMood fromValue(String? value) {
    for (final mood in WatchMood.values) {
      if (mood.value == value) return mood;
    }
    return WatchMood.none;
  }
}

/// 一次观影会话 —— 同一部影片可有多条，记录随时间演变的观影体验。
class ViewingSession {
  final String id;
  final String movieId;
  final DateTime watchedAt;

  /// 当次心情
  final WatchMood mood;

  /// 和谁一起看（自由文本，可空）
  final String watchedWith;

  /// 一句私语 / 短评
  final String note;

  /// 是否为重看
  final bool isRewatch;

  /// 当次评分（0-5，null 表示未评）
  final double? rating;

  final DateTime createdAt;

  /// 观影时刻的 UTC 毫秒。**只用于排序与比较**，与时区无关。
  ///
  /// 与 [watchedAt] 同时写入并持久化；旧数据尚未补齐时为 null，
  /// 读取时由 [effectiveWatchedAtUtcMs] 兜底。
  final int? watchedAtUtcMs;

  /// 观影的**当地日期** `YYYY-MM-DD`，用于日历与年度回顾分组。
  ///
  /// 这是「当天到底算哪一天」的唯一真相：写入时按当时的设备时区算出并落库，
  /// 之后**永不再从时刻反推**。所以用户飞到另一个时区，历史记录仍落在原日期。
  final String? watchedOn;

  /// 排序用：优先用已落库的 UTC 毫秒，旧数据退回按 [watchedAt] 推导。
  int get effectiveWatchedAtUtcMs =>
      watchedAtUtcMs ?? watchedAt.toUtc().millisecondsSinceEpoch;

  /// 分组用：优先用已落库的当地日期，旧数据退回按 [watchedAt] 推导。
  String get effectiveWatchedOn => watchedOn ?? watchedOnOf(watchedAt);

  ViewingSession({
    required this.id,
    required this.movieId,
    required this.watchedAt,
    this.mood = WatchMood.none,
    this.watchedWith = '',
    this.note = '',
    this.isRewatch = false,
    this.rating,
    DateTime? createdAt,
    this.watchedAtUtcMs,
    this.watchedOn,
  }) : createdAt = createdAt ?? DateTime.now();

  ViewingSession copyWith({
    String? id,
    String? movieId,
    DateTime? watchedAt,
    WatchMood? mood,
    String? watchedWith,
    String? note,
    bool? isRewatch,
    double? rating,
    bool clearRating = false,
    DateTime? createdAt,
    int? watchedAtUtcMs,
    String? watchedOn,
  }) {
    final nextWatchedAt = watchedAt ?? this.watchedAt;
    // 改了观影时刻就必须重算派生列，否则排序与日历会和显示对不上。
    final watchedAtChanged = watchedAt != null;
    return ViewingSession(
      id: id ?? this.id,
      movieId: movieId ?? this.movieId,
      watchedAt: nextWatchedAt,
      mood: mood ?? this.mood,
      watchedWith: watchedWith ?? this.watchedWith,
      note: note ?? this.note,
      isRewatch: isRewatch ?? this.isRewatch,
      rating: clearRating ? null : (rating ?? this.rating),
      createdAt: createdAt ?? this.createdAt,
      watchedAtUtcMs: watchedAtChanged
          ? nextWatchedAt.toUtc().millisecondsSinceEpoch
          : (watchedAtUtcMs ?? this.watchedAtUtcMs),
      watchedOn: watchedAtChanged
          ? watchedOnOf(nextWatchedAt)
          : (watchedOn ?? this.watchedOn),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'movieId': movieId,
    'watchedAt': watchedAt.toIso8601String(),
    'mood': mood.value,
    'watchedWith': watchedWith,
    'note': note,
    'isRewatch': isRewatch,
    'rating': rating,
    'createdAt': createdAt.toIso8601String(),
    // 导出仍写 ISO8601（UTC），额外写当地日期；导入时优先读 watchedOn，
    // 这样跨时区导入也能落回原来的那一天。
    'watchedAtUtc': watchedAt.toUtc().toIso8601String(),
    'watchedOn': effectiveWatchedOn,
  };

  factory ViewingSession.fromJson(Map<String, dynamic> json) {
    final watchedAt = json['watchedAt'] != null
        ? DateTime.parse(json['watchedAt'])
        : DateTime.now();
    // 优先用备份里声明的当地日期：换时区导入不该改变「哪天看的」。
    final declaredWatchedOn = json['watchedOn']?.toString();
    final utcMs =
        json['watchedAtUtcMs'] is num
        ? (json['watchedAtUtcMs'] as num).toInt()
        : parseUtcMillis(json['watchedAtUtc']?.toString());
    return ViewingSession(
      id: json['id'] ?? '',
      movieId: json['movieId'] ?? '',
      watchedAt: watchedAt,
      mood: WatchMood.fromValue(json['mood']?.toString()),
      watchedWith: json['watchedWith'] ?? '',
      note: json['note'] ?? '',
      isRewatch: json['isRewatch'] == true,
      rating: (json['rating'] as num?)?.toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      watchedAtUtcMs: utcMs,
      watchedOn:
          (declaredWatchedOn != null && declaredWatchedOn.isNotEmpty)
          ? declaredWatchedOn
          : null,
    );
  }
}

/// 时间线条目：一次观影会话 + 关联影片（用于观影页时间线展示）。
class SessionEntry {
  final ViewingSession session;
  final Movie movie;

  const SessionEntry({required this.session, required this.movie});
}
