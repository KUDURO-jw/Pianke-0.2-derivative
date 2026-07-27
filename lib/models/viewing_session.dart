import 'package:random_movie/models/movie.dart';

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

/// 一次观影会话 —— 同一部电影可有多条，记录随时间演变的观影体验。
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
  }) {
    return ViewingSession(
      id: id ?? this.id,
      movieId: movieId ?? this.movieId,
      watchedAt: watchedAt ?? this.watchedAt,
      mood: mood ?? this.mood,
      watchedWith: watchedWith ?? this.watchedWith,
      note: note ?? this.note,
      isRewatch: isRewatch ?? this.isRewatch,
      rating: clearRating ? null : (rating ?? this.rating),
      createdAt: createdAt ?? this.createdAt,
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
  };

  factory ViewingSession.fromJson(Map<String, dynamic> json) => ViewingSession(
    id: json['id'] ?? '',
    movieId: json['movieId'] ?? '',
    watchedAt: json['watchedAt'] != null
        ? DateTime.parse(json['watchedAt'])
        : DateTime.now(),
    mood: WatchMood.fromValue(json['mood']?.toString()),
    watchedWith: json['watchedWith'] ?? '',
    note: json['note'] ?? '',
    isRewatch: json['isRewatch'] == true,
    rating: (json['rating'] as num?)?.toDouble(),
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'])
        : DateTime.now(),
  );
}

/// 时间线条目：一次观影会话 + 关联影片（用于观影页时间线展示）。
class SessionEntry {
  final ViewingSession session;
  final Movie movie;

  const SessionEntry({required this.session, required this.movie});
}
