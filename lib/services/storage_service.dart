import 'dart:convert';
import 'dart:math' show Random, min, max, pow;

import 'package:path/path.dart' as path;
import 'package:random_movie/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// 本地存储服务
class StorageService {
  static const String _userIdKey = 'movie_app_user_id';
  static const String _userNameKey = 'movie_app_user_name';
  static const String _legacyMoviesKey = 'movie_app_local_movies';
  static const String _legacyDrawHistoryKey = 'movie_app_draw_history';
  static const String _migrationFlagKey = 'movie_app_storage_migrated_v2';
  static const String _themeModeKey = 'movie_app_theme_mode';
  static const String _databaseName = 'random_movie.db';
  static const int _databaseVersion = 7;
  static const int _maxDrawHistory = 100;
  static const String _moviesTable = 'movies';
  static const String _drawRecordsTable = 'draw_records';
  static const String _viewingSessionsTable = 'viewing_sessions';
  static const String _collectionsTable = 'collections';
  static const String _collectionMembersTable = 'collection_members';
  static const String _tagsTable = 'tags';
  static const String _movieTagsTable = 'movie_tags';

  static const String _movieWatchedPredicate =
      '(m.watched = 1 OR EXISTS(SELECT 1 FROM $_viewingSessionsTable vs WHERE vs.movie_id = m.id))';

  /// 派生字段：电影是否看过（显式状态或存在观影会话）
  static const String _derivedWatchedExpr =
      '$_movieWatchedPredicate AS derived_watched';

  /// 派生字段：最近一次观看时间，兼容没有会话的显式已看状态。
  static const String _derivedWatchedAtExpr =
      'COALESCE((SELECT MAX(vs.watched_at) FROM $_viewingSessionsTable vs WHERE vs.movie_id = m.id), m.watched_at) AS derived_watched_at';

  late SharedPreferences _prefs;
  late Database _db;
  bool _initialized = false;

  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Future<void> init() async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      path.join(dbPath, _databaseName),
      version: _databaseVersion,
      onCreate: (db, _) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _upgradeDatabase(db, oldVersion, newVersion);
      },
    );
    _initialized = true;
    await _migrateLegacyData();
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
  }

  Future<void> _createViewingSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_viewingSessionsTable (
        id TEXT PRIMARY KEY,
        movie_id TEXT NOT NULL,
        watched_at TEXT NOT NULL,
        mood TEXT NOT NULL DEFAULT 'none',
        watched_with TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        is_rewatch INTEGER NOT NULL DEFAULT 0,
        rating REAL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_sessions_movie ON $_viewingSessionsTable(movie_id, watched_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_sessions_watched_at ON $_viewingSessionsTable(watched_at DESC)',
    );
  }

  Future<void> _createCollectionAndTagTables(Database db) async {
    await db.execute('''
      CREATE TABLE $_collectionsTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon_key TEXT NOT NULL DEFAULT 'collections',
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $_collectionMembersTable (
        collection_id TEXT NOT NULL,
        movie_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
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
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $_movieTagsTable (
        movie_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
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

  /// v4 迁移：为现有 watched=1 的电影各生成一条默认观影会话，
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
            _movieToDbMap(movie),
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

  // ========== 电影 ==========

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
      'SELECT COUNT(*) AS count FROM $_moviesTable m${clause.where == null ? '' : ' WHERE ${clause.where}'}',
      clause.whereArgs,
    );
    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  /// 统一的影片读取：附带 watched / watched_at 派生字段。
  String _movieSelect({
    String? where,
    String? orderBy,
    bool withLimit = false,
  }) {
    final buffer = StringBuffer(
      'SELECT m.*, $_derivedWatchedExpr, $_derivedWatchedAtExpr FROM $_moviesTable m',
    );
    if (where != null) buffer.write(' WHERE $where');
    if (orderBy != null) buffer.write(' ORDER BY $orderBy');
    if (withLimit) buffer.write(' LIMIT ? OFFSET ?');
    return buffer.toString();
  }

  /// 已看排序：最近观看优先；未看排序：未看在前，再按入库时间。
  String _movieOrderBy({required bool watchedOnly}) {
    return watchedOnly
        ? 'derived_watched_at DESC, m.created_at DESC'
        : 'derived_watched ASC, m.created_at DESC';
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
      FROM $_moviesTable m
      WHERE EXISTS(
        SELECT 1 FROM $_viewingSessionsTable vs
        WHERE vs.movie_id = m.id AND vs.watched_at >= ? AND vs.watched_at < ?
      )
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
      'SELECT m.id, $_derivedWatchedExpr, $_derivedWatchedAtExpr '
      'FROM $_moviesTable m'
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
      '${_movieSelect(where: 'm.id = ?')} LIMIT 1',
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

    final rows = await _db.rawQuery(_movieSelect(where: "m.douban_url <> ''"));
    for (final row in rows) {
      final movie = _movieFromDbMap(row);
      if (_extractDoubanSubjectId(movie.doubanUrl) == normalizedSubjectId) {
        return movie;
      }
    }
    return null;
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
        _movieSelect(where: 'm.id IN ($placeholders)'),
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

    await _db.insert(
      _moviesTable,
      _movieToDbMap(newMovie),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return newMovie;
  }

  String? _extractDoubanSubjectId(String url) {
    final match = RegExp(r'(?:subject|movie)/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  Future<void> updateMovie(Movie updatedMovie) async {
    _ensureInitialized();
    await _db.update(
      _moviesTable,
      _movieToDbMap(updatedMovie),
      where: 'id = ?',
      whereArgs: [updatedMovie.id],
    );
  }

  Future<void> deleteMovie(String movieId) async {
    _ensureInitialized();
    await _db.delete(_moviesTable, where: 'id = ?', whereArgs: [movieId]);
    await _db.delete(
      _viewingSessionsTable,
      where: 'movie_id = ?',
      whereArgs: [movieId],
    );
    await _db.delete(
      _collectionMembersTable,
      where: 'movie_id = ?',
      whereArgs: [movieId],
    );
    await _db.delete(
      _movieTagsTable,
      where: 'movie_id = ?',
      whereArgs: [movieId],
    );
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

  /// 某部影片的所有观影会话，按观看时间倒序。
  Future<List<ViewingSession>> querySessionsByMovie(String movieId) async {
    _ensureInitialized();
    final rows = await _db.query(
      _viewingSessionsTable,
      where: 'movie_id = ?',
      whereArgs: [movieId],
      orderBy: 'watched_at DESC, created_at DESC',
    );
    return rows.map(_sessionFromDbMap).toList();
  }

  /// 某月所有观影会话，按观看时间倒序。
  Future<List<ViewingSession>> querySessionsByMonth(DateTime month) async {
    _ensureInitialized();
    final firstDay = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    final rows = await _db.query(
      _viewingSessionsTable,
      where: 'watched_at >= ? AND watched_at < ?',
      whereArgs: [firstDay.toIso8601String(), nextMonth.toIso8601String()],
      orderBy: 'watched_at DESC, created_at DESC',
    );
    return rows.map(_sessionFromDbMap).toList();
  }

  /// 分页查询全部观影会话（时间线），按观看时间倒序。
  Future<List<ViewingSession>> querySessions({
    required int limit,
    required int offset,
  }) async {
    _ensureInitialized();
    final rows = await _db.query(
      _viewingSessionsTable,
      orderBy: 'watched_at DESC, created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_sessionFromDbMap).toList();
  }

  Future<int> countSessions() async {
    _ensureInitialized();
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_viewingSessionsTable',
    );
    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<bool> movieHasSession(String movieId) async {
    _ensureInitialized();
    final rows = await _db.query(
      _viewingSessionsTable,
      columns: const ['id'],
      where: 'movie_id = ?',
      whereArgs: [movieId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<ViewingSession> addSession(ViewingSession session) async {
    _ensureInitialized();
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
      _sessionToDbMap(session),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> deleteSession(String sessionId) async {
    _ensureInitialized();
    await _db.delete(
      _viewingSessionsTable,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 删除某部影片的全部会话（用于「取消已看」）。
  Future<void> deleteSessionsByMovie(String movieId) async {
    _ensureInitialized();
    await _db.delete(
      _viewingSessionsTable,
      where: 'movie_id = ?',
      whereArgs: [movieId],
    );
  }

  /// 备份用：全部会话。
  Future<List<ViewingSession>> getAllSessionsForBackup() async {
    _ensureInitialized();
    final rows = await _db.query(
      _viewingSessionsTable,
      orderBy: 'watched_at ASC',
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
      _sessionToDbMap(session),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return true;
  }

  // ---- 合集 / 标签备份（导出为原始行，按表恢复）----

  Future<Map<String, List<Map<String, Object?>>>>
  getCollectionsAndTagsForBackup() async {
    _ensureInitialized();
    return {
      'collections': await _db.query(_collectionsTable),
      'collectionMembers': await _db.query(_collectionMembersTable),
      'tags': await _db.query(_tagsTable),
      'movieTags': await _db.query(_movieTagsTable),
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
          Map<String, Object?>.from(raw),
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
        batch.insert(_moviesTable, _movieToDbMap(movie));
      }
      for (final record in drawRecords) {
        batch.insert(_drawRecordsTable, _drawRecordToDbMap(record));
      }
      for (final session in sessions) {
        batch.insert(_viewingSessionsTable, _sessionToDbMap(session));
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
          batch.insert(table, row);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<ViewingStats> queryViewingStats() async {
    _ensureInitialized();

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);

    final totalCount = await countSessions();
    if (totalCount == 0) return const ViewingStats();

    final monthlyResult = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_viewingSessionsTable WHERE watched_at >= ? AND watched_at < ?',
      [monthStart.toIso8601String(), nextMonth.toIso8601String()],
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

    // 连续观影天数：取所有观看日期去重，从今天/昨天往前数
    final dateRows = await _db.rawQuery(
      'SELECT DISTINCT substr(watched_at, 1, 10) AS day FROM $_viewingSessionsTable',
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
    );
  }

  // ========== 合集 ==========

  /// 全部手动合集，附带成员数与最多 4 张预览海报，按 sort_order 排序。
  Future<List<MovieCollection>> queryCollections() async {
    _ensureInitialized();
    final rows = await _db.query(
      _collectionsTable,
      orderBy: 'sort_order ASC, created_at ASC',
    );

    final result = <MovieCollection>[];
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final countResult = await _db.rawQuery(
        'SELECT COUNT(*) AS count FROM $_collectionMembersTable WHERE collection_id = ?',
        [id],
      );
      final count = (countResult.first['count'] as num?)?.toInt() ?? 0;
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
    await _db.insert(_collectionsTable, {
      'id': stored.id,
      'name': stored.name,
      'icon_key': stored.iconKey,
      'sort_order': stored.sortOrder,
      'created_at': stored.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    await _db.delete(
      _collectionsTable,
      where: 'id = ?',
      whereArgs: [collectionId],
    );
    await _db.delete(
      _collectionMembersTable,
      where: 'collection_id = ?',
      whereArgs: [collectionId],
    );
  }

  /// 合集成员影片 id（按 sort_order）。
  Future<List<String>> queryCollectionMemberIds(String collectionId) async {
    _ensureInitialized();
    final rows = await _db.query(
      _collectionMembersTable,
      columns: const ['movie_id'],
      where: 'collection_id = ?',
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
    await _db.insert(_collectionMembersTable, {
      'collection_id': collectionId,
      'movie_id': movieId,
      'sort_order': nextOrder,
      'added_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
      where: 'movie_id = ?',
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
          where: 'genre_json LIKE ?',
          whereArgs: ['%"$value"%'],
        );
      case CollectionKind.smartDirector:
        return _SqlClause(where: 'director LIKE ?', whereArgs: ['%$value%']);
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
    final rows = await _db.query(_tagsTable, orderBy: 'created_at ASC');
    return rows.map(_tagFromDbMap).toList();
  }

  Future<MovieTag> addTag(MovieTag tag) async {
    _ensureInitialized();
    final stored = tag.copyWith(
      id: tag.id.isNotEmpty
          ? tag.id
          : 'tag_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(4)}',
    );
    await _db.insert(_tagsTable, {
      'id': stored.id,
      'name': stored.name,
      'color_value': stored.colorValue,
      'created_at': stored.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    await _db.delete(_tagsTable, where: 'id = ?', whereArgs: [tagId]);
    await _db.delete(_movieTagsTable, where: 'tag_id = ?', whereArgs: [tagId]);
  }

  /// 某影片挂的标签。
  Future<List<MovieTag>> queryTagsForMovie(String movieId) async {
    _ensureInitialized();
    final rows = await _db.rawQuery(
      '''
      SELECT t.* FROM $_movieTagsTable mt
      JOIN $_tagsTable t ON t.id = mt.tag_id
      WHERE mt.movie_id = ?
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
      batch.insert(_movieTagsTable, {
        'movie_id': movieId,
        'tag_id': tagId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
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

  /// 直接写入电影（跳过重复id检查），仅供备份恢复使用
  Future<void> addMovieDirectly(Movie movie) async {
    _ensureInitialized();
    await _db.insert(
      _moviesTable,
      _movieToDbMap(movie),
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
      final like = '%$normalizedQuery%';
      conditions.add(
        '(${fields.map((field) => '$field LIKE ?').join(' OR ')})',
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
  String toString() => '电影《${existingMovie.title}》已在片库中';
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
