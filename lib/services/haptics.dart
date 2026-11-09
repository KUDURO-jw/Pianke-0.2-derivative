// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 触觉反馈的统一入口。
///
/// 此前 `HapticFeedback` 全项目只有 4 处调用（3 处在底栏），所以「标记已看」
/// 「保存成功」「删除」这些真正需要确认感的动作全是静默的。
///
/// 统一收口有两个好处：
/// 1. 设置页一个开关就能全局关掉（`enabled`）；
/// 2. 各平台是否支持由这里统一兜底，调用方不用关心。
abstract final class Haptics {
  static const String _prefsKey = 'pianke_haptics_enabled';

  /// 是否允许震动。设置页会改它，调用方无需判断。
  static bool enabled = true;

  static bool _loaded = false;

  /// 从偏好读取开关状态。启动时调用一次即可，重复调用无副作用。
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      // 读不到就保持默认开启，不该因为偏好异常让交互失去反馈。
      enabled = true;
    }
  }

  /// 写入开关状态并持久化。
  static Future<void> setEnabled(bool value) async {
    enabled = value;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // 持久化失败时内存态已生效，本次会话仍然正确。
    }
  }

  /// 选中 / 切换（最轻）。
  static void selection() => _fire(HapticFeedback.selectionClick);

  /// 轻触：列表项被按下、开关被拨动。
  static void light() => _fire(HapticFeedback.lightImpact);

  /// 成功：保存完成、标记已看。
  static void success() => _fire(HapticFeedback.mediumImpact);

  /// 警告：删除、不可撤回的破坏性操作。
  static void warning() => _fire(HapticFeedback.heavyImpact);

  /// 所有触觉都从这里出去，保证「开关」和「异常兜底」只有一处。
  static void _fire(void Function() action) {
    if (!enabled) return;
    // 桌面端 / 测试环境没有触觉实现，会抛 MissingPluginException，
    // 这里必须吞掉：震动失败绝不该影响一次成功的保存。
    try {
      action();
    } catch (_) {}
  }
}
