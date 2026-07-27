import 'package:flutter/material.dart';
import 'package:random_movie/services/storage_service.dart';

/// 主题模式 Provider —— 管理明暗切换并持久化到 SharedPreferences。
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({StorageService? storage})
    : _storage = storage ?? StorageService();

  final StorageService _storage;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// 从本地读取已保存的模式。应在 StorageService.init() 之后调用。
  void load() {
    _themeMode = _decode(_storage.getThemeMode());
    notifyListeners();
  }

  /// 显式设置模式（system / light / dark）并持久化。
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _storage.setThemeMode(_encode(mode));
  }

  /// 在明暗之间切换。
  ///
  /// 若当前为 system，则依据传入的当前亮度切到相反色，
  /// 保证点击一次一定有可见变化。
  Future<void> toggle(Brightness currentBrightness) async {
    final ThemeMode next;
    switch (_themeMode) {
      case ThemeMode.light:
        next = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        next = ThemeMode.light;
        break;
      case ThemeMode.system:
        next = currentBrightness == Brightness.dark
            ? ThemeMode.light
            : ThemeMode.dark;
        break;
    }
    await setMode(next);
  }

  static ThemeMode _decode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
