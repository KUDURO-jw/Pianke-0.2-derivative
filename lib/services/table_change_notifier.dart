// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/services/storage_service.dart';

/// 订阅数据库变更并在防抖后通知界面重新查询。
///
/// T5b 的目标是替掉 `MovieProvider` 里那 4 套手写「版本计数器」
/// （`_libraryRefreshRevision` 等）：它们各自丢弃过期异步结果，页面返回后
/// 还得手动 `refresh()`，漏一处界面就是旧的。
///
/// 这里换个方向：数据库自己说「这几张表变了」，界面在**安静 80ms 之后**
/// 重新查询一次。为什么防抖：一次保存往往连带动多张表（影片 + 会话 +
/// 合集成员），不防抖就会连查三次，滚动时还会和用户操作抢帧。
///
/// ```dart
/// final changes = TableChangeNotifier(StorageService());
/// changes.addListener(() => provider.refreshLibrary());
/// ```
class TableChangeNotifier extends ChangeNotifier {
  /// 安静多久之后才认为「这一批改动结束了」。
  final Duration debounce;

  /// 只关心这些表的变更；为空表示全部。
  final Set<String>? watchTables;

  final StorageService _storage;
  StreamSubscription<Set<String>>? _subscription;
  Timer? _timer;
  bool _disposed = false;

  /// 上一批（防抖后）被改动的表，便于调试与测试。
  Set<String> lastChangedTables = const {};

  /// 收到变更通知的累计次数（防抖前），用于测试「合并成一次」。
  int rawNotificationCount = 0;

  TableChangeNotifier(
    this._storage, {
    this.debounce = Motion.debounce,
    this.watchTables,
  }) {
    _subscription = _storage.tableChanges.listen(_onTablesChanged);
  }

  void _onTablesChanged(Set<String> tables) {
    if (_disposed) return;
    if (watchTables != null && !tables.any(watchTables!.contains)) return;
    rawNotificationCount++;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      if (_disposed) return;
      lastChangedTables = Set<String>.unmodifiable(tables);
      notifyListeners();
    });
  }

  /// 手动触发一次（例如从设置页回来需要强制刷新）。
  void triggerNow() {
    _timer?.cancel();
    lastChangedTables = const {'__manual__'};
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
