/// 合集类型：手动合集 + 智能虚拟合集。
enum CollectionKind {
  manual('manual'),
  smartGenre('smartGenre'),
  smartDirector('smartDirector'),
  smartDecade('smartDecade'),
  smartRegion('smartRegion');

  final String value;
  const CollectionKind(this.value);

  bool get isSmart => this != CollectionKind.manual;

  static CollectionKind fromValue(String? value) {
    for (final kind in CollectionKind.values) {
      if (kind.value == value) return kind;
    }
    return CollectionKind.manual;
  }
}

/// 合集。手动合集成员存于 collection_members 表；智能合集为虚拟、查询时动态生成。
///
/// [memberCount] / [previewPosters] 为展示用的派生字段，由查询填充。
class MovieCollection {
  final String id;
  final CollectionKind kind;
  final String name;

  /// 图标键，映射到 UI 的 const IconData（见 collectionIcon）。
  final String iconKey;

  final int sortOrder;
  final DateTime createdAt;

  /// 智能合集的过滤值（类型名 / 导演名 / 年代起始年 / 地区）。手动合集为空。
  final String smartValue;

  // ---- 派生展示字段 ----
  final int memberCount;
  final List<String> previewPosters;

  MovieCollection({
    required this.id,
    this.kind = CollectionKind.manual,
    required this.name,
    this.iconKey = 'collections',
    this.sortOrder = 0,
    DateTime? createdAt,
    this.smartValue = '',
    this.memberCount = 0,
    this.previewPosters = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isSmart => kind.isSmart;

  /// 智能合集的可选图标键。
  static const List<String> iconKeys = [
    'collections',
    'favorite',
    'star',
    'bolt',
    'nights_stay',
    'local_movies',
    'theaters',
    'whatshot',
    'mood',
    'auto_awesome',
    'public',
  ];

  MovieCollection copyWith({
    String? id,
    CollectionKind? kind,
    String? name,
    String? iconKey,
    int? sortOrder,
    DateTime? createdAt,
    String? smartValue,
    int? memberCount,
    List<String>? previewPosters,
  }) {
    return MovieCollection(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      smartValue: smartValue ?? this.smartValue,
      memberCount: memberCount ?? this.memberCount,
      previewPosters: previewPosters ?? this.previewPosters,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.value,
    'name': name,
    'iconKey': iconKey,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
    'smartValue': smartValue,
  };

  factory MovieCollection.fromJson(Map<String, dynamic> json) =>
      MovieCollection(
        id: json['id'] ?? '',
        kind: CollectionKind.fromValue(json['kind']?.toString()),
        name: json['name'] ?? '',
        iconKey: json['iconKey'] ?? 'collections',
        sortOrder: json['sortOrder'] is num
            ? (json['sortOrder'] as num).toInt()
            : 0,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
        smartValue: json['smartValue'] ?? '',
      );
}
