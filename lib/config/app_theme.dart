import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用主题配置 —— Material 3，seed 中性化配色。
///
/// 两套 ColorScheme 均由 [ColorScheme.fromSeed] 基于品牌红 [accent] 派生，
/// 暗色底采用 MD3 标准中性深灰。页面统一走 `Theme.of(context).colorScheme`
/// 语义色，不再依赖手写的固定色常量。
class AppTheme {
  // 品牌种子色（唯一保留的核心色）
  static const Color accent = Color(0xFFE94560);

  /// 品牌渐变的浅色端（仅用于强调渐变，非主题表面色）。
  static const Color accentLight = Color(0xFFFF6B6B);

  // ── 兼容旧常量：逐页迁移期间保留，指向近似的静态值 ──
  // 新代码请改用 colorScheme 语义色，勿再引用以下常量。
  @Deprecated('use colorScheme.surface')
  static const Color backgroundLight = Color(0xFFFBF8F8);
  @Deprecated('use colorScheme.surfaceContainerLow')
  static const Color backgroundLight2 = Color(0xFFF3EDED);
  @Deprecated('use colorScheme.surface')
  static const Color backgroundDark = Color(0xFF141218);
  @Deprecated('use colorScheme.surfaceContainerLowest')
  static const Color backgroundDarker = Color(0xFF0F0D13);
  @Deprecated('use colorScheme.surfaceContainerHigh')
  static const Color surfaceSoft = Color(0xFF211F26);
  @Deprecated('use colorScheme.surfaceContainerHigh')
  static const Color surfaceSoftLight = Color(0xFFFFFFFF);
  @Deprecated('use colorScheme.onSurface')
  static const Color textPrimary = Color(0xFFFFFFFF);
  @Deprecated('use colorScheme.onSurfaceVariant')
  static const Color textSecondary = Color(0xB3FFFFFF);
  @Deprecated('use colorScheme.onSurfaceVariant')
  static const Color textMuted = Color(0x80FFFFFF);
  @Deprecated('use colorScheme.onSurface')
  static const Color textPrimaryDarkOnLight = Color(0xFF1C1B1F);
  @Deprecated('use colorScheme.onSurfaceVariant')
  static const Color textSecondaryDarkOnLight = Color(0x991C1B1F);

  // 圆角
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
  static const double radiusXLarge = 24;

  // 间距
  static const double spacingXSmall = 4;
  static const double spacingSmall = 8;
  static const double spacingMedium = 16;
  static const double spacingLarge = 24;
  static const double spacingXLarge = 32;

  static const SystemUiOverlayStyle overlayStyleLight =
      SystemUiOverlayStyle.light;
  static const SystemUiOverlayStyle overlayStyleDark =
      SystemUiOverlayStyle.dark;

  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.light,
  );

  static final ColorScheme _darkScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  );

  /// 亮色主题
  static ThemeData get lightTheme =>
      _buildTheme(_lightScheme, overlayStyleDark);

  /// 暗色主题
  static ThemeData get darkTheme => _buildTheme(_darkScheme, overlayStyleLight);

  static ThemeData _buildTheme(
    ColorScheme scheme,
    SystemUiOverlayStyle overlay,
  ) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: scheme.primary, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingMedium,
          vertical: spacingSmall,
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacingLarge,
            vertical: spacingMedium,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        elevation: 6,
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        insetPadding: const EdgeInsets.fromLTRB(
          spacingMedium,
          spacingSmall,
          spacingMedium,
          88,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// 轻拟物装饰 —— 纯色底 + 描边，配色随主题。
///
/// 由于 [BoxDecoration] 不能在 build 外拿到 context，这里提供接收
/// [ColorScheme] 的工厂方法。
class SoftDecoration {
  static BoxDecoration card(ColorScheme scheme) => BoxDecoration(
    color: scheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
    border: Border.all(color: scheme.outlineVariant, width: 1),
  );

  static BoxDecoration sheet(ColorScheme scheme) => BoxDecoration(
    color: scheme.surfaceContainerLow,
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(AppTheme.radiusXLarge),
    ),
    border: Border.all(color: scheme.outlineVariant, width: 1),
  );
}
