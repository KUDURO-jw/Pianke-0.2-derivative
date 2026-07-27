enum MovieSubjectType {
  movie('movie'),
  tvSeries('tvSeries');

  final String value;
  const MovieSubjectType(this.value);

  static MovieSubjectType fromValue(String? value) {
    switch (value) {
      case 'tvSeries':
        return MovieSubjectType.tvSeries;
      case 'movie':
      default:
        return MovieSubjectType.movie;
    }
  }
}

class MovieEpisode {
  final int number;
  final String label;
  final String doubanUrl;
  final bool watched;

  const MovieEpisode({
    required this.number,
    required this.label,
    required this.doubanUrl,
    this.watched = false,
  });

  Map<String, dynamic> toJson() => {
    'number': number,
    'label': label,
    'doubanUrl': doubanUrl,
    'watched': watched,
  };

  factory MovieEpisode.fromJson(Map<String, dynamic> json) {
    final watchedRaw = json['watched'];
    final watchedValue = watchedRaw is bool
        ? watchedRaw
        : watchedRaw == 1 ||
              watchedRaw == '1' ||
              watchedRaw?.toString().toLowerCase() == 'true';

    return MovieEpisode(
      number: json['number'] is int
          ? json['number'] as int
          : int.tryParse(json['number']?.toString() ?? '') ?? 0,
      label: json['label'] ?? '',
      doubanUrl: json['doubanUrl'] ?? '',
      watched: watchedValue,
    );
  }

  MovieEpisode copyWith({
    int? number,
    String? label,
    String? doubanUrl,
    bool? watched,
  }) {
    return MovieEpisode(
      number: number ?? this.number,
      label: label ?? this.label,
      doubanUrl: doubanUrl ?? this.doubanUrl,
      watched: watched ?? this.watched,
    );
  }
}

/// 影片模型
class Movie {
  final String id;
  final String title;
  final String year;
  final String director;
  final String author;
  final String cast;
  final double rating;
  final List<String> genre;
  final String region;
  final String summary;
  final String publishedAt;
  final String durationText;

  /// 结构化片长（分钟）。构造时若未显式提供，会自动从 [durationText] 解析。
  /// 剧集类型表示单集时长。
  final int? durationMinutes;
  final String poster;
  final String doubanUrl;
  final MovieSubjectType subjectType;
  final List<MovieEpisode> episodes;
  final bool watched;
  final DateTime? watchedAt;
  final double? userRating;
  final String? userReview;
  final DateTime createdAt;

  Movie({
    required this.id,
    required this.title,
    this.year = '',
    this.director = '',
    this.author = '',
    this.cast = '',
    this.rating = 0,
    this.genre = const [],
    this.region = '',
    this.summary = '',
    this.publishedAt = '',
    this.durationText = '',
    int? durationMinutes,
    this.poster = '',
    this.doubanUrl = '',
    this.subjectType = MovieSubjectType.movie,
    this.episodes = const [],
    this.watched = false,
    this.watchedAt,
    this.userRating,
    this.userReview,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       durationMinutes = durationMinutes ?? parseDurationMinutes(durationText);

  /// 从形如「124分钟」「片长: 124分钟」「每集45分钟」或 ISO 8601（`PT2H4M`/
  /// `PT124M`）的文本中提取分钟数。解析失败返回 null。
  static int? parseDurationMinutes(String? text) {
    if (text == null || text.isEmpty) return null;

    // ISO 8601 时长：PT[h]H[m]M
    final iso = RegExp(
      r'PT(?:(\d+)H)?(?:(\d+)M)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (iso != null && (iso.group(1) != null || iso.group(2) != null)) {
      final hours = int.tryParse(iso.group(1) ?? '0') ?? 0;
      final minutes = int.tryParse(iso.group(2) ?? '0') ?? 0;
      final total = hours * 60 + minutes;
      if (total > 0) return total;
    }

    final match = RegExp(r'(\d+)').firstMatch(text);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// 获取代理后的海报URL
  String get proxiedPosterUrl {
    if (poster.isEmpty) return '';
    return poster;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'year': year,
    'director': director,
    'author': author,
    'cast': cast,
    'rating': rating,
    'genre': genre,
    'region': region,
    'summary': summary,
    'publishedAt': publishedAt,
    'durationText': durationText,
    'durationMinutes': durationMinutes,
    'poster': poster,
    'doubanUrl': doubanUrl,
    'subjectType': subjectType.value,
    'episodes': episodes.map((e) => e.toJson()).toList(),
    'watched': watched,
    'watchedAt': watchedAt?.toIso8601String(),
    'userRating': userRating,
    'userReview': userReview,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Movie.fromJson(Map<String, dynamic> json) => Movie(
    id: json['id'] ?? json['_id'] ?? '',
    title: json['title'] ?? '',
    year: json['year'] ?? '',
    director: json['director'] ?? '',
    author: json['author'] ?? '',
    cast: json['cast'] ?? '',
    rating: (json['rating'] ?? 0).toDouble(),
    genre: List<String>.from(json['genre'] ?? []),
    region: json['region'] ?? '',
    summary: json['summary'] ?? '',
    publishedAt: json['publishedAt'] ?? '',
    durationText: json['durationText'] ?? '',
    durationMinutes: json['durationMinutes'] is num
        ? (json['durationMinutes'] as num).toInt()
        : null,
    poster: json['poster'] ?? '',
    doubanUrl: json['doubanUrl'] ?? '',
    subjectType: MovieSubjectType.fromValue(json['subjectType']?.toString()),
    episodes: (json['episodes'] is List)
        ? (json['episodes'] as List)
              .whereType<Map>()
              .map((e) => MovieEpisode.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : const [],
    watched: json['watched'] ?? false,
    watchedAt: json['watchedAt'] != null
        ? DateTime.parse(json['watchedAt'])
        : null,
    userRating: json['userRating']?.toDouble(),
    userReview: json['userReview'],
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'])
        : DateTime.now(),
  );

  Movie copyWith({
    String? id,
    String? title,
    String? year,
    String? director,
    String? author,
    String? cast,
    double? rating,
    List<String>? genre,
    String? region,
    String? summary,
    String? publishedAt,
    String? durationText,
    int? durationMinutes,
    bool clearDurationMinutes = false,
    String? poster,
    String? doubanUrl,
    MovieSubjectType? subjectType,
    List<MovieEpisode>? episodes,
    bool? watched,
    DateTime? watchedAt,
    bool clearWatchedAt = false,
    double? userRating,
    bool clearUserRating = false,
    String? userReview,
    bool clearUserReview = false,
    DateTime? createdAt,
  }) {
    return Movie(
      id: id ?? this.id,
      title: title ?? this.title,
      year: year ?? this.year,
      director: director ?? this.director,
      author: author ?? this.author,
      cast: cast ?? this.cast,
      rating: rating ?? this.rating,
      genre: genre ?? this.genre,
      region: region ?? this.region,
      summary: summary ?? this.summary,
      publishedAt: publishedAt ?? this.publishedAt,
      durationText: durationText ?? this.durationText,
      durationMinutes: clearDurationMinutes
          ? null
          : (durationMinutes ?? this.durationMinutes),
      poster: poster ?? this.poster,
      doubanUrl: doubanUrl ?? this.doubanUrl,
      subjectType: subjectType ?? this.subjectType,
      episodes: episodes ?? this.episodes,
      watched: watched ?? this.watched,
      watchedAt: clearWatchedAt ? null : (watchedAt ?? this.watchedAt),
      userRating: clearUserRating ? null : (userRating ?? this.userRating),
      userReview: clearUserReview ? null : (userReview ?? this.userReview),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Movie(id: $id, title: $title, year: $year)';
}
