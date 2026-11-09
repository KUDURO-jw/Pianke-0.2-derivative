// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:io';

import 'package:random_movie/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 当前生产数据库版本（从实现读取，避免测试里另抄一份数字而漂移）。
const int currentDatabaseVersion = StorageService.databaseVersionForTest;

/// 真实 SQLite 的测试底座。
///
/// 走与生产完全相同的打开路径（同样的 onCreate / onUpgrade / onDowngrade），
/// 只把 `getDatabasesPath()` 换成临时目录里的真实文件，让 SQL 语句、
/// LIKE 转义、迁移链真正进入测试覆盖——此前这些是空白，SQL 写错测试也发现不了。
///
/// 刻意用**独立临时文件**而不是 `:memory:`：sqflite 的工厂会按路径缓存句柄，
/// 多个用例共用 `:memory:` 会拿到同一个库；而且内存库在关闭瞬间就销毁，
/// 没法模拟「先写旧版数据、再重新打开升级」这一真实迁移路径。
///
/// ```dart
/// final storage = await openTestStorage();
/// addTearDown(storage.closeForTest);
/// ```
///
/// 模拟旧版本升级：先按 [version] 建库、用 [seed] 写入旧版夹具，
/// 关闭后再用当前版本打开，从而真实触发 onUpgrade。
Future<StorageService> openTestStorage({
  int? version,
  Future<void> Function(Database db)? seed,
  String? path,
}) async {
  sqfliteFfiInit();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final factory = databaseFactoryFfi;
  final dbPath = path ?? newTestDbPath();

  if (seed != null) {
    final seedDb = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: version ?? 1),
    );
    try {
      await seed(seedDb);
    } finally {
      await seedDb.close();
    }
  }

  final service = StorageService.forTesting();
  await service.init(dbPath: dbPath, factory: factory);
  return service;
}

/// 每个用例一个独立库文件，互不干扰。
String newTestDbPath() =>
    '${Directory.systemTemp.createTempSync('pianke_test_').path}/test.db';
