// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:random_movie/providers/app_notifier.dart';
import 'dart:math' as math;

import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/services.dart';

/// 抽奖历史状态管理
class DrawHistoryProvider extends AppNotifier {
  static const int pageSize = 20;

  final StorageService _storageService;

  List<DrawRecord> _records = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  int _revision = 0;
  bool _hasLoaded = false;
  String? _error;

  List<DrawRecord> get records => _records;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  DrawHistoryProvider({StorageService? storage})
    : _storageService = storage ?? StorageService();

  Future<void> ensureLoaded() async {
    if (_hasLoaded || _isLoading) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (isDisposed) return;
    final revision = ++_revision;
    _isLoadingMore = false;
    final shouldNotifyLoading =
        _hasLoaded || _records.isNotEmpty || _error != null;
    _isLoading = true;
    _error = null;
    if (shouldNotifyLoading) {
      notifyListeners();
    }

    try {
      final records = await _storageService.queryDrawRecords(
        limit: pageSize,
        offset: 0,
      );
      if (isDisposed || revision != _revision) return;
      _records = records;
      _page = 0;
      _hasMore = records.length == pageSize;
    } catch (error) {
      if (revision == _revision) _error = '加载失败: $error';
    } finally {
      if (revision == _revision) {
        _hasLoaded = true;
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    final revision = _revision;
    _error = null;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final nextPage = _page + 1;
      final records = await _storageService.queryDrawRecords(
        limit: pageSize,
        offset: nextPage * pageSize,
      );
      if (isDisposed || revision != _revision) return;
      if (records.isEmpty) {
        _hasMore = false;
      } else {
        _records = [..._records, ...records];
        _page = nextPage;
        _hasMore = records.length == pageSize;
      }
    } catch (error) {
      if (revision == _revision) _error = '加载更多失败: $error';
    } finally {
      if (revision == _revision) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> _reloadVisibleRecords() async {
    final revision = ++_revision;
    _isLoadingMore = false;
    final limit = math.max((_page + 1) * pageSize, pageSize);
    final results = await Future.wait<Object>([
      _storageService.queryDrawRecords(limit: limit, offset: 0),
      _storageService.countDrawRecords(),
    ]);
    if (isDisposed || revision != _revision) return;
    final records = results[0] as List<DrawRecord>;
    final total = results[1] as int;
    _records = records;
    _page = records.isEmpty ? 0 : ((records.length - 1) / pageSize).floor();
    _hasMore = records.length < total;
    notifyListeners();
  }

  /// 添加一条记录并刷新
  Future<void> addRecord(DrawRecord record) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _storageService.addDrawRecord(record);
      await _reloadVisibleRecords();
    } catch (error) {
      _error = '保存失败: $error';
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 更新某条记录的处理状态（就看这个 / 跳过）。
  Future<void> updateOutcome(String recordId, DrawOutcome outcome) async {
    try {
      await _storageService.updateDrawRecordOutcome(recordId, outcome);
      final index = _records.indexWhere((record) => record.id == recordId);
      if (index != -1) {
        _records = [..._records];
        _records[index] = _records[index].copyWith(outcome: outcome);
        notifyListeners();
      }
    } catch (error) {
      _error = '更新状态失败: $error';
      notifyListeners();
    }
  }

  /// 清空历史
  Future<void> clearAll() async {
    try {
      ++_revision;
      _isLoadingMore = false;
      _isLoading = true;
      _error = null;
      notifyListeners();
      await _storageService.clearDrawHistory();
      _records = [];
      _page = 0;
      _hasMore = false;
      notifyListeners();
    } catch (error) {
      _error = '清空失败: $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
