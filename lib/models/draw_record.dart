/// 抽片结果的处理状态。
///
/// - [pending]：刚抽出，用户尚未决定
/// - [accepted]：「就看这个」，用户采纳了结果
/// - [skipped]：「跳过」，用户放弃了结果（公平模式下次降权）
enum DrawOutcome {
  pending('pending'),
  accepted('accepted'),
  skipped('skipped');

  final String value;
  const DrawOutcome(this.value);

  static DrawOutcome fromValue(String? value) {
    switch (value) {
      case 'accepted':
        return DrawOutcome.accepted;
      case 'skipped':
        return DrawOutcome.skipped;
      case 'pending':
      default:
        return DrawOutcome.pending;
    }
  }
}

/// A single draw record, stored locally
class DrawRecord {
  final String id;
  final String movieId;
  final String movieTitle;
  final String moviePoster;
  final int seed;
  final int candidateCount;
  final DrawOutcome outcome;
  final DateTime drawnAt;

  DrawRecord({
    required this.id,
    required this.movieId,
    required this.movieTitle,
    required this.moviePoster,
    required this.seed,
    required this.candidateCount,
    this.outcome = DrawOutcome.pending,
    required this.drawnAt,
  });

  DrawRecord copyWith({
    String? id,
    String? movieId,
    String? movieTitle,
    String? moviePoster,
    int? seed,
    int? candidateCount,
    DrawOutcome? outcome,
    DateTime? drawnAt,
  }) {
    return DrawRecord(
      id: id ?? this.id,
      movieId: movieId ?? this.movieId,
      movieTitle: movieTitle ?? this.movieTitle,
      moviePoster: moviePoster ?? this.moviePoster,
      seed: seed ?? this.seed,
      candidateCount: candidateCount ?? this.candidateCount,
      outcome: outcome ?? this.outcome,
      drawnAt: drawnAt ?? this.drawnAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'movieId': movieId,
    'movieTitle': movieTitle,
    'moviePoster': moviePoster,
    'seed': seed,
    'candidateCount': candidateCount,
    'outcome': outcome.value,
    'drawnAt': drawnAt.toIso8601String(),
  };

  factory DrawRecord.fromJson(Map<String, dynamic> json) => DrawRecord(
    id: json['id'] ?? '',
    movieId: json['movieId'] ?? '',
    movieTitle: json['movieTitle'] ?? '',
    moviePoster: json['moviePoster'] ?? '',
    seed: json['seed'] ?? 0,
    candidateCount: json['candidateCount'] ?? 0,
    outcome: DrawOutcome.fromValue(json['outcome']?.toString()),
    drawnAt: json['drawnAt'] != null
        ? DateTime.parse(json['drawnAt'])
        : DateTime.now(),
  );
}
