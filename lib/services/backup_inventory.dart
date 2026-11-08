/// Read-only inventory used before any import or cloud replacement is applied.
class BackupInventory {
  final int movies;
  final int sessions;
  final int draws;
  final int collections;
  final int tags;
  const BackupInventory({
    required this.movies,
    required this.sessions,
    required this.draws,
    required this.collections,
    required this.tags,
  });

  factory BackupInventory.fromPayload(Map<String, dynamic> payload) {
    int count(String key) =>
        payload[key] is List ? (payload[key] as List).length : 0;
    return BackupInventory(
      movies: count('movies'),
      sessions: count('viewingSessions'),
      draws: count('drawRecords'),
      collections: count('collections'),
      tags: count('tags'),
    );
  }

  String get description =>
      '$movies 部影片 · $sessions 条观影记录 · $draws 条抽片记录\n$collections 个合集 · $tags 个标签';
}
