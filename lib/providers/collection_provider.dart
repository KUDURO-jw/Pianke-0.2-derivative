import 'package:flutter/foundation.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/services.dart';

/// 合集与标签状态管理。
class CollectionProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();

  List<MovieCollection> _manualCollections = [];
  List<MovieCollection> _smartCollections = [];
  List<MovieTag> _allTags = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;

  List<MovieCollection> get manualCollections => _manualCollections;
  List<MovieCollection> get smartCollections => _smartCollections;
  List<MovieTag> get allTags => _allTags;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  Future<void> ensureLoaded() async {
    if (_hasLoaded || _isLoading) return;
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    if (_hasLoaded) notifyListeners();
    try {
      final results = await Future.wait<Object>([
        _storageService.queryCollections(),
        _storageService.querySmartCollections(),
        _storageService.queryAllTags(),
      ]);
      _manualCollections = results[0] as List<MovieCollection>;
      _smartCollections = results[1] as List<MovieCollection>;
      _allTags = results[2] as List<MovieTag>;
    } catch (error) {
      _error = '加载合集失败: $error';
    } finally {
      _hasLoaded = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ========== 合集 ==========

  Future<MovieCollection?> createCollection(String name, String iconKey) async {
    if (name.trim().isEmpty) return null;
    try {
      final created = await _storageService.addCollection(
        MovieCollection(id: '', name: name.trim(), iconKey: iconKey),
      );
      await refresh();
      return created;
    } catch (error) {
      _error = '创建失败: $error';
      notifyListeners();
      return null;
    }
  }

  Future<void> renameCollection(MovieCollection collection, String name) async {
    if (name.trim().isEmpty) return;
    await _storageService.updateCollection(
      collection.copyWith(name: name.trim()),
    );
    await refresh();
  }

  Future<void> updateCollectionIcon(
    MovieCollection collection,
    String iconKey,
  ) async {
    await _storageService.updateCollection(
      collection.copyWith(iconKey: iconKey),
    );
    await refresh();
  }

  Future<void> deleteCollection(String collectionId) async {
    await _storageService.deleteCollection(collectionId);
    await refresh();
  }

  Future<void> addMovieToCollection(String collectionId, String movieId) async {
    await _storageService.addMovieToCollection(collectionId, movieId);
    await refresh();
  }

  Future<void> removeMovieFromCollection(
    String collectionId,
    String movieId,
  ) async {
    await _storageService.removeMovieFromCollection(collectionId, movieId);
    await refresh();
  }

  /// 合集成员影片 id（手动或智能）。
  Future<List<String>> memberIdsOf(MovieCollection collection) {
    if (collection.isSmart) {
      return _storageService.querySmartCollectionMemberIds(
        collection.kind,
        collection.smartValue,
      );
    }
    return _storageService.queryCollectionMemberIds(collection.id);
  }

  /// 某影片所属的手动合集 id 集合。
  Future<Set<String>> collectionIdsForMovie(String movieId) {
    return _storageService.queryCollectionIdsForMovie(movieId);
  }

  // ========== 标签 ==========

  Future<MovieTag?> createTag(String name, int colorValue) async {
    if (name.trim().isEmpty) return null;
    try {
      final created = await _storageService.addTag(
        MovieTag(id: '', name: name.trim(), colorValue: colorValue),
      );
      _allTags = [..._allTags, created];
      notifyListeners();
      return created;
    } catch (error) {
      _error = '创建标签失败: $error';
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteTag(String tagId) async {
    await _storageService.deleteTag(tagId);
    _allTags = _allTags.where((t) => t.id != tagId).toList();
    notifyListeners();
  }

  Future<List<MovieTag>> tagsForMovie(String movieId) {
    return _storageService.queryTagsForMovie(movieId);
  }

  Future<void> setMovieTags(String movieId, Iterable<String> tagIds) async {
    await _storageService.setMovieTags(movieId, tagIds);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
