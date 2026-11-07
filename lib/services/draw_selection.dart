import 'package:random_movie/models/models.dart';

/// 让抽片选中的影片始终落在当前候选范围内。
class DrawSelection {
  const DrawSelection._();

  /// 规范化、去重，并按需裁剪到 [scope] 范围内。
  static List<String> restrictToScope(
    Iterable<String> ids, {
    Iterable<String>? scope,
  }) {
    final scopeIds = scope
        ?.map(_normalize)
        .where((id) => id.isNotEmpty)
        .toSet();
    final result = <String>[];
    final seen = <String>{};

    for (final rawId in ids) {
      final id = _normalize(rawId);
      if (id.isEmpty || (scopeIds != null && !scopeIds.contains(id))) {
        continue;
      }
      if (seen.add(id)) result.add(id);
    }
    return result;
  }

  static String _normalize(String id) => id.trim();

  static List<String> selectAll(Iterable<String> scope) =>
      restrictToScope(scope);

  static List<String> selectUnwatched(
    Iterable<String> ids, {
    Iterable<String>? scope,
  }) => restrictToScope(ids, scope: scope);
}

/// 抽片页使用的按模式隔离的选中状态。
class DrawSelectionState {
  final Map<DrawMode, Set<String>> _selectedByMode = {
    for (final mode in DrawMode.values) mode: <String>{},
  };

  Set<String> selectedIds(DrawMode mode) =>
      Set<String>.unmodifiable(_selectedByMode[mode]!);

  int count(DrawMode mode) => _selectedByMode[mode]!.length;

  void replace(DrawMode mode, Iterable<String> ids, {Iterable<String>? scope}) {
    _selectedByMode[mode]!
      ..clear()
      ..addAll(DrawSelection.restrictToScope(ids, scope: scope));
  }

  void replaceAllModes(Iterable<String> ids) {
    final normalized = DrawSelection.restrictToScope(ids);
    for (final mode in DrawMode.values) {
      replace(mode, normalized);
    }
  }

  void clearAll() {
    for (final selection in _selectedByMode.values) {
      selection.clear();
    }
  }

  void toggle(DrawMode mode, String id) {
    final normalized = id.trim();
    if (normalized.isEmpty) return;
    final selection = _selectedByMode[mode]!;
    if (!selection.add(normalized)) selection.remove(normalized);
  }
}
