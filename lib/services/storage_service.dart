// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random, min, max, pow;

import 'package:path/path.dart' as path;
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/hlc.dart';
import 'package:random_movie/services/time_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// 把用户输入变成 SQL `LIKE ... ESCAPE '\'` 可以安全使用的文本：
/// `%`、`_` 和 `\` 都当作普通字符，而不是通配符。
String escapeSqlLike(String input) => input
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');

/// 本机数据库被更新版本的片刻创建过。
///
/// 典型场景：用户装回了旧版 APK。此时旧代码不认识新表结构，继续打开只会
/// 在写入时损坏数据，所以这里直接停下，并把「需要装回新版本」讲清楚。
/// 界面应当显示不带「重试」按钮的说明页——重试永远不会成功。
class DatabaseTooNewException implements Exception {
  /// 本机数据库文件里的实际版本（由更新版本写入）。
  final int fileVersion;

  /// 当前安装的片刻所期望的版本。
  final int appVersion;

  const DatabaseTooNewException(this.fileVersion, this.appVersion);

  String get message =>
      '这份数据由更新版本创建（数据库 v$fileVersion），'
      '请安装不低于该版本的片刻后再打开';

  @override
  String toString() => message;
}

/// 覆盖本地数据前发现本地已经变了。
///
/// 抛出它意味着「差点覆盖掉用户刚存的内容」，属于保护性失败：
/// 数据库保持原样，调用方应提示用户稍后重试，而不是重试覆盖。
class StaleLocalDataException implements Exception {
  const StaleLocalDataException();

  String get message => '本地数据刚刚发生变化，已停止覆盖，请稍后重试';

  @override
  String toString() => message;
}

/// 备份时一次性读出的整库快照。四张表的行来自同一个事务视图，彼此自洽。
class BackupBundle {
  final List<Movie> movies;
  final List<DrawRecord> drawRecords;
  final List<ViewingSession> sessions;
  final Map<String, List<Map<String, Object?>>> collectionsAndTags;

  const BackupBundle({
    required this.movies,
    required this.drawRecords,
    required this.sessions,
    required this.collectionsAndTags,
  });
}

/// 本地存储服务
class StorageService {
  static const String _userIdKey = 'movie_app_user_id';
  static const String _userNameKey = 'movie_app_user_name';
  static const String _legacyMoviesKey = 'movie_app_local_movies';
  static const String _legacyDrawHistoryKey = 'movie_app_draw_history';
  static const String _migrationFlagKey = 'movie_app_storage_migrated_v2';
  static const String _themeModeKey = 'movie_app_theme_mode';
  static const String _databaseName = 'random_movie.db';
  static const int _databaseVersion = 9;

  /// 当前数据库结构版本。测试用它构造旧版夹具，避免另抄一份数字。
  static const int databaseVersionForTest = _databaseVersion;

  static const int _maxDrawHistory = 100;
  static const String _moviesTable = 'movies';
  static const String _drawRecordsTable = 'draw_records';
  static const String _viewingSessionsTable = 'viewing_sessions';
  static const String _collectionsTable = 'collections';
  static const String _collectionMembersTable = 'collection_members';
  static const String _tagsTable = 'tags';
  static const String _movieTagsTable = 'movie_tags';

  /// 「是否已看」的**唯一**判定表达式。
  ///
  /// 这是 T4 阶段 A 的核心：此前多处各自手写 `watched = 1 OR EXISTS(...)`，
  /// 一处改动没跟上就会让列表、计数、抽片候选给出不同答案。现在只有这一份。
  ///
  /// 三个来源依次是：
  /// 1. 显式 `watched = 1`；
  /// 2. 存在未删除的观影会话；
  /// 3. 剧集的分集全部看完（历史数据里存在 `watched = 0` 但分集已追完的行）。
  ///
  /// 第 3 条与 Dart 侧 [WatchStatus] 的剧集规则一一对应，
  /// 两边对同一批数据必须给出相同答案（由 watch_state_view_test 守护）。
  static const String _movieWatchedPredicate =
      '(m.watched = 1 '
      'OR EXISTS(SELECT 1 FROM $_viewingSessionsTable vs '
      'WHERE vs.movie_id = m.id AND vs.deleted_at IS NULL) '
      'OR $_seriesCompletedPredicate)';

  /// 剧集「全部分集已看完」的 SQL 判定。
  ///
  /// `episodes_json` 是 `[{"number":1,"watched":true}, ...]` 形式。
  /// 判断条件：是剧集、有分集、且**不存在**任何 `"watched":false`。
  ///
  /// 用一个简单的字符串匹配（而不是 json_each）：Android 7 的系统 SQLite
  /// 未必编译了 JSON1 扩展，而 `LIKE` 到处都能用。
  static const String _seriesCompletedPredicate =
      "(m.subject_type = 'tvSeries' "
      "AND m.episodes_json <> '[]' "
      "AND m.episodes_json NOT LIKE '%\"watched\":false%' "
      "AND m.episodes_json NOT LIKE '%\"watched\": false%')";

  /// 派生字段：影片是否看过（显式状态或存在观影会话）
  static const String _derivedWatchedExpr =
      '$_movieWatchedPredicate AS derived_watched';

  /// 派生字段：最近一次观影时间，兼容没有会话的显式已看状态。
  static const String _derivedWatchedAtExpr =
      'COALESCE((SELECT MAX(vs.watched_at) FROM $_viewingSessionsTable vs '
      'WHERE vs.movie_id = m.id AND vs.deleted_at IS NULL), '
      'm.watched_at) AS derived_watched_at';

  /// 统一视图：所有影片查询都读它，而不是各写一遍子查询。
  ///
  /// T4 阶段 A。视图把「已看」与「最近观影时间」收进一处，查询侧只剩
  /// `FROM v_movie_state m`。已在多个版本上验证过视图与直接查询结果一致。
  static const String _movieStateView = 'v_movie_state';

  static const String _createMovieStateView = '''
    CREATE VIEW IF NOT EXISTS $_movieStateView AS
    SELECT m.*,
      $_derivedWatchedExpr,
      $_derivedWatchedAtExpr
    FROM $_moviesTable m
  ''';

  late SharedPreferences _prefs;
  late Database _db;
  bool _initialized = false;

  /// 记录级版本时钟。所有写入路径都必须从这里取时间戳。
  ///
  /// 懒初始化：`init()` 里已经有 _prefs 了，但为测试构造的实例可能还没走到。
  HlcClock? _clock;
  HlcClock get _hlc => _clock ??= HlcClock(
    deviceId: _prefs.getString(_deviceIdKey) ?? 'unknown',
  );

  static const String _deviceIdKey = 'pianke_device_id';

  /// 给「将要写库的一行」打上版本戳。
  ///
  /// 所有 `insert` / `update` 都必须经过它，否则这一行在合并时会被当成
  /// 「最旧」而永远输给另一台设备——正是 T3 要消除的问题。
  Map<String, Object?> _stamp(Map<String, Object?> row) => {
    ...row,
    'updated_at': _hlc.now().encode(),
    'deleted_at': row['deleted_at'],
  };

  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;

  /// 仅供测试：返回一个非单例实例，可配合 [init] 的 `dbPath` / `factory`
  /// 指向内存数据库，从而让真实 SQL 与迁移链进入测试覆盖。
  ///
  /// 生产代码一律用 `StorageService()`，行为与之前完全一致。
  StorageService.forTesting();

  StorageService._internal();

  /// 打开数据库并完成初始化。
  ///
  /// [dbPath] / [factory] 供测试注入（`sqflite_common_ffi` + `inMemoryDatabasePath`）；
  /// 生产环境两者都为空，走原来的 `getDatabasesPath()` + 默认工厂。
  Future<void> init({String? dbPath, DatabaseFactory? factory}) async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();
    final resolvedFactory = factory ?? databaseFactory;
    final resolvedPath =
        dbPath ?? path.join(await getDatabasesPath(), _databaseName);
    _db = await resolvedFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onConfigure: (db) async {
          // sqlite 默认不开外键，必须每个连接显式打开。
          // 打开后删影片会自动带走会话 / 合集成员 / 标签关联，
          // 不再依赖各处手写清理，漏一处也不会留下孤儿数据。
          await db.execute('PRAGMA foreign_keys = ON');
          // WAL：读写不再互斥。后台 WebDAV 同步写入时，界面上的
          // 查询（片库滚动、日历翻月）不会被写锁挡住，反之亦然。
          // 单机应用不需要网络文件系统，WAL 是安全的选择。
          await db.execute('PRAGMA journal_mode = WAL');
          // 平衡耐久性与写入速度：WAL 下 NORMAL 只在检查点落盘，
          // 断电最多丢最后一个事务，不会损坏数据库文件。
          await db.execute('PRAGMA synchronous = NORMAL');
        },
        onCreate: (db, _) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _upgradeDatabase(db, oldVersion, newVersion);
        },
        onDowngrade: (db, oldVersion, newVersion) async {
          // 旧版 APK 打开新版数据库：立刻停下，绝不尝试读写。
          // 界面据此显示不带「重试」的说明页（见 app.dart）。
          throw DatabaseTooNewException(oldVersion, newVersion);
        },
      ),
    );
    _initialized = true;
    await _migrateLegacyData();
  }

  /// 仅供测试：关闭数据库并复位初始化状态，便于同一进程内重复打开。
  Future<void> closeForTest() async {
    if (!_initialized) return;
    await _db.close();
    _initialized = false;
  }

  /// 仅供测试：直接执行 SQL（无权限时抛错），用于读取 PRAGMA 与夹具校验。
  Future<List<Map<String, Object?>>> rawQueryForTest(String sql) async {
    _ensureInitialized();
    return _db.rawQuery(sql);
  }

  /// 仅供测试：底层数据库，便于断言事务与版本。
  Database get databaseForTest {
    _ensureInitialized();
    return _db;
  }

  // ========== 变更通知（T5b）==========

  /// 每次写事务提交后，向订阅者发出「被改动的逻辑表名」。
  ///
  /// 为什么用「表变更」而不是逐条记录：界面关心的是「我该重新查了」，
  /// 不关心具体哪一行变了。这样 StorageService 不需要知道谁在看什么，
  /// 也不会因为订阅者变多而变慢。
  final StreamController<Set<String>> _tableChanges =
      StreamController<Set<String>>.broadcast();

  /// 待提交的变更集合。一次事务里改多张表只发一次通知。
  Set<String>? _pendingTables;
  int _writeDepth = 0;

  /// 对外暴露的变更流。订阅者应当自行防抖后再查询。
  Stream<Set<String>> get tableChanges => _tableChanges.stream;

  /// 包装一次写操作：结束后统一发出变更通知。
  ///
  /// 约定（很关键）：**只有真正提交成功才通知**。事务回滚时 `_pendingTables`
  /// 会被丢弃，界面不会因为一次失败的操作去刷新——否则用户会看到
  /// 「数据闪了一下又变回去」。
  Future<T> _notifyOnWrite<T>(Set<String> tables, Future<T> Function() body) async {
    final outermost = _writeDepth == 0;
    if (outermost) _pendingTables = <String>{};
    _writeDepth++;
    try {
      final result = await body();
      _pendingTables?.addAll(tables);
      return result;
    } catch (error) {
      if (outermost) _pendingTables = null;
      rethrow;
    } finally {
      _writeDepth--;
      if (_writeDepth == 0) {
        final pending = _pendingTables;
        _pendingTables = null;
        if (pending != null && pending.isNotEmpty && !_tableChanges.isClosed) {
          _tableChanges.add(Set<String>.unmodifiable(pending));
        }
      }
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE $_moviesTable (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        year TEXT NOT NULL DEFAULT '',
        subject_type TEXT NOT NULL DEFAULT 'movie',
        director TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        cast_text TEXT NOT NULL DEFAULT '',
        rating REAL NOT NULL DEFAULT 0,
        genre_json TEXT NOT NULL DEFAULT '[]',
        region TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        published_at TEXT NOT NULL DEFAULT '',
        duration_text TEXT NOT NULL DEFAULT '',
        duration_minutes INTEGER,
        episodes_json TEXT NOT NULL DEFAULT '[]',
        poster TEXT NOT NULL DEFAULT '',
        douban_url TEXT NOT NULL DEFAULT '',
        watched INTEGER NOT NULL DEFAULT 0,
        watched_at TEXT,
        user_rating REAL,
        user_review TEXT,
        poster_color INTEGER,
        updated_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_movies_created_at ON $_moviesTable(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_movies_watched_history ON $_moviesTable(watched, watched_at DESC, created_at DESC)',
    );

    await db.execute('''
      CREATE TABLE $_drawRecordsTable (
        id TEXT PRIMARY KEY,
        movie_id TEXT NOT NULL,
        movie_title TEXT NOT NULL,
        movie_poster TEXT NOT NULL DEFAULT '',
        seed INTEGER NOT NULL DEFAULT 0,
        candidate_count INTEGER NOT NULL DEFAULT 0,
        outcome TEXT NOT NULL DEFAULT 'pending',
        drawn_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_draw_records_drawn_at ON $_drawRecordsTable(drawn_at DESC)',
    );

    await _createViewingSessionsTable(db);
    await _createCollectionAndTagTables(db);
    await db.execute(_createMovieStateView);
  }

  Future<void> _createViewingSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_viewingSessionsTable (
        id TEXT PRIMARY KEY,
        movie_id TEXT NOT NULL REFERENCES $_moviesTable(id) ON DELETE CASCADE,
        watched_at TEXT NOT NULL,
        watched_at_utc INTEGER,
        watched_on TEXT,
        mood TEXT NOT NULL DEFAULT 'none',
        watched_with TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        is_rewatch INTEGER NOT NULL DEFAULT 0,
        rating REAL,
        updated_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_sessions_movie ON $_viewingSessionsTable(movie_id, watched_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_sessions_watched_at ON $_viewingSessionsTable(watched_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_sessions_watched_on ON $_viewingSessionsTable(watched_on)',
    );
  }

  Future<void> _createCollectionAndTagTables(Database db) async {
    await db.execute('''
      CREATE TABLE $_collectionsTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon_key TEXT NOT NULL DEFAULT 'collections',
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $_collectionMembersTable (
        collection_id TEXT NOT NULL REFERENCES $_collectionsTable(id) ON DELETE CASCADE,
        movie_id TEXT NOT NULL REFERENCES $_moviesTable(id) ON DELETE CASCADE,
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT,
        added_at TEXT NOT NULL,
        PRIMARY KEY (collection_id, movie_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_collection_members ON $_collectionMembersTable(collection_id, sort_order)',
    );

    await db.execute('''
      CREATE TABLE $_tagsTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        updated_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $_movieTagsTable (
        movie_id TEXT NOT NULL REFERENCES $_moviesTable(id) ON DELETE CASCADE,
        tag_id TEXT NOT NULL REFERENCES $_tagsTable(id) ON DELETE CASCADE,
        updated_at TEXT NOT NULL DEFAULT '',
        deleted_at TEXT,
        PRIMARY KEY (movie_id, tag_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_movie_tags_tag ON $_movieTagsTable(tag_id)',
    );
    await db.execute(
      'CREATE INDEX idx_movie_tags_movie ON $_movieTagsTable(movie_id)',
    );
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion >= newVersion) return;

    if (oldVersion < 2) {
      await _addMovieColumnIfMissing(
        db,
        columnName: 'subject_type',
        columnDefinition: "TEXT NOT NULL DEFAULT 'movie'",
      );
      await _addMovieColumnIfMissing(
        db,
        columnName: 'author',
        columnDefinition: "TEXT NOT NULL DEFAULT ''",
      );
      await _addMovieColumnIfMissing(
        db,
        columnName: 'summary',
        columnDefinition: "TEXT NOT NULL DEFAULT ''",
      );
      await _addMovieColumnIfMissing(
        db,
        columnName: 'published_at',
        columnDefinition: "TEXT NOT NULL DEFAULT ''",
      );
      await _addMovieColumnIfMissing(
        db,
        columnName: 'duration_text',
        columnDefinition: "TEXT NOT NULL DEFAULT ''",
      );
      await _addMovieColumnIfMissing(
        db,
        columnName: 'episodes_json',
        columnDefinition: "TEXT NOT NULL DEFAULT '[]'",
      );
    }

    if (oldVersion < 3) {
      await _addColumnIfMissing(
        db,
        table: _moviesTable,
        columnName: 'duration_minutes',
        columnDefinition: 'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        table: _drawRecordsTable,
        columnName: 'outcome',
        columnDefinition: "TEXT NOT NULL DEFAULT 'pending'",
      );
    }

    if (oldVersion < 4) {
      await _createViewingSessionsTable(db);
      await _backfillViewingSessions(db);
    }

    if (oldVersion < 5) {
      await _createCollectionAndTagTables(db);
    }

    if (oldVersion < 6) {
      await _rebuildDrawRecordsWithoutLegacyColumns(db);
    }

    if (oldVersion < 7) {
      await _backfillCompletedSeriesWatchState(db);
    }

    if (oldVersion < 8) {
      await _migrateToForeignKeys(db);
      await _migrateSessionTimeColumns(db);
      await _addColumnIfMissing(
        db,
        table: _moviesTable,
        columnName: 'poster_color',
        columnDefinition: 'INTEGER',
      );
    }

    if (oldVersion < 9) {
      await _migrateMergeMetadata(db);
    }

    // 视图是幂等的：老库升级时补建，新建库（onCreate）时也会建。
    // 放在最后，保证它依赖的 deleted_at 列已经存在。
    await db.execute(_createMovieStateView);
  }

  /// v9：给可同步的表加记录级版本（`updated_at`）与墓碑（`deleted_at`）。
  ///
  /// 这是记录级合并的地基。迁移时把已有的 `created_at` / `watched_at` 等
  /// 转成 HLC，保证「老记录不会被判定成比新记录更新」。
  ///
  /// 注意 `deleted_at` 全部留空：历史数据里没有删除痕迹，
  /// 也不该凭空把任何行标成已删。
  Future<void> _migrateMergeMetadata(Database db) async {
    final deviceId = await _deviceIdForMigration();
    final clock = HlcClock(deviceId: deviceId);

    for (final table in _syncedTables) {
      await _addColumnIfMissing(
        db,
        table: table,
        columnName: 'updated_at',
        columnDefinition: "TEXT NOT NULL DEFAULT ''",
      );
      await _addColumnIfMissing(
        db,
        table: table,
        columnName: 'deleted_at',
        columnDefinition: 'TEXT',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${table}_updated_at '
        'ON $table(updated_at)',
      );
    }

    // 用各表自己的「有意义的时间」回填，缺什么用什么。
    await _backfillHlcColumn(
      db,
      table: _moviesTable,
      sourceColumns: const ['created_at', 'watched_at'],
      clock: clock,
    );
    await _backfillHlcColumn(
      db,
      table: _viewingSessionsTable,
      sourceColumns: const ['watched_at', 'created_at'],
      clock: clock,
    );
    // 抽片记录不参与记录级合并（它按「最近 N 条」滚动淘汰，冲突价值低），
    // 所以不在 [_syncedTables] 里，这里也就不回填。
    for (final table in const [
      _collectionsTable,
      _tagsTable,
      _collectionMembersTable,
    ]) {
      await _backfillHlcColumn(
        db,
        table: table,
        sourceColumns: const ['created_at', 'added_at'],
        clock: clock,
      );
    }
    // movie_tags 没有时间列：统一给一个固定的很早时间戳，
    // 让它们在未来任何一次真实修改面前都「更旧」。
    await db.execute(
      'UPDATE $_movieTagsTable SET updated_at = ? WHERE updated_at = ?',
      [Hlc(physicalMs: 0, counter: 0, deviceId: deviceId).encode(), ''],
    );
  }

  /// 需要记录级版本（合并）的同步表。
  ///
  /// **不含 `draw_records`**：抽片历史按「最近 N 条」滚动淘汰，
  /// 记录级合并对它价值低，加进来只会让迁移和合并多一份复杂度。
  static const List<String> _syncedTables = [
    _moviesTable,
    _viewingSessionsTable,
    _collectionsTable,
    _collectionMembersTable,
    _tagsTable,
    _movieTagsTable,
  ];

  /// 逐行把已有时间列转换成 HLC 写进 updated_at。
  ///
  /// 转换时通过 [HlcClock] 依次取时间戳，保证同一毫秒内的多行也有确定顺序。
  Future<void> _backfillHlcColumn(
    Database db, {
    required String table,
    required List<String> sourceColumns,
    required HlcClock clock,
  }) async {
    final rows = await db.query(table);
    if (rows.isEmpty) return;

    // 找出这张表实际存在的候选时间列。
    final columns = (await db.rawQuery('PRAGMA table_info($table)'))
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    final usable = sourceColumns.where(columns.contains).toList();

    final batch = db.batch();
    var patched = 0;
    for (final row in rows) {
      if ((row['updated_at']?.toString() ?? '').isNotEmpty) continue;

      DateTime? stamp;
      for (final column in usable) {
        final parsed = DateTime.tryParse(row[column]?.toString() ?? '');
        if (parsed != null) {
          stamp = parsed;
          break;
        }
      }
      // 完全解析不出时间：用当前时刻，至少不会比新记录更「新」得离谱。
      final observed = stamp == null
          ? null
          : Hlc(
              physicalMs: stamp.millisecondsSinceEpoch,
              counter: 0,
              deviceId: clock.deviceId,
            );
      clock.observe(observed);
      final encoded = clock.now().encode();
      batch.update(
        table,
        {'updated_at': encoded},
        where: _primaryKeyWhere(table),
        whereArgs: _primaryKeyArgs(table, row),
      );
      patched++;
    }
    if (patched > 0) await batch.commit(noResult: true);
  }

  /// 各表主键列（movie_tags / collection_members 是联合主键）。
  List<String> _primaryKeyColumns(String table) => switch (table) {
    _collectionMembersTable => const ['collection_id', 'movie_id'],
    _movieTagsTable => const ['movie_id', 'tag_id'],
    _ => const ['id'],
  };

  String _primaryKeyWhere(String table) =>
      _primaryKeyColumns(table).map((c) => '$c = ?').join(' AND ');

  List<Object?> _primaryKeyArgs(String table, Map<String, Object?> row) =>
      _primaryKeyColumns(table).map((c) => row[c]).toList();

  /// 本机设备 id，用于 HLC 的设备段。存在偏好里，缺失时生成并写回。
  Future<String> _deviceIdForMigration() async {
    const key = 'pianke_device_id';
    final existing = _prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated =
        'dev_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(4)}';
    await _prefs.setString(key, generated);
    return generated;
  }

  /// v8：把观影时间拆成「UTC 毫秒（排序）」+「当地日期（分组）」。
  ///
  /// 旧数据里 `watched_at` 格式混杂：有的带时区，有的是不带时区的本地串。
  /// 逐行解析，能解析的补齐两列；解析不了的留空并保持原串不动，
  /// 由读取时的 [ViewingSession.effectiveWatchedOn] 兜底——绝不丢行。
  Future<void> _migrateSessionTimeColumns(Database db) async {
    await _addColumnIfMissing(
      db,
      table: _viewingSessionsTable,
      columnName: 'watched_at_utc',
      columnDefinition: 'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: _viewingSessionsTable,
      columnName: 'watched_on',
      columnDefinition: 'TEXT',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_watched_on '
      'ON $_viewingSessionsTable(watched_on)',
    );

    final rows = await db.query(
      _viewingSessionsTable,
      columns: const ['id', 'watched_at'],
    );
    final batch = db.batch();
    var patched = 0;
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final raw = row['watched_at']?.toString();
      final utcMs = parseUtcMillis(raw);
      final on = salvageWatchedOn(raw);
      if (utcMs == null && on == null) continue; // 无法解析：保持原样
      batch.update(
        _viewingSessionsTable,
        {'watched_at_utc': utcMs, 'watched_on': on},
        where: 'id = ?',
        whereArgs: [id],
      );
      patched++;
    }
    if (patched > 0) await batch.commit(noResult: true);
  }

  /// v8：开启外键并加级联删除。
  ///
  /// SQLite 不能给已有表「就地」加外键，只能建新表 → 拷数据 → 删旧表 → 改名
  /// → 重建索引（沿用 [_rebuildDrawRecordsWithoutLegacyColumns] 的思路）。
  ///
  /// 关键顺序：**先清孤儿再开约束**。历史数据里可能已有指向已删影片的会话行，
  /// 不清掉的话建表拷贝阶段就会因外键失败，整个升级回滚——用户会在启动时
  /// 看到「初始化失败」。sqflite 的升级本身在事务内，任何一步抛错都会整体回滚，
  /// 数据库保持 v7 原样。
  Future<void> _migrateToForeignKeys(Database db) async {
    // 1) 清孤儿。draw_records 故意不加外键：影片删了，抽片历史仍要保留。
    await db.execute(
      'DELETE FROM $_viewingSessionsTable '
      'WHERE movie_id NOT IN (SELECT id FROM $_moviesTable)',
    );
    await db.execute(
      'DELETE FROM $_collectionMembersTable '
      'WHERE movie_id NOT IN (SELECT id FROM $_moviesTable) '
      '   OR collection_id NOT IN (SELECT id FROM $_collectionsTable)',
    );
    await db.execute(
      'DELETE FROM $_movieTagsTable '
      'WHERE movie_id NOT IN (SELECT id FROM $_moviesTable) '
      '   OR tag_id NOT IN (SELECT id FROM $_tagsTable)',
    );

    // 2) 重建三张子表，带上外键与级联。
    await _rebuildTableWithForeignKeys(
      db,
      table: _viewingSessionsTable,
      createSql: '''
        CREATE TABLE $_viewingSessionsTable (
          id TEXT PRIMARY KEY,
          movie_id TEXT NOT NULL REFERENCES $_moviesTable(id) ON DELETE CASCADE,
          watched_at TEXT NOT NULL,
          mood TEXT NOT NULL DEFAULT 'none',
          watched_with TEXT NOT NULL DEFAULT '',
          note TEXT NOT NULL DEFAULT '',
          is_rewatch INTEGER NOT NULL DEFAULT 0,
          rating REAL,
          created_at TEXT NOT NULL
        )
      ''',
      columns: const [
        'id',
        'movie_id',
        'watched_at',
        'mood',
        'watched_with',
        'note',
        'is_rewatch',
        'rating',
        'created_at',
      ],
      indexes: const [
        'CREATE INDEX idx_sessions_movie ON $_viewingSessionsTable(movie_id, watched_at DESC)',
        'CREATE INDEX idx_sessions_watched_at ON $_viewingSessionsTable(watched_at DESC)',
      ],
    );

    await _rebuildTableWithForeignKeys(
      db,
      table: _collectionMembersTable,
      createSql: '''
        CREATE TABLE $_collectionMembersTable (
          collection_id TEXT NOT NULL REFERENCES $_collectionsTable(id) ON DELETE CASCADE,
          movie_id TEXT NOT NULL REFERENCES $_moviesTable(id) ON DELETE CASCADE,
          sort_order INTEGER NOT NULL DEFAULT 0,
          added_at TEXT NOT NULL,
          PRIMARY KEY (collection_id, movie_id)
        )
      ''',
      columns: const ['collection_id', 'movie_id', 'sort_order', 'added_at'],
      indexes: const [
        'CREATE INDEX idx_collection_members ON $_collectionMembersTable(collection_id, sort_order)',
      ],
    );

    await _rebuildTableWithForeignKeys(
      db,
      table: _movieTagsTable,
      createSql: '''
        CREATE TABLE $_movieTagsTable (
          movie_id TEXT NOT NULL REFERENCES $_moviesTable(id) ON DELETE CASCADE,
          tag_id TEXT NOT NULL REFERENCES $_tagsTable(id) ON DELETE CASCADE,
          PRIMARY KEY (movie_id, tag_id)
        )
      ''',
      columns: const ['movie_id', 'tag_id'],
      indexes: const [
        'CREATE INDEX idx_movie_tags_tag ON $_movieTagsTable(tag_id)',
        'CREATE INDEX idx_movie_tags_movie ON $_movieTagsTable(movie_id)',
      ],
    );

    // 3) 收尾自检：还有违规行就抛错，让整个升级回滚，绝不带着坏数据启动。
    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) {
      throw StateError(
        '数据库升级校验失败：存在 ${violations.length} 行违反外键约束',
      );
    }
  }

  /// 用「建新表 → 拷数据 → 删旧表 → 改名 → 重建索引」替换一张表。
  Future<void> _rebuildTableWithForeignKeys(
    Database db, {
    required String table,
    required String createSql,
    required List<String> columns,
    required List<String> indexes,
  }) async {
    final tempTable = '${table}_v8';
    final columnList = columns.join(', ');
    await db.execute('DROP TABLE IF EXISTS $tempTable');
    await db.execute(
      createSql.replaceFirst('CREATE TABLE $table', 'CREATE TABLE $tempTable'),
    );
    await db.execute(
      'INSERT INTO $tempTable ($columnList) SELECT $columnList FROM $table',
    );
    await db.execute('DROP TABLE $table');
    await db.execute('ALTER TABLE $tempTable RENAME TO $table');
    for (final index in indexes) {
      await db.execute(index);
    }
  }

  /// Keeps legacy series whose completed episodes were saved without the
  /// aggregate movie flag aligned with the shared watch-state predicate.
  Future<void> _backfillCompletedSeriesWatchState(Database db) async {
    final rows = await db.query(
      _moviesTable,
      columns: const ['id', 'subject_type', 'episodes_json', 'watched'],
      where: 'subject_type = ? AND watched = 0',
      whereArgs: ['tvSeries'],
    );

    for (final row in rows) {
      final episodes = _decodeEpisodes(row['episodes_json']?.toString());
      if (episodes.isEmpty || !episodes.every((episode) => episode.watched)) {
        continue;
      }
      await db.update(
        _moviesTable,
        {'watched': 1},
        where: 'id = ?',
        whereArgs: [row['id']?.toString()],
      );
    }
  }

  Future<void> _rebuildDrawRecordsWithoutLegacyColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info($_drawRecordsTable)');
    final columnNames = columns
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    final hasLegacyColumns =
        columnNames.contains('mode') ||
        columnNames.contains('room_code') ||
        columnNames.contains('participants_json');
    if (!hasLegacyColumns) return;

    const tempTable = '${_drawRecordsTable}_v6';
    await db.execute('DROP TABLE IF EXISTS $tempTable');
    await db.execute('''
      CREATE TABLE $tempTable (
        id TEXT PRIMARY KEY,
        movie_id TEXT NOT NULL,
        movie_title TEXT NOT NULL,
        movie_poster TEXT NOT NULL DEFAULT '',
        seed INTEGER NOT NULL DEFAULT 0,
        candidate_count INTEGER NOT NULL DEFAULT 0,
        outcome TEXT NOT NULL DEFAULT 'pending',
        drawn_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      INSERT INTO $tempTable (
        id,
        movie_id,
        movie_title,
        movie_poster,
        seed,
        candidate_count,
        outcome,
        drawn_at
      )
      SELECT
        id,
        movie_id,
        movie_title,
        movie_poster,
        seed,
        candidate_count,
        outcome,
        drawn_at
      FROM $_drawRecordsTable
    ''');

    await db.execute('DROP TABLE $_drawRecordsTable');
    await db.execute('ALTER TABLE $tempTable RENAME TO $_drawRecordsTable');
    await db.execute(
      'CREATE INDEX idx_draw_records_drawn_at ON $_drawRecordsTable(drawn_at DESC)',
    );
  }

  /// v4 迁移：为现有 watched=1 的影片各生成一条默认观影会话，
  /// watchedAt 取现有值、rating/note 取 movie 的 userRating/userReview。
  Future<void> _backfillViewingSessions(Database db) async {
    final rows = await db.query(
      _moviesTable,
      columns: const [
        'id',
        'watched',
        'watched_at',
        'user_rating',
        'user_review',
        'created_at',
      ],
      where: 'watched = 1',
    );
    if (rows.isEmpty) return;

    final batch = db.batch();
    for (final row in rows) {
      final movieId = row['id']?.toString() ?? '';
      if (movieId.isEmpty) continue;
      final watchedAt =
          row['watched_at']?.toString() ??
          row['created_at']?.toString() ??
          DateTime.now().toIso8601String();
      final review = row['user_review']?.toString() ?? '';
      batch.insert(_viewingSessionsTable, {
        'id': 'vs_migrated_$movieId',
        'movie_id': movieId,
        'watched_at': watchedAt,
        'mood': 'none',
        'watched_with': '',
        'note': review,
        'is_rewatch': 0,
        'rating': (row['user_rating'] as num?)?.toDouble(),
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _addMovieColumnIfMissing(
    Database db, {
    required String columnName,
    required String columnDefinition,
  }) {
    return _addColumnIfMissing(
      db,
      table: _moviesTable,
      columnName: columnName,
      columnDefinition: columnDefinition,
    );
  }

  Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String columnName,
    required String columnDefinition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name']?.toString() == columnName);
    if (exists) return;

    await db.execute(
      'ALTER TABLE $table ADD COLUMN $columnName $columnDefinition',
    );
  }

  Future<void> _migrateLegacyData() async {
    final migrated = _prefs.getBool(_migrationFlagKey) ?? false;
    if (migrated) return;

    final movieCount = await countMovies();
    final drawRecordCount = await countDrawRecords();
    var shouldClearLegacyMovies = false;
    var shouldClearLegacyDrawHistory = false;

    final legacyMovies = _prefs.getString(_legacyMoviesKey);
    if (movieCount == 0 && legacyMovies != null && legacyMovies.isNotEmpty) {
      try {
        final decoded = jsonDecode(legacyMovies) as List<dynamic>;
        final movies = decoded
            .whereType<Map>()
            .map((json) => Movie.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        final batch = _db.batch();
        for (final movie in movies) {
          batch.insert(
            _moviesTable,
            _stamp(_movieToDbMap(movie)),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
        shouldClearLegacyMovies = true;
      } catch (_) {}
    } else if (movieCount > 0 || legacyMovies == null || legacyMovies.isEmpty) {
      shouldClearLegacyMovies = legacyMovies != null;
    }

    final legacyDrawHistory = _prefs.getString(_legacyDrawHistoryKey);
    if (drawRecordCount == 0 &&
        legacyDrawHistory != null &&
        legacyDrawHistory.isNotEmpty) {
      try {
        final decoded = jsonDecode(legacyDrawHistory) as List<dynamic>;
        final records = decoded
            .whereType<Map>()
            .map((json) => DrawRecord.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        final batch = _db.batch();
        for (final record in records.take(_maxDrawHistory)) {
          batch.insert(
            _drawRecordsTable,
            _drawRecordToDbMap(record),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
        shouldClearLegacyDrawHistory = true;
      } catch (_) {}
    } else if (drawRecordCount > 0 ||
        legacyDrawHistory == null ||
        legacyDrawHistory.isEmpty) {
      shouldClearLegacyDrawHistory = legacyDrawHistory != null;
    }

    if (shouldClearLegacyMovies) {
      await _prefs.remove(_legacyMoviesKey);
    }
    if (shouldClearLegacyDrawHistory) {
      await _prefs.remove(_legacyDrawHistoryKey);
    }
    final moviesReady =
        shouldClearLegacyMovies ||
        movieCount > 0 ||
        legacyMovies == null ||
        legacyMovies.isEmpty;
    final drawHistoryReady =
        shouldClearLegacyDrawHistory ||
        drawRecordCount > 0 ||
        legacyDrawHistory == null ||
        legacyDrawHistory.isEmpty;
    if (moviesReady && drawHistoryReady) {
      await _prefs.setBool(_migrationFlagKey, true);
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('StorageService.init() 尚未完成');
    }
  }

  // ========== 用户管理 ==========

  Future<LocalUser> getOrCreateUser() async {
    _ensureInitialized();

    String? userId = _prefs.getString(_userIdKey);
    String? userName = _prefs.getString(_userNameKey);

    if (userId == null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = _generateRandomString(6);
      userId = 'user_${timestamp}_$random';
      await _prefs.setString(_userIdKey, userId);
    }

    if (userName == null) {
      userName = '用户${_generateRandomNumber(4)}';
      await _prefs.setString(_userNameKey, userName);
    }

    return LocalUser(id: userId, name: userName);
  }

  Future<void> updateUserName(String newName) async {
    _ensureInitialized();
    await _prefs.setString(_userNameKey, newName);
  }

  String? get userId => _prefs.getString(_userIdKey);
  String? get userName => _prefs.getString(_userNameKey);

  // ========== 外观 / 主题 ==========

  /// 读取主题模式：'system' | 'light' | 'dark'（默认 system）
  String getThemeMode() {
    _ensureInitialized();
    return _prefs.getString(_themeModeKey) ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    _ensureInitialized();
    await _prefs.setString(_themeModeKey, mode);
  }

  // ========== 影片 ==========

  Future<int> countMovies({
    String searchQuery = '',
    bool watchedOnly = false,
    bool unwatchedOnly = false,
  }) async {
    _ensureInitialized();

    final clause = _buildMovieWhereClause(
      searchQuery: searchQuery,
      watchedOnly: watchedOnly,
      unwatchedOnly: unwatchedOnly,
    );
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_movieStateView m${clause.where == null ? '' : ' WHERE ${clause.where}'}',
      clause.whereArgs,
    );
    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  /// 统一的影片读取：附带 watched / watched_at 派生字段。
  /// 统一的影片读取：直接读 [v_movie_state] 视图，派生字段由视图提供。
  ///
  /// 视图已经把 `derived_watched` / `derived_watched_at` 算好，
  /// 这里不再重复写子查询——「已看」只有一份定义，就不会再出现
  /// 列表说已看、计数说未看这种自相矛盾。
  String _movieSelect({
    String? where,
    String? orderBy,
    bool withLimit = false,
  }) {
    final buffer = StringBuffer('SELECT m.* FROM $_movieStateView m');
    if (where != null) buffer.write(' WHERE $where');
    if (orderBy != null) buffer.write(' ORDER BY $orderBy');
    if (withLimit) buffer.write(' LIMIT ? OFFSET ?');
    return buffer.toString();
  }

  /// 已看排序：最近观影优先；未看排序：未看在前，再按入库时间。
  String _movieOrderBy({required bool watchedOnly}) {
    return watchedOnly
        ? 'derived_watched_at DESC, m.created_at DESC, m.id ASC'
        : 'derived_watched ASC, m.created_at DESC, m.id ASC';
  }

  Future<List<Movie>> queryMovies({
    required int limit,
    required int offset,
    String searchQuery = '',
    bool watchedOnly = false,
    bool unwatchedOnly = false,
  }) async {
    _ensureInitialized();

    final clause = _buildMovieWhereClause(
      searchQuery: searchQuery,
      watchedOnly: watchedOnly,
      unwatchedOnly: unwatchedOnly,
    );
    final rows = await _db.rawQuery(
      _movieSelect(
        where: clause.where,
        orderBy: _movieOrderBy(watchedOnly: watchedOnly),
        withLimit: true,
      ),
      [...?clause.whereArgs, limit, offset],
    );
    return rows.map(_movieFromDbMap).toList();
  }

  /// 按月份查询「分集在该月有观看日期」的剧集，附带集号明细。
  ///
  /// 电影靠观影会话进日历，而电视剧是逐集勾选的，原来只有 `watched`
  /// 布尔值、没有日期，导致花几天看完的剧在日历上全是空白。
  /// 现在分集带 `watchedAt`，这里把它们按月捞出来。
  ///
  /// 刻意**不在 SQL 里解析 JSON**：`episodes_json` 是 JSON 文本，
  /// 而 Android 7 的系统 SQLite 未必编译了 JSON1 扩展
  /// （`_seriesCompletedPredicate` 也是因此改用 LIKE 而非 json_each）。
  /// 所以只在 SQL 层做一次粗筛，日期解析放到 Dart 层，
  /// 既跨版本安全，解析逻辑也能单测。
  ///
  /// 粗筛条件：JSON 里出现本月前十位字符（`"2026-11-`）说明
  /// 至少有一集落在该月。这一条能把绝大多数月份无关的剧排除掉，
  /// 避免每次翻月都把整个片库的 JSON 全解析一遍。
  Future<List<({Movie movie, List<int> episodeNumbers})>>
  querySeriesEpisodesByMonth(DateTime month) async {
    _ensureInitialized();

    final firstDay = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);

    // 形如 2026-11，与 toIso8601String() 的前缀一致。
    final monthPrefix =
        '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}-';

    final rows = await _db.rawQuery(
      _movieSelect(
        where:
            "m.deleted_at IS NULL "
            "AND m.subject_type = 'tvSeries' "
            "AND m.episodes_json <> '[]' "
            // 粗筛：JSON 里出现本月前缀（形如 2026-11-）说明至少有一集
            // 落在该月。值来自代码生成（年月），不含用户输入，
            // 且格式固定为数字与连字符，无注入面。
            "AND m.episodes_json LIKE '%$monthPrefix%'",
      ),
    );

    final result = <({Movie movie, List<int> episodeNumbers})>[];
    for (final row in rows) {
      final movie = _movieFromDbMap(row);
      final numbers = <int>[];
      for (final episode in movie.episodes) {
        final at = episode.watchedAt;
        if (!episode.watched || at == null) continue;
        if (at.isBefore(firstDay) || !at.isBefore(nextMonth)) continue;
        numbers.add(episode.number);
      }
      if (numbers.isEmpty) continue;
      numbers.sort();
      result.add((movie: movie, episodeNumbers: numbers));
    }
    return result;
  }

  /// 按月份查询有观影会话的影片（用于日历），一部多次仅返回一次，
  /// watched_at 取该月内最近一次会话时间。
  Future<List<Movie>> queryWatchedMoviesByMonth(DateTime month) async {
    _ensureInitialized();

    final firstDay = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    final rows = await _db.rawQuery(
      '''
      SELECT m.*, 1 AS derived_watched,
        (SELECT MAX(vs.watched_at) FROM $_viewingSessionsTable vs
         WHERE vs.movie_id = m.id AND vs.watched_at >= ? AND vs.watched_at < ?)
          AS derived_watched_at
      FROM $_movieStateView m
      WHERE EXISTS(
        SELECT 1 FROM $_viewingSessionsTable vs
        WHERE vs.movie_id = m.id AND vs.watched_at >= ? AND vs.watched_at < ?
          AND vs.deleted_at IS NULL
      )
        AND m.deleted_at IS NULL
      ORDER BY derived_watched_at DESC, m.created_at DESC
      ''',
      [
        firstDay.toIso8601String(),
        nextMonth.toIso8601String(),
        firstDay.toIso8601String(),
        nextMonth.toIso8601String(),
      ],
    );
    return rows.map(_movieFromDbMap).toList();
  }

  Future<List<String>> queryMovieIds({
    String searchQuery = '',
    bool watchedOnly = false,
    bool unwatchedOnly = false,
  }) async {
    _ensureInitialized();

    final clause = _buildMovieWhereClause(
      searchQuery: searchQuery,
      watchedOnly: watchedOnly,
      unwatchedOnly: unwatchedOnly,
    );
    final rows = await _db.rawQuery(
      'SELECT m.id FROM $_movieStateView m'
      '${clause.where == null ? '' : ' WHERE ${clause.where}'}'
      ' ORDER BY ${_movieOrderBy(watchedOnly: watchedOnly)}',
      clause.whereArgs,
    );
    return rows
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<Movie?> getMovieById(String id) async {
    _ensureInitialized();

    final rows = await _db.rawQuery(
      '${_movieSelect(where: 'm.id = ? AND m.deleted_at IS NULL')} LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return _movieFromDbMap(rows.first);
  }

  Future<Movie?> _getMovieByDoubanSubjectId(String subjectId) async {
    final normalizedSubjectId = subjectId.trim();
    if (normalizedSubjectId.isEmpty) return null;

    final canonicalId = 'douban_$normalizedSubjectId';
    final byId = await getMovieById(canonicalId);
    if (byId != null) return byId;

    final legacyById = await getMovieById(normalizedSubjectId);
    if (legacyById != null) return legacyById;

    final rows = await _db.rawQuery(_movieSelect(where: "m.douban_url <> '' AND m.deleted_at IS NULL"));
    for (final row in rows) {
      final movie = _movieFromDbMap(row);
      if (_extractDoubanSubjectId(movie.doubanUrl) == normalizedSubjectId) {
        return movie;
      }
    }
    return null;
  }

  /// 查这个主键是否被**已软删除**的行占用。
  ///
  /// 为什么需要它：`getMovieById` / `_getMovieByDoubanSubjectId` 都带
  /// `deleted_at IS NULL`，会把墓碑行当作不存在。但 `movies.id` 是主键，
  /// 墓碑行仍然占着这个 id。于是出现：
  ///   删过某片 → 重新添加 → 查重通过 → INSERT 主键冲突
  /// → 用户看到「保存失败: UNIQUE constraint failed: movies.id」。
  ///
  /// 返回墓碑行时，调用方应当「复活」它（清掉 deleted_at 并覆盖内容），
  /// 而不是插入新行。
  Future<Movie?> _findTombstoneById(String id) async {
    if (id.isEmpty) return null;
    final rows = await _db.query(
      _moviesTable,
      where: 'id = ? AND deleted_at IS NOT NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _movieFromDbMap(rows.first);
  }

  Future<List<Movie>> getMoviesByIds(Iterable<String> ids) async {
    _ensureInitialized();

    final orderedIds = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (orderedIds.isEmpty) return const [];

    final movieById = <String, Movie>{};
    for (final chunk in _chunkList(orderedIds, 800)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db.rawQuery(
        _movieSelect(where: 'm.id IN ($placeholders) AND m.deleted_at IS NULL'),
        chunk,
      );
      for (final row in rows) {
        final movie = _movieFromDbMap(row);
        movieById[movie.id] = movie;
      }
    }

    return orderedIds.map((id) => movieById[id]).whereType<Movie>().toList();
  }

  Future<Movie> addMovie(Movie movie) async {
    _ensureInitialized();

    if (movie.id.isNotEmpty) {
      final existing = await getMovieById(movie.id);
      if (existing != null) {
        throw DuplicateMovieException(existing);
      }
    }

    final subjectId = _extractDoubanSubjectId(movie.doubanUrl);
    if (subjectId != null) {
      final existing = await _getMovieByDoubanSubjectId(subjectId);
      if (existing != null) {
        throw DuplicateMovieException(existing);
      }
    }

    final newMovie = movie.id.isNotEmpty
        ? movie
        : movie.copyWith(
            id: 'movie_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(4)}',
          );

    // 主键可能被一条「已软删除」的墓碑行占着。
    // 上面的查重都带 `deleted_at IS NULL`，看不见它，但数据库主键看得见，
    // 直接 INSERT 会抛 UNIQUE constraint failed: movies.id。
    //
    // 正确处理是「复活」那一行：把墓碑行覆盖成新内容并清掉 deleted_at。
    // 这样既满足「删了还能重新添加」的用户预期，也不留重复主键。
    final tombstone = await _findTombstoneById(newMovie.id);
    if (tombstone != null) {
      await _notifyOnWrite({_moviesTable}, () async {
        await _db.update(
          _moviesTable,
          {..._stamp(_movieToDbMap(newMovie)), 'deleted_at': null},
          where: 'id = ?',
          whereArgs: [newMovie.id],
        );
      });
      return newMovie;
    }

    await _notifyOnWrite({_moviesTable}, () async {
      await _db.insert(
        _moviesTable,
        _stamp(_movieToDbMap(newMovie)),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
    return newMovie;
  }

  String? _extractDoubanSubjectId(String url) {
    final match = RegExp(r'(?:subject|movie)/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  Future<void> updateMovie(Movie updatedMovie) async {
    _ensureInitialized();
    await _notifyOnWrite({_moviesTable}, () async {
      await _db.update(
        _moviesTable,
        _stamp(_movieToDbMap(updatedMovie)),
        where: 'id = ?',
        whereArgs: [updatedMovie.id],
      );
    });
  }

  /// 删除影片 —— 写墓碑而不是物理删除。
  ///
  /// 为什么必须软删除：记录级合并靠「谁的删除标记更新」判断删除是否生效。
  /// 如果这里直接把行删掉，另一台设备离线时的那份备份里还有这部影片，
  /// 合并时本机根本没有对应的墓碑，那条旧数据就会被当成「新记录」复活。
  ///
  /// 墓碑行对用户完全不可见（所有查询都带 `deleted_at IS NULL`），
  /// 也不会参与抽片与计数；它只在下一次同步时告诉另一端「这条已经删了」。
  /// 满 90 天后由同步流程统一物理清理。
  Future<void> deleteMovie(String movieId) async {
    _ensureInitialized();
    final stamp = _hlc.now().encode();
    await _notifyOnWrite({
      _moviesTable,
      _viewingSessionsTable,
      _collectionMembersTable,
      _movieTagsTable,
    }, () => _db.transaction((txn) async {
      // 子记录跟着父记录一起打墓碑，父记录复活时它们也会一起回来。
      for (final table in [
        _viewingSessionsTable,
        _collectionMembersTable,
        _movieTagsTable,
      ]) {
        await txn.update(
          table,
          {'deleted_at': stamp, 'updated_at': stamp},
          where: 'movie_id = ? AND deleted_at IS NULL',
          whereArgs: [movieId],
        );
      }
      await txn.update(
        _moviesTable,
        {'deleted_at': stamp, 'updated_at': stamp},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [movieId],
      );
    }));
  }

  /// 给若干行打墓碑（软删除）。统一入口，保证 `deleted_at` 与 `updated_at`
  /// 用的是同一个时间戳——两者不一致会让合并逻辑对「删除还是修改更新」判断错误。
  Future<void> _markDeleted(
    String table,
    String where,
    List<Object?> whereArgs,
  ) async {
    final stamp = _hlc.now().encode();
    await _db.update(
      table,
      {'deleted_at': stamp, 'updated_at': stamp},
      where: '$where AND deleted_at IS NULL',
      whereArgs: whereArgs,
    );
  }

  /// 物理移除墓碑行（同步流程在保留期满后调用）。
  Future<void> purgeTombstones({int retentionDays = 90}) async {
    _ensureInitialized();
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;
    final cutoffHlc = Hlc(
      physicalMs: cutoff,
      counter: 0,
      deviceId: '',
    ).encode();
    await _db.transaction((txn) async {
      // 先清子表再清主表，避免外键级联把它们提前带走导致统计不准。
      for (final table in const [
        _movieTagsTable,
        _collectionMembersTable,
        _viewingSessionsTable,
        _collectionsTable,
        _tagsTable,
        _moviesTable,
      ]) {
        await txn.delete(
          table,
          where: "deleted_at IS NOT NULL AND deleted_at <> '' AND deleted_at < ?",
          whereArgs: [cutoffHlc],
        );
      }
    });
  }

  // ========== 抽奖历史 ==========

  Future<int> countDrawRecords() async {
    _ensureInitialized();

    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_drawRecordsTable',
    );
    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<DrawRecord>> queryDrawRecords({
    required int limit,
    required int offset,
  }) async {
    _ensureInitialized();

    final rows = await _db.query(
      _drawRecordsTable,
      orderBy: 'drawn_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_drawRecordFromDbMap).toList();
  }

  Future<void> addDrawRecord(DrawRecord record) async {
    _ensureInitialized();

    await _db.insert(
      _drawRecordsTable,
      _drawRecordToDbMap(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _db.rawDelete(
      '''
        DELETE FROM $_drawRecordsTable
        WHERE id IN (
          SELECT id FROM $_drawRecordsTable
          ORDER BY drawn_at DESC
          LIMIT -1 OFFSET ?
        )
      ''',
      [_maxDrawHistory],
    );
  }

  Future<void> clearDrawHistory() async {
    _ensureInitialized();
    await _db.delete(_drawRecordsTable);
  }

  /// 删除单条抽片记录。
  Future<void> deleteDrawRecord(String recordId) async {
    _ensureInitialized();
    await _db.delete(
      _drawRecordsTable,
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  /// 更新某条抽片记录的处理状态（accepted/skipped）。
  Future<void> updateDrawRecordOutcome(
    String recordId,
    DrawOutcome outcome,
  ) async {
    _ensureInitialized();
    await _db.update(
      _drawRecordsTable,
      {'outcome': outcome.value},
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  /// 公平模式用：最近 [withinDays] 天内抽过的影片 id 集合。
  Future<Set<String>> queryRecentlyDrawnMovieIds({int withinDays = 30}) async {
    _ensureInitialized();
    final since = DateTime.now().subtract(Duration(days: withinDays));
    final rows = await _db.query(
      _drawRecordsTable,
      columns: const ['movie_id'],
      where: 'drawn_at >= ?',
      whereArgs: [since.toIso8601String()],
    );
    return rows
        .map((row) => row['movie_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// 公平模式用：最近 [withinDays] 天内看过的影片 id 集合（基于观影会话）。
  Future<Set<String>> queryRecentlyWatchedMovieIds({
    int withinDays = 30,
  }) async {
    _ensureInitialized();
    final since = DateTime.now().subtract(Duration(days: withinDays));
    final rows = await _db.query(
      _viewingSessionsTable,
      columns: const ['movie_id'],
      where: 'watched_at >= ?',
      whereArgs: [since.toIso8601String()],
    );
    return rows
        .map((row) => row['movie_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// 筛选面板用：扫描全库轻量字段，汇总可选的类型/地区/年代区间/最长片长。
  Future<MovieFacets> queryMovieFacets() async {
    _ensureInitialized();
    final rows = await _db.query(
      _moviesTable,
      columns: const [
        'genre_json',
        'region',
        'year',
        'duration_minutes',
        'duration_text',
      ],
    );

    final genres = <String>{};
    final regions = <String>{};
    int? minYear;
    int? maxYear;
    var maxDuration = 0;

    for (final row in rows) {
      for (final genre in _decodeStringList(row['genre_json']?.toString())) {
        final trimmed = genre.trim();
        if (trimmed.isNotEmpty) genres.add(trimmed);
      }
      final region = row['region']?.toString().trim() ?? '';
      for (final part in _splitRegionFacets(region)) {
        regions.add(part);
      }

      final year = int.tryParse(
        RegExp(r'\d{4}').firstMatch(row['year']?.toString() ?? '')?.group(0) ??
            '',
      );
      if (year != null) {
        minYear = minYear == null ? year : min(minYear, year);
        maxYear = maxYear == null ? year : max(maxYear, year);
      }

      final duration =
          (row['duration_minutes'] as int?) ??
          Movie.parseDurationMinutes(row['duration_text']?.toString());
      if (duration != null && duration > maxDuration) {
        maxDuration = duration;
      }
    }

    return MovieFacets(
      genres: genres.toList()..sort(),
      regions: regions.toList()..sort(),
      minYear: minYear,
      maxYear: maxYear,
      maxDurationMinutes: maxDuration > 0 ? maxDuration : null,
    );
  }

  List<String> _splitRegionFacets(String raw) {
    if (raw.trim().isEmpty) return const [];
    return raw
        .split(RegExp(r'[\s/,，、|]+'))
        .map((region) => region.trim())
        .where((region) => region.isNotEmpty)
        .toSet()
        .toList();
  }

  // ========== 观影会话 ==========

  /// 某部影片的所有观影会话，按观影时间倒序。
  Future<List<ViewingSession>> querySessionsByMovie(String movieId) async {
    _ensureInitialized();
    final rows = await _db.query(
      _viewingSessionsTable,
      where: 'movie_id = ? AND deleted_at IS NULL',
      whereArgs: [movieId],
      orderBy: 'COALESCE(watched_at_utc, 9223372036854775807) DESC, watched_at DESC, created_at DESC',
    );
    return rows.map(_sessionFromDbMap).toList();
  }

  /// 某月所有观影会话，按观影时间倒序。
  Future<List<ViewingSession>> querySessionsByMonth(DateTime month) async {
    _ensureInitialized();
    final firstDay = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    final rows = await _db.query(
      _viewingSessionsTable,
      where: 'watched_at >= ? AND watched_at < ? AND deleted_at IS NULL',
      whereArgs: [firstDay.toIso8601String(), nextMonth.toIso8601String()],
      orderBy: 'COALESCE(watched_at_utc, 9223372036854775807) DESC, watched_at DESC, created_at DESC',
    );
    return rows.map(_sessionFromDbMap).toList();
  }

  /// 分页查询全部观影会话（时间线），按观影时间倒序。
  Future<List<ViewingSession>> querySessions({
    required int limit,
    required int offset,
  }) async {
    _ensureInitialized();
    final rows = await _db.query(
      _viewingSessionsTable,
      where: 'deleted_at IS NULL',
      orderBy: 'COALESCE(watched_at_utc, 9223372036854775807) DESC, watched_at DESC, created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_sessionFromDbMap).toList();
  }

  Future<int> countSessions() async {
    _ensureInitialized();
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_viewingSessionsTable WHERE deleted_at IS NULL',
    );
    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<bool> movieHasSession(String movieId) async {
    _ensureInitialized();
    final rows = await _db.query(
      _viewingSessionsTable,
      columns: const ['id'],
      where: 'movie_id = ? AND deleted_at IS NULL',
      whereArgs: [movieId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<ViewingSession> addSession(ViewingSession session) async {
    _ensureInitialized();
    return _notifyOnWrite({_viewingSessionsTable}, () => _addSessionInner(session));
  }

  Future<ViewingSession> _addSessionInner(ViewingSession session) async {
    final stored = session.id.isNotEmpty
        ? session
        : session.copyWith(
            id: 'vs_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(4)}',
          );
    await _db.insert(
      _viewingSessionsTable,
      _sessionToDbMap(stored),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return stored;
  }

  Future<void> updateSession(ViewingSession session) async {
    _ensureInitialized();
    await _db.update(
      _viewingSessionsTable,
      _stamp(_sessionToDbMap(session)),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> deleteSession(String sessionId) async {
    _ensureInitialized();
    // 软删除：让另一台设备同步时能看到「这条被删了」。
    await _notifyOnWrite(
      {_viewingSessionsTable},
      () => _markDeleted(_viewingSessionsTable, 'id = ?', [sessionId]),
    );
  }

  /// 删除某部影片的全部会话（用于「取消已看」）。
  Future<void> deleteSessionsByMovie(String movieId) async {
    _ensureInitialized();
    await _notifyOnWrite(
      {_viewingSessionsTable},
      () => _markDeleted(_viewingSessionsTable, 'movie_id = ?', [movieId]),
    );
  }

  /// 备份用：全部会话。
  Future<List<ViewingSession>> getAllSessionsForBackup() async {
    _ensureInitialized();
    final rows = await _db.query(
      _viewingSessionsTable,
      where: 'deleted_at IS NULL',
      orderBy: 'COALESCE(watched_at_utc, -1) ASC, watched_at ASC',
    );
    return rows.map(_sessionFromDbMap).toList();
  }

  /// 备份恢复用：仅当不存在时插入，返回是否实际写入。
  Future<bool> addSessionIfNotExists(ViewingSession session) async {
    _ensureInitialized();
    if (session.id.isEmpty) return false;
    final existing = await _db.query(
      _viewingSessionsTable,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [session.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    await _db.insert(
      _viewingSessionsTable,
      _stamp(_sessionToDbMap(session)),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return true;
  }

  // ---- 合集 / 标签备份（导出为原始行，按表恢复）----

  Future<Map<String, List<Map<String, Object?>>>>
  getCollectionsAndTagsForBackup() async {
    _ensureInitialized();
    return {
      'collections': await _db.query(_collectionsTable, where: 'deleted_at IS NULL'),
      'collectionMembers': await _db.query(
        _collectionMembersTable,
        where: 'deleted_at IS NULL',
      ),
      'tags': await _db.query(_tagsTable, where: 'deleted_at IS NULL'),
      'movieTags': await _db.query(_movieTagsTable, where: 'deleted_at IS NULL'),
    };
  }

  /// 恢复合集/标签原始行（仅当主键不冲突时写入）。返回写入计数。
  Future<int> restoreCollectionsAndTags(Map<String, dynamic> data) async {
    _ensureInitialized();
    var imported = 0;
    final batch = _db.batch();

    for (final table in const [
      _collectionsTable,
      _collectionMembersTable,
      _tagsTable,
      _movieTagsTable,
    ]) {
      final key = switch (table) {
        _collectionsTable => 'collections',
        _collectionMembersTable => 'collectionMembers',
        _tagsTable => 'tags',
        _ => 'movieTags',
      };
      final rows = data[key];
      if (rows is! List) continue;
      for (final raw in rows) {
        if (raw is! Map) continue;
        batch.insert(
          table,
          _stamp(Map<String, Object?>.from(raw)),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        imported++;
      }
    }
    await batch.commit(noResult: true);
    return imported;
  }

  /// Replaces all user-owned sync data in one transaction.
  Future<void> replaceBackupData({
    required List<Movie> movies,
    required List<DrawRecord> drawRecords,
    required List<ViewingSession> sessions,
    required Map<String, List<Map<String, Object?>>> tableData,
  }) async {
    _ensureInitialized();
    await _db.transaction((txn) async {
      for (final table in const [
        _movieTagsTable,
        _collectionMembersTable,
        _tagsTable,
        _collectionsTable,
        _drawRecordsTable,
        _viewingSessionsTable,
        _moviesTable,
      ]) {
        await txn.delete(table);
      }

      final batch = txn.batch();
      for (final movie in movies) {
        batch.insert(_moviesTable, _stamp(_movieToDbMap(movie)));
      }
      for (final record in drawRecords) {
        batch.insert(_drawRecordsTable, _drawRecordToDbMap(record));
      }
      for (final session in sessions) {
        batch.insert(_viewingSessionsTable, _stamp(_sessionToDbMap(session)));
      }
      for (final table in const [
        _collectionsTable,
        _collectionMembersTable,
        _tagsTable,
        _movieTagsTable,
      ]) {
        final rows =
            tableData[table == _collectionsTable
                ? 'collections'
                : table == _collectionMembersTable
                ? 'collectionMembers'
                : table == _tagsTable
                ? 'tags'
                : 'movieTags'];
        for (final row in rows ?? const <Map<String, Object?>>[]) {
          batch.insert(table, _stamp(Map<String, Object?>.from(row)));
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<ViewingStats> queryViewingStats() async {
    _ensureInitialized();

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);

    final totalCount = await countSessions();
    if (totalCount == 0) return const ViewingStats();

    // 按月计数用 watched_on（当地日期）判断归属月份：
    // 这本来就是「哪个月看的」问题，跟 UTC 时刻无关，也不怕旧数据格式不一。
    final monthPrefix = formatWatchedOn(monthStart).substring(0, 7);
    final monthlyResult = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_viewingSessionsTable '
      'WHERE COALESCE(watched_on, substr(watched_at, 1, 7)) = ?',
      [monthPrefix],
    );
    final monthlyCount = (monthlyResult.first['count'] as num?)?.toInt() ?? 0;

    final ratingResult = await _db.rawQuery(
      'SELECT MAX(rating) AS max_rating FROM $_viewingSessionsTable WHERE rating IS NOT NULL',
    );
    final highestRating = (ratingResult.first['max_rating'] as num?)
        ?.toDouble();

    // 类型分布：join 影片类型 json，本地聚合
    final genreRows = await _db.rawQuery(
      'SELECT m.genre_json FROM $_viewingSessionsTable vs '
      'JOIN $_moviesTable m ON m.id = vs.movie_id',
    );
    final genreCounts = <String, int>{};
    for (final row in genreRows) {
      for (final genre in _decodeStringList(row['genre_json']?.toString())) {
        final trimmed = genre.trim();
        if (trimmed.isEmpty) continue;
        genreCounts[trimmed] = (genreCounts[trimmed] ?? 0) + 1;
      }
    }
    final genreDistribution = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 连续观影天数：按「当地日期」去重。
    // 用 watched_on 而不是 substr(watched_at,1,10)：后者切的是字符串字面量，
    // 对 UTC 或不带时区的旧串会切出错误的一天。
    final dateRows = await _db.rawQuery(
      'SELECT DISTINCT COALESCE(watched_on, substr(watched_at, 1, 10)) AS day '
      'FROM $_viewingSessionsTable',
    );
    final watchedDays = dateRows
        .map((row) => row['day']?.toString() ?? '')
        .where((day) => day.isNotEmpty)
        .toSet();
    final streakDays = _computeStreak(watchedDays, now);

    return ViewingStats(
      monthlyCount: monthlyCount,
      totalCount: totalCount,
      genreDistribution: genreDistribution,
      highestRating: highestRating,
      streakDays: streakDays,
    );
  }

  int _computeStreak(Set<String> watchedDays, DateTime now) {
    if (watchedDays.isEmpty) return 0;
    String dayKey(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final today = DateTime(now.year, now.month, now.day);
    // 允许「今天还没看」：从今天或昨天起算
    var cursor = watchedDays.contains(dayKey(today))
        ? today
        : today.subtract(const Duration(days: 1));
    if (!watchedDays.contains(dayKey(cursor))) return 0;

    var streak = 0;
    while (watchedDays.contains(dayKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Map<String, Object?> _sessionToDbMap(ViewingSession session) {
    return {
      'id': session.id,
      'movie_id': session.movieId,
      'watched_at': session.watchedAt.toIso8601String(),
      // 写入时就把两个派生值算好落库：此后不再从 watched_at 反推，
      // 换时区也改不动「那天算哪一天」。
      'watched_at_utc': session.watchedAt.toUtc().millisecondsSinceEpoch,
      'watched_on': session.effectiveWatchedOn,
      'mood': session.mood.value,
      'watched_with': session.watchedWith,
      'note': session.note,
      'is_rewatch': session.isRewatch ? 1 : 0,
      'rating': session.rating,
      'created_at': session.createdAt.toIso8601String(),
    };
  }

  ViewingSession _sessionFromDbMap(Map<String, Object?> row) {
    return ViewingSession(
      id: row['id']?.toString() ?? '',
      movieId: row['movie_id']?.toString() ?? '',
      watchedAt:
          DateTime.tryParse(row['watched_at']?.toString() ?? '') ??
          DateTime.now(),
      mood: WatchMood.fromValue(row['mood']?.toString()),
      watchedWith: row['watched_with']?.toString() ?? '',
      note: row['note']?.toString() ?? '',
      isRewatch: (row['is_rewatch'] as int? ?? 0) == 1,
      rating: (row['rating'] as num?)?.toDouble(),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      watchedAtUtcMs: (row['watched_at_utc'] as num?)?.toInt(),
      watchedOn: row['watched_on']?.toString(),
    );
  }

  // ========== 合集 ==========

  /// 全部手动合集，附带成员数与最多 4 张预览海报，按 sort_order 排序。
  Future<List<MovieCollection>> queryCollections() async {
    _ensureInitialized();
    final rows = await _db.query(
      _collectionsTable,
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, created_at ASC',
    );
    if (rows.isEmpty) return const [];
    final countRows = await _db.rawQuery(
      'SELECT collection_id, COUNT(*) AS count FROM $_collectionMembersTable GROUP BY collection_id',
    );
    final counts = {
      for (final row in countRows)
        row['collection_id']?.toString(): (row['count'] as num?)?.toInt() ?? 0,
    };
    final result = <MovieCollection>[];
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final count = counts[id] ?? 0;
      final posterRows = await _db.rawQuery(
        '''
        SELECT m.poster FROM $_collectionMembersTable cm
        JOIN $_moviesTable m ON m.id = cm.movie_id
        WHERE cm.collection_id = ? AND m.poster != ''
        ORDER BY cm.sort_order ASC LIMIT 4
        ''',
        [id],
      );
      result.add(
        _collectionFromDbMap(
          row,
          memberCount: count,
          previewPosters: posterRows
              .map((r) => r['poster']?.toString() ?? '')
              .where((p) => p.isNotEmpty)
              .toList(),
        ),
      );
    }
    return result;
  }

  Future<MovieCollection?> getCollectionById(String id) async {
    _ensureInitialized();
    final rows = await _db.query(
      _collectionsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final countResult = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_collectionMembersTable WHERE collection_id = ?',
      [id],
    );
    final count = (countResult.first['count'] as num?)?.toInt() ?? 0;
    return _collectionFromDbMap(rows.first, memberCount: count);
  }

  Future<MovieCollection> addCollection(MovieCollection collection) async {
    _ensureInitialized();
    final orderResult = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM $_collectionsTable',
    );
    final nextOrder = (orderResult.first['next'] as num?)?.toInt() ?? 0;
    final stored = collection.copyWith(
      id: collection.id.isNotEmpty
          ? collection.id
          : 'col_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(4)}',
      sortOrder: collection.sortOrder == 0 ? nextOrder : collection.sortOrder,
    );
    await _db.insert(_collectionsTable, _stamp({
      'id': stored.id,
      'name': stored.name,
      'icon_key': stored.iconKey,
      'sort_order': stored.sortOrder,
      'created_at': stored.createdAt.toIso8601String(),
    }), conflictAlgorithm: ConflictAlgorithm.replace);
    return stored;
  }

  Future<void> updateCollection(MovieCollection collection) async {
    _ensureInitialized();
    await _db.update(
      _collectionsTable,
      {
        'name': collection.name,
        'icon_key': collection.iconKey,
        'sort_order': collection.sortOrder,
      },
      where: 'id = ?',
      whereArgs: [collection.id],
    );
  }

  Future<void> deleteCollection(String collectionId) async {
    _ensureInitialized();
    await _db.transaction((txn) async {
      await txn.delete(
        _collectionMembersTable,
        where: 'collection_id = ?',
        whereArgs: [collectionId],
      );
      await txn.delete(
        _collectionsTable,
        where: 'id = ?',
        whereArgs: [collectionId],
      );
    });
  }

  /// 合集成员影片 id（按 sort_order）。
  Future<List<String>> queryCollectionMemberIds(String collectionId) async {
    _ensureInitialized();
    final rows = await _db.query(
      _collectionMembersTable,
      columns: const ['movie_id'],
      where: 'collection_id = ? AND deleted_at IS NULL',
      whereArgs: [collectionId],
      orderBy: 'sort_order ASC',
    );
    return rows
        .map((row) => row['movie_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<void> addMovieToCollection(String collectionId, String movieId) async {
    _ensureInitialized();
    final orderResult = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM $_collectionMembersTable WHERE collection_id = ?',
      [collectionId],
    );
    final nextOrder = (orderResult.first['next'] as num?)?.toInt() ?? 0;
    await _db.insert(_collectionMembersTable, _stamp({
      'collection_id': collectionId,
      'movie_id': movieId,
      'sort_order': nextOrder,
      'added_at': DateTime.now().toIso8601String(),
    }), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Apply just the member differences atomically, preserving existing ordering.
  Future<void> updateCollectionMembers(
    String collectionId, {
    required Iterable<String> add,
    required Iterable<String> remove,
  }) async {
    _ensureInitialized();
    final additions = add.toSet();
    final removals = remove.toSet()..removeAll(additions);
    await _db.transaction((txn) async {
      final collection = await txn.query(
        _collectionsTable,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [collectionId],
        limit: 1,
      );
      if (collection.isEmpty) throw StateError('合集已不存在，请返回后重试');
      for (final id in removals) {
        await txn.delete(
          _collectionMembersTable,
          where: 'collection_id = ? AND movie_id = ?',
          whereArgs: [collectionId, id],
        );
      }
      final order = await txn.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM $_collectionMembersTable WHERE collection_id = ?',
        [collectionId],
      );
      var next = (order.first['next'] as num).toInt();
      final now = DateTime.now().toIso8601String();
      for (final id in additions) {
        // A movie may have been removed while the picker was open.
        final movie = await txn.query(
          _moviesTable,
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (movie.isEmpty) throw StateError('所选影片已被删除，请刷新后重试');
        await txn.insert(_collectionMembersTable, {
          'collection_id': collectionId,
          'movie_id': id,
          'sort_order': next++,
          'added_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> removeMovieFromCollection(
    String collectionId,
    String movieId,
  ) async {
    _ensureInitialized();
    await _db.delete(
      _collectionMembersTable,
      where: 'collection_id = ? AND movie_id = ?',
      whereArgs: [collectionId, movieId],
    );
  }

  /// 某影片所属的手动合集 id 集合。
  Future<Set<String>> queryCollectionIdsForMovie(String movieId) async {
    _ensureInitialized();
    final rows = await _db.query(
      _collectionMembersTable,
      columns: const ['collection_id'],
      where: 'movie_id = ? AND deleted_at IS NULL',
      whereArgs: [movieId],
    );
    return rows
        .map((row) => row['collection_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// 智能合集：按类型/导演/年代/地区动态聚合，返回带成员数与预览海报的虚拟合集。
  Future<List<MovieCollection>> querySmartCollections() async {
    _ensureInitialized();
    final result = <MovieCollection>[];

    // 类型（取片数最多的前 6 个）
    final genreCounts = <String, int>{};
    final genreRows = await _db.query(
      _moviesTable,
      columns: const ['genre_json'],
    );
    for (final row in genreRows) {
      for (final genre in _decodeStringList(row['genre_json']?.toString())) {
        final g = genre.trim();
        if (g.isEmpty) continue;
        genreCounts[g] = (genreCounts[g] ?? 0) + 1;
      }
    }
    final topGenres = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in topGenres.take(6)) {
      if (entry.value < 2) continue;
      result.add(
        MovieCollection(
          id: 'smart_genre_${entry.key}',
          kind: CollectionKind.smartGenre,
          name: entry.key,
          iconKey: 'theaters',
          smartValue: entry.key,
          memberCount: entry.value,
          previewPosters: await _smartPreviewPosters(
            CollectionKind.smartGenre,
            entry.key,
          ),
        ),
      );
    }

    // 年代
    final decadeCounts = <int, int>{};
    final yearRows = await _db.query(_moviesTable, columns: const ['year']);
    for (final row in yearRows) {
      final year = int.tryParse(
        RegExp(r'\d{4}').firstMatch(row['year']?.toString() ?? '')?.group(0) ??
            '',
      );
      if (year == null) continue;
      final decade = (year ~/ 10) * 10;
      decadeCounts[decade] = (decadeCounts[decade] ?? 0) + 1;
    }
    final decades = decadeCounts.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final decade in decades) {
      if ((decadeCounts[decade] ?? 0) < 2) continue;
      result.add(
        MovieCollection(
          id: 'smart_decade_$decade',
          kind: CollectionKind.smartDecade,
          name: '${decade}s',
          iconKey: 'nights_stay',
          smartValue: decade.toString(),
          memberCount: decadeCounts[decade] ?? 0,
          previewPosters: await _smartPreviewPosters(
            CollectionKind.smartDecade,
            decade.toString(),
          ),
        ),
      );
    }

    // 地区（按单个地区拆分；如“中国台湾/日本”会同时计入两个地区）
    final regionCounts = <String, int>{};
    final regionRows = await _db.query(_moviesTable, columns: const ['region']);
    for (final row in regionRows) {
      final raw = row['region']?.toString() ?? '';
      for (final region in _splitRegionFacets(raw)) {
        regionCounts[region] = (regionCounts[region] ?? 0) + 1;
      }
    }
    final topRegions = regionCounts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in topRegions.take(6)) {
      result.add(
        MovieCollection(
          id: 'smart_region_${entry.key}',
          kind: CollectionKind.smartRegion,
          name: entry.key,
          iconKey: 'public',
          smartValue: entry.key,
          memberCount: entry.value,
          previewPosters: await _smartPreviewPosters(
            CollectionKind.smartRegion,
            entry.key,
          ),
        ),
      );
    }

    // 导演（取片数 >=2 的前 6 个）
    final directorCounts = <String, int>{};
    final directorRows = await _db.query(
      _moviesTable,
      columns: const ['director'],
    );
    for (final row in directorRows) {
      final raw = row['director']?.toString() ?? '';
      for (final name in raw.split(RegExp(r'\s*/\s*'))) {
        final d = name.trim();
        if (d.isEmpty) continue;
        directorCounts[d] = (directorCounts[d] ?? 0) + 1;
      }
    }
    final topDirectors =
        directorCounts.entries.where((e) => e.value >= 2).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in topDirectors.take(6)) {
      result.add(
        MovieCollection(
          id: 'smart_director_${entry.key}',
          kind: CollectionKind.smartDirector,
          name: entry.key,
          iconKey: 'local_movies',
          smartValue: entry.key,
          memberCount: entry.value,
          previewPosters: await _smartPreviewPosters(
            CollectionKind.smartDirector,
            entry.key,
          ),
        ),
      );
    }

    return result;
  }

  /// 智能合集成员影片 id。
  Future<List<String>> querySmartCollectionMemberIds(
    CollectionKind kind,
    String value,
  ) async {
    _ensureInitialized();
    if (kind == CollectionKind.smartRegion) {
      return _querySmartRegionMemberIds(value);
    }
    final clause = _smartWhereClause(kind, value);
    if (clause == null) return const [];
    final rows = await _db.rawQuery(
      'SELECT id FROM $_moviesTable WHERE ${clause.where} ORDER BY created_at DESC',
      clause.whereArgs,
    );
    return rows
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<List<String>> _smartPreviewPosters(
    CollectionKind kind,
    String value,
  ) async {
    if (kind == CollectionKind.smartRegion) {
      return _querySmartRegionPreviewPosters(value);
    }
    final clause = _smartWhereClause(kind, value);
    if (clause == null) return const [];
    final rows = await _db.rawQuery(
      "SELECT poster FROM $_moviesTable WHERE ${clause.where} AND poster != '' ORDER BY created_at DESC LIMIT 4",
      clause.whereArgs,
    );
    return rows
        .map((row) => row['poster']?.toString() ?? '')
        .where((p) => p.isNotEmpty)
        .toList();
  }

  _SqlClause? _smartWhereClause(CollectionKind kind, String value) {
    switch (kind) {
      case CollectionKind.smartGenre:
        // genre_json 为 JSON 数组字符串，用 LIKE 匹配带引号的值
        return _SqlClause(
          where: "genre_json LIKE ? ESCAPE '\\'",
          whereArgs: ['%"${escapeSqlLike(value)}"%'],
        );
      case CollectionKind.smartDirector:
        return _SqlClause(
          where: "director LIKE ? ESCAPE '\\'",
          whereArgs: ['%${escapeSqlLike(value)}%'],
        );
      case CollectionKind.smartDecade:
        final decade = int.tryParse(value);
        if (decade == null) return null;
        return _SqlClause(
          where:
              "CAST(substr(year, 1, 4) AS INTEGER) >= ? AND CAST(substr(year, 1, 4) AS INTEGER) < ?",
          whereArgs: [decade, decade + 10],
        );
      case CollectionKind.smartRegion:
        return null;
      case CollectionKind.manual:
        return null;
    }
  }

  Future<List<String>> _querySmartRegionMemberIds(String value) async {
    final rows = await _db.query(
      _moviesTable,
      columns: const ['id', 'region'],
      orderBy: 'created_at DESC',
    );
    return rows
        .where(
          (row) => _splitRegionFacets(
            row['region']?.toString() ?? '',
          ).contains(value),
        )
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<List<String>> _querySmartRegionPreviewPosters(String value) async {
    final rows = await _db.query(
      _moviesTable,
      columns: const ['poster', 'region'],
      where: "poster != ''",
      orderBy: 'created_at DESC',
    );
    return rows
        .where(
          (row) => _splitRegionFacets(
            row['region']?.toString() ?? '',
          ).contains(value),
        )
        .map((row) => row['poster']?.toString() ?? '')
        .where((poster) => poster.isNotEmpty)
        .take(4)
        .toList();
  }

  MovieCollection _collectionFromDbMap(
    Map<String, Object?> row, {
    int memberCount = 0,
    List<String> previewPosters = const [],
  }) {
    return MovieCollection(
      id: row['id']?.toString() ?? '',
      kind: CollectionKind.manual,
      name: row['name']?.toString() ?? '',
      iconKey: row['icon_key']?.toString() ?? 'collections',
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      memberCount: memberCount,
      previewPosters: previewPosters,
    );
  }

  // ========== 标签 ==========

  Future<List<MovieTag>> queryAllTags() async {
    _ensureInitialized();
    final rows = await _db.query(
      _tagsTable,
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
    );
    return rows.map(_tagFromDbMap).toList();
  }

  Future<MovieTag> addTag(MovieTag tag) async {
    _ensureInitialized();
    final stored = tag.copyWith(
      id: tag.id.isNotEmpty
          ? tag.id
          : 'tag_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(4)}',
    );
    await _db.insert(_tagsTable, _stamp({
      'id': stored.id,
      'name': stored.name,
      'color_value': stored.colorValue,
      'created_at': stored.createdAt.toIso8601String(),
    }), conflictAlgorithm: ConflictAlgorithm.replace);
    return stored;
  }

  Future<void> updateTag(MovieTag tag) async {
    _ensureInitialized();
    await _db.update(
      _tagsTable,
      {'name': tag.name, 'color_value': tag.colorValue},
      where: 'id = ?',
      whereArgs: [tag.id],
    );
  }

  Future<void> deleteTag(String tagId) async {
    _ensureInitialized();
    await _db.transaction((txn) async {
      await txn.delete(
        _movieTagsTable,
        where: 'tag_id = ?',
        whereArgs: [tagId],
      );
      await txn.delete(_tagsTable, where: 'id = ?', whereArgs: [tagId]);
    });
  }

  /// 某影片挂的标签。
  Future<List<MovieTag>> queryTagsForMovie(String movieId) async {
    _ensureInitialized();
    final rows = await _db.rawQuery(
      '''
      SELECT t.* FROM $_movieTagsTable mt
      JOIN $_tagsTable t ON t.id = mt.tag_id
      WHERE mt.movie_id = ?
        AND mt.deleted_at IS NULL
        AND t.deleted_at IS NULL
      ORDER BY t.created_at ASC
      ''',
      [movieId],
    );
    return rows.map(_tagFromDbMap).toList();
  }

  Future<void> setMovieTags(String movieId, Iterable<String> tagIds) async {
    _ensureInitialized();
    final batch = _db.batch();
    batch.delete(_movieTagsTable, where: 'movie_id = ?', whereArgs: [movieId]);
    for (final tagId in tagIds) {
      batch.insert(_movieTagsTable, _stamp({
        'movie_id': movieId,
        'tag_id': tagId,
      }), conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// 命中任一标签的影片 id（用于标签抽片）。
  Future<List<String>> queryMovieIdsByTags(Iterable<String> tagIds) async {
    _ensureInitialized();
    final ids = tagIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.rawQuery(
      'SELECT DISTINCT movie_id FROM $_movieTagsTable WHERE tag_id IN ($placeholders)',
      ids,
    );
    return rows
        .map((row) => row['movie_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  MovieTag _tagFromDbMap(Map<String, Object?> row) {
    return MovieTag(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      colorValue:
          (row['color_value'] as num?)?.toInt() ?? MovieTag.palette.first,
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  // ========== 备份 / 恢复专用接口 ==========

  /// 在一个事务里读完所有需要备份的表，返回彼此一致的快照。
  ///
  /// 之前的实现连续 4 次 `await getAll*ForBackup()`，都不在同一事务里：
  /// 读取过程中用户保存一次数据，快照就会自相矛盾（例如会话指向还没读到的
  /// 影片）。这种坏快照一旦上传，另一台设备会因为「关联的影片缺失，已停止
  /// 覆盖」而永远无法恢复，同步直接卡死。
  ///
  /// 事务里读到的是同一个数据库版本视图，因此每一行都互相自洽。
  Future<BackupBundle> readBackupBundle() async {
    _ensureInitialized();
    return _db.transaction((txn) async {
      // 必须过滤墓碑行（deleted_at IS NOT NULL）。
      //
      // 删除是软删除：只给 deleted_at 打时间戳，行还留在表里。
      // 如果这里不过滤，用户删掉的影片会原封不动进备份——
      // 表现就是「片库显示 94 部，备份却说 116 部」，
      // 而且上传云端后，那些本该消失的条目会跟着同步到别的设备。
      //
      // 视图 v_movie_state 也做同样的过滤，但它是 view 不是 table，
      // 这里直接查表所以要自己带条件。
      //
      // 注意：draw_records 表没有 deleted_at 列（抽片记录不做软删除），
      // 因此它不加这个条件。其余可同步表都有。
      const alive = 'deleted_at IS NULL';

      final movieRows = await txn.query(
        _moviesTable,
        where: alive,
        orderBy: 'created_at ASC',
      );
      final drawRows = await txn.query(
        _drawRecordsTable,
        orderBy: 'drawn_at ASC',
      );
      final sessionRows = await txn.query(
        _viewingSessionsTable,
        where: alive,
        orderBy: 'COALESCE(watched_at_utc, -1) ASC, watched_at ASC',
      );
      final collectionsAndTags = <String, List<Map<String, Object?>>>{
        'collections': await txn.query(_collectionsTable, where: alive),
        'collectionMembers': await txn.query(
          _collectionMembersTable,
          where: alive,
        ),
        'tags': await txn.query(_tagsTable, where: alive),
        // 关联表也有 deleted_at，直接用它过滤。
        // 另外再排除指向已删除影片/标签的行，避免导出「归属对象已不存在」
        // 的孤儿关联——那类行导入后会被外键检查拦下。
        'movieTags': await txn.query(
          _movieTagsTable,
          where:
              '$alive '
              'AND movie_id IN (SELECT id FROM $_moviesTable WHERE $alive) '
              'AND tag_id IN (SELECT id FROM $_tagsTable WHERE $alive)',
        ),
      };
      return BackupBundle(
        movies: movieRows.map(_movieFromDbMap).toList(growable: false),
        drawRecords: drawRows.map(_drawRecordFromDbMap).toList(growable: false),
        sessions: sessionRows.map(_sessionFromDbMap).toList(growable: false),
        collectionsAndTags: collectionsAndTags,
      );
    });
  }

  /// 在**同一个写事务**里完成「校验本地没变 + 整体替换」。
  ///
  /// 覆盖云端数据是不可撤回操作。原先的做法是先算校验值、再另开事务替换，
  /// 两步之间的窗口期里用户保存的内容会被无声覆盖。这里把复查与替换放进
  /// 同一个事务：只要指纹对不上就抛 [StaleLocalDataException]，数据库保持原样。
  ///
  /// [expectedFingerprint] 由 [localFingerprint] 在覆盖前取得。
  Future<void> replaceBackupDataIfUnchanged({
    required String expectedFingerprint,
    required List<Movie> movies,
    required List<DrawRecord> drawRecords,
    required List<ViewingSession> sessions,
    required Map<String, List<Map<String, Object?>>> tableData,
  }) async {
    _ensureInitialized();
    await _db.transaction((txn) async {
      final current = await _fingerprintInTxn(txn);
      if (current != expectedFingerprint) {
        throw const StaleLocalDataException();
      }
      await _replaceAllInTxn(
        txn,
        movies: movies,
        drawRecords: drawRecords,
        sessions: sessions,
        tableData: tableData,
      );
    });
  }

  /// 本地数据指纹：各表行数 + 关键时间列的最大值。
  ///
  /// 只用来判断「这几张表自上次读数以来有没有变过」，不必把几 MB 内容读进事务，
  /// 因此可以和替换动作放进同一把写锁里做。覆盖前后各取一次即可发现任何写入。
  Future<String> localFingerprint() async {
    _ensureInitialized();
    return _fingerprintInTxn(_db);
  }

  Future<String> _fingerprintInTxn(DatabaseExecutor txn) async {
    final parts = <String>[];
    for (final (table, column) in const [
      (_moviesTable, 'created_at'),
      (_drawRecordsTable, 'drawn_at'),
      (_viewingSessionsTable, 'watched_at'),
      (_collectionsTable, 'created_at'),
      (_tagsTable, 'created_at'),
      (_collectionMembersTable, 'added_at'),
    ]) {
      final rows = await txn.rawQuery(
        'SELECT COUNT(*) AS c, MAX($column) AS m FROM $table',
      );
      final count = (rows.first['c'] as num?)?.toInt() ?? 0;
      final latest = rows.first['m']?.toString() ?? '';
      parts.add('$table:$count:$latest');
    }
    // movie_tags 没有时间列，只数行数。
    final tags = await txn.rawQuery(
      'SELECT COUNT(*) AS c FROM $_movieTagsTable',
    );
    parts.add('movieTags:${(tags.first['c'] as num?)?.toInt() ?? 0}');
    return parts.join('|');
  }

  Future<void> _replaceAllInTxn(
    DatabaseExecutor txn, {
    required List<Movie> movies,
    required List<DrawRecord> drawRecords,
    required List<ViewingSession> sessions,
    required Map<String, List<Map<String, Object?>>> tableData,
  }) async {
    for (final table in const [
      _movieTagsTable,
      _collectionMembersTable,
      _tagsTable,
      _collectionsTable,
      _drawRecordsTable,
      _viewingSessionsTable,
      _moviesTable,
    ]) {
      await txn.delete(table);
    }

    final batch = txn.batch();
    for (final movie in movies) {
      batch.insert(_moviesTable, _stamp(_movieToDbMap(movie)));
    }
    for (final record in drawRecords) {
      batch.insert(_drawRecordsTable, _drawRecordToDbMap(record));
    }
    for (final session in sessions) {
      batch.insert(_viewingSessionsTable, _stamp(_sessionToDbMap(session)));
    }
    for (final table in const [
      _collectionsTable,
      _collectionMembersTable,
      _tagsTable,
      _movieTagsTable,
    ]) {
      final rows =
          tableData[table == _collectionsTable
              ? 'collections'
              : table == _collectionMembersTable
              ? 'collectionMembers'
              : table == _tagsTable
              ? 'tags'
              : 'movieTags'];
      for (final row in rows ?? const <Map<String, Object?>>[]) {
        batch.insert(table, _stamp(Map<String, Object?>.from(row)));
      }
    }
    await batch.commit(noResult: true);
  }

  Future<List<Movie>> getAllMoviesForBackup() async {
    _ensureInitialized();
    final rows = await _db.query(_moviesTable, orderBy: 'created_at ASC');
    return rows.map(_movieFromDbMap).toList();
  }

  Future<List<DrawRecord>> getAllDrawRecordsForBackup() async {
    _ensureInitialized();
    final rows = await _db.query(_drawRecordsTable, orderBy: 'drawn_at ASC');
    return rows.map(_drawRecordFromDbMap).toList();
  }

  /// 直接写入影片（跳过重复id检查），仅供备份恢复使用
  Future<void> addMovieDirectly(Movie movie) async {
    _ensureInitialized();
    await _db.insert(
      _moviesTable,
      _stamp(_movieToDbMap(movie)),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 仅当记录不存在时插入，返回是否实际写入
  Future<bool> addDrawRecordIfNotExists(DrawRecord record) async {
    _ensureInitialized();
    final existing = await _db.query(
      _drawRecordsTable,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [record.id],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    await _db.insert(
      _drawRecordsTable,
      _drawRecordToDbMap(record),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return true;
  }

  // ========== 映射 ==========

  _SqlClause _buildMovieWhereClause({
    required String searchQuery,
    required bool watchedOnly,
    required bool unwatchedOnly,
  }) {
    final conditions = <String>[];
    final args = <Object?>[];

    // 墓碑行永不出现在任何面向用户的查询里。
    // 这条必须无条件生效，因此放在最前面，让「已删除」的影片在
    // 片库、搜索、计数、抽片候选里统统消失。
    //
    // 用别名 `m` 而不是表名：三个调用方（countMovies / queryMovies /
    // queryMovieIds）都以 `FROM movies m` 起手，SQLite 一旦起了别名
    // 就不再接受用原表名限定列，写成 `movies.deleted_at` 会直接报
    // 「no such column」。
    conditions.add('m.deleted_at IS NULL');

    if (watchedOnly) {
      conditions.add(_movieWatchedPredicate);
    } else if (unwatchedOnly) {
      conditions.add('NOT $_movieWatchedPredicate');
    }

    final normalizedQuery = searchQuery.trim().toLowerCase();
    if (normalizedQuery.isNotEmpty) {
      const fields = [
        'LOWER(m.title)',
        'LOWER(m.director)',
        'LOWER(m.cast_text)',
      ];
      final like = '%${escapeSqlLike(normalizedQuery)}%';
      conditions.add(
        '(${fields.map((field) => "$field LIKE ? ESCAPE '\\'").join(' OR ')})',
      );
      args.addAll(List<Object?>.filled(fields.length, like));
    }

    if (conditions.isEmpty) {
      return const _SqlClause();
    }

    return _SqlClause(where: conditions.join(' AND '), whereArgs: args);
  }

  Map<String, Object?> _movieToDbMap(Movie movie) {
    return {
      'id': movie.id,
      'title': movie.title,
      'year': movie.year,
      'subject_type': movie.subjectType.value,
      'director': movie.director,
      'author': movie.author,
      'cast_text': movie.cast,
      'rating': movie.rating,
      'genre_json': jsonEncode(movie.genre),
      'region': movie.region,
      'summary': movie.summary,
      'published_at': movie.publishedAt,
      'duration_text': movie.durationText,
      'duration_minutes': movie.durationMinutes,
      'episodes_json': jsonEncode(
        movie.episodes.map((episode) => episode.toJson()).toList(),
      ),
      'poster': movie.poster,
      'douban_url': movie.doubanUrl,
      'watched': movie.watched ? 1 : 0,
      'watched_at': movie.watchedAt?.toIso8601String(),
      'user_rating': movie.userRating,
      'user_review': movie.userReview,
      'poster_color': movie.posterColor,
      'created_at': movie.createdAt.toIso8601String(),
    };
  }

  Movie _movieFromDbMap(Map<String, Object?> row) {
    // watched / watched_at 优先取统一派生字段，缺失时回退到物理列。
    final hasDerivedWatched = row.containsKey('derived_watched');
    final bool watched = hasDerivedWatched
        ? ((row['derived_watched'] as num?)?.toInt() ?? 0) == 1
        : (row['watched'] as int? ?? 0) == 1;
    final watchedAtRaw = row.containsKey('derived_watched_at')
        ? row['derived_watched_at']
        : row['watched_at'];

    return Movie(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      year: row['year']?.toString() ?? '',
      subjectType: MovieSubjectType.fromValue(row['subject_type']?.toString()),
      director: row['director']?.toString() ?? '',
      author: row['author']?.toString() ?? '',
      cast: row['cast_text']?.toString() ?? '',
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      genre: _decodeStringList(row['genre_json']?.toString()),
      region: row['region']?.toString() ?? '',
      summary: row['summary']?.toString() ?? '',
      publishedAt: row['published_at']?.toString() ?? '',
      durationText: row['duration_text']?.toString() ?? '',
      durationMinutes: row['duration_minutes'] as int?,
      episodes: _decodeEpisodes(row['episodes_json']?.toString()),
      poster: row['poster']?.toString() ?? '',
      doubanUrl: row['douban_url']?.toString() ?? '',
      watched: watched,
      watchedAt: watchedAtRaw != null
          ? DateTime.tryParse(watchedAtRaw.toString())
          : null,
      userRating: (row['user_rating'] as num?)?.toDouble(),
      userReview: row['user_review']?.toString(),
      posterColor: (row['poster_color'] as num?)?.toInt(),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> _drawRecordToDbMap(DrawRecord record) {
    return {
      'id': record.id,
      'movie_id': record.movieId,
      'movie_title': record.movieTitle,
      'movie_poster': record.moviePoster,
      'seed': record.seed,
      'candidate_count': record.candidateCount,
      'outcome': record.outcome.value,
      'drawn_at': record.drawnAt.toIso8601String(),
    };
  }

  DrawRecord _drawRecordFromDbMap(Map<String, Object?> row) {
    return DrawRecord(
      id: row['id']?.toString() ?? '',
      movieId: row['movie_id']?.toString() ?? '',
      movieTitle: row['movie_title']?.toString() ?? '',
      moviePoster: row['movie_poster']?.toString() ?? '',
      seed: row['seed'] as int? ?? 0,
      candidateCount: row['candidate_count'] as int? ?? 0,
      outcome: DrawOutcome.fromValue(row['outcome']?.toString()),
      drawnAt:
          DateTime.tryParse(row['drawn_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((item) => item.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  List<MovieEpisode> _decodeEpisodes(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((json) => MovieEpisode.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<List<T>> _chunkList<T>(List<T> values, int chunkSize) {
    final chunks = <List<T>>[];
    for (int start = 0; start < values.length; start += chunkSize) {
      final end = min(start + chunkSize, values.length);
      chunks.add(values.sublist(start, end));
    }
    return chunks;
  }

  // ========== 工具方法 ==========

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final buffer = StringBuffer();
    final random = Random();
    for (int index = 0; index < length; index++) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  String _generateRandomNumber(int length) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final mod = pow(10, length) as int;
    return (timestamp % mod).toString().padLeft(length, '0');
  }
}

class DuplicateMovieException implements Exception {
  final Movie existingMovie;
  DuplicateMovieException(this.existingMovie);

  @override
  String toString() => '影片《${existingMovie.title}》已在片库中';
}

class _SqlClause {
  final String? where;
  final List<Object?>? whereArgs;

  const _SqlClause({this.where, this.whereArgs});
}

/// 片库筛选可选值的汇总，供筛选面板构建可选项。
class MovieFacets {
  final List<String> genres;
  final List<String> regions;
  final int? minYear;
  final int? maxYear;
  final int? maxDurationMinutes;

  const MovieFacets({
    this.genres = const [],
    this.regions = const [],
    this.minYear,
    this.maxYear,
    this.maxDurationMinutes,
  });

  bool get isEmpty =>
      genres.isEmpty &&
      regions.isEmpty &&
      minYear == null &&
      maxYear == null &&
      maxDurationMinutes == null;
}
