// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/continuous_rrect.dart';

/// 应用主题。
///
/// 设计语言：
/// - 浅灰页面底 + 纯白卡片，靠层次与极淡阴影区分，而不是靠描边
/// - 蓝色强调色，只出现在主按钮、选中态、进度等关键位置
/// - 连续圆角（超椭圆），在高密度屏上过渡更自然
/// - 字号阶梯统一，标题粗大、正文舒适、辅助信息小而灰
class AppTheme {
  /// 兼容旧代码的别名：强调色现在指蓝色。
  static const Color accent = AppColors.primary;

  /// 兼容旧代码：渐变的浅色端。
  static const Color accentLight = AppColors.primaryDark;

  // ── 兼容旧常量（保留旧名，值已指向新令牌）──
  @Deprecated('use colorScheme.pageSurface')
  static const Color backgroundLight = AppColors.pageLight;
  @Deprecated('use colorScheme.blockSurface')
  static const Color backgroundLight2 = AppColors.softLight;
  @Deprecated('use colorScheme.pageSurface')
  static const Color backgroundDark = AppColors.pageDark;
  @Deprecated('use colorScheme.pageSurface')
  static const Color backgroundDarker = Color(0xFF08080A);
  @Deprecated('use colorScheme.blockSurface')
  static const Color surfaceSoft = AppColors.softDark;
  @Deprecated('use colorScheme.cardSurface')
  static const Color surfaceSoftLight = AppColors.cardLight;
  @Deprecated('use colorScheme.primaryText')
  static const Color textPrimary = AppColors.textDark;
  @Deprecated('use colorScheme.secondaryText')
  static const Color textSecondary = AppColors.subTextDark;
  @Deprecated('use colorScheme.secondaryText')
  static const Color textMuted = AppColors.subTextDark;
  @Deprecated('use colorScheme.primaryText')
  static const Color textPrimaryDarkOnLight = AppColors.textLight;
  @Deprecated('use colorScheme.secondaryText')
  static const Color textSecondaryDarkOnLight = AppColors.subTextLight;

  // 圆角（已对齐新令牌）
  static const double radiusSmall = Radii.sm;
  static const double radiusMedium = Radii.md;
  static const double radiusLarge = Radii.lg;
  static const double radiusXLarge = Radii.xl;

  // 间距（已对齐新令牌）
  static const double spacingXSmall = Spacing.xs;
  static const double spacingSmall = Spacing.sm;
  static const double spacingMedium = Spacing.md;
  static const double spacingLarge = Spacing.lg;
  static const double spacingXLarge = Spacing.xl;

  static const SystemUiOverlayStyle overlayStyleLight =
      SystemUiOverlayStyle.light;
  static const SystemUiOverlayStyle overlayStyleDark =
      SystemUiOverlayStyle.dark;

  /// 亮色配色。
  static ColorScheme lightScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );
    return base.copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      surface: AppColors.pageLight,
      onSurface: AppColors.textLight,
      onSurfaceVariant: AppColors.subTextLight,
      error: AppColors.danger,
      outlineVariant: AppColors.borderLight,
      surfaceBright: AppColors.cardLight,
      surfaceContainerLowest: AppColors.cardLight,
      surfaceContainerLow: AppColors.pageLight,
      surfaceContainer: AppColors.pageLight,
      surfaceContainerHigh: AppColors.softLight,
      surfaceContainerHighest: const Color(0xFFE3E5EA),
    );
  }

  /// 暗色配色。
  static ColorScheme darkScheme() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      primary: AppColors.primaryDark,
      onPrimary: Colors.white,
      secondary: AppColors.primaryDark,
      surface: AppColors.pageDark,
      onSurface: AppColors.textDark,
      onSurfaceVariant: AppColors.subTextDark,
      error: AppColors.danger,
      outlineVariant: AppColors.borderDark,
      surfaceBright: AppColors.softDark,
      surfaceContainerLowest: AppColors.pageDark,
      surfaceContainerLow: AppColors.cardDark,
      surfaceContainer: AppColors.cardDark,
      surfaceContainerHigh: AppColors.softDark,
      surfaceContainerHighest: const Color(0xFF42434A),
    );
  }

  static ThemeData get lightTheme =>
      _buildTheme(lightScheme(), overlayStyleDark);

  static ThemeData get darkTheme =>
      _buildTheme(darkScheme(), overlayStyleLight);

  static ThemeData _buildTheme(
    ColorScheme scheme,
    SystemUiOverlayStyle overlay,
  ) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = _buildTextTheme(scheme);

    return base.copyWith(
      textTheme: text,
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: ShapeDecoration(
          color: scheme.blockSurface,
          shape: const ContinuousRRect.all(Radii.lg),
        ),
        labelColor: scheme.accent,
        unselectedLabelColor: scheme.secondaryText,
        labelStyle: const TextStyle(fontSize: TypeScale.label, fontWeight: FontWeight.w600),
      ),
      primaryTextTheme: text,
      scaffoldBackgroundColor: scheme.pageSurface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.pageSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
        iconTheme: IconThemeData(color: scheme.primaryText, size: 22),
        titleTextStyle: TextStyle(
          fontSize: TypeScale.title,
          fontWeight: FontWeight.w700,
          color: scheme.primaryText,
        ),
      ),
      // 浮动导航：整条由自定义组件绘制，这里只清掉背景
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.accent,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: const ContinuousRRect(radius: Radii.lg, smoothing: 0.6),
      ),
      cardTheme: CardThemeData(
        color: scheme.cardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: ContinuousRRect(
          radius: Radii.xl,
          smoothing: 0.6,
          side: BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const ContinuousRRect(radius: Radii.xxl, smoothing: 0.6),
        titleTextStyle: TextStyle(
          fontSize: TypeScale.title,
          fontWeight: FontWeight.w700,
          color: scheme.primaryText,
        ),
        contentTextStyle: TextStyle(
          fontSize: TypeScale.body,
          height: TypeScale.lineHeight,
          color: scheme.secondaryText,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.pageSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.pageSurface,
        elevation: 0,
        shape: const ContinuousRRect.top(Radii.huge),
        showDragHandle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.insetSurface,
        border: const ContinuousInputBorder.all(Radii.pill),
        enabledBorder: const ContinuousInputBorder.all(Radii.pill),
        focusedBorder: ContinuousInputBorder.all(
          Radii.pill,
          borderSide: BorderSide(color: scheme.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: 13,
        ),
        hintStyle: TextStyle(
          color: scheme.secondaryText,
          fontSize: TypeScale.body,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const ContinuousRRect(radius: Radii.pill, smoothing: 0.6),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xxl,
            vertical: 14,
          ),
          textStyle: const TextStyle(
            fontSize: TypeScale.body,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const ContinuousRRect(radius: Radii.pill, smoothing: 0.6),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xxl,
            vertical: 14,
          ),
          textStyle: const TextStyle(
            fontSize: TypeScale.bodyLarge,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primaryText,
          backgroundColor: scheme.cardSurface,
          shape: const ContinuousRRect(radius: Radii.pill, smoothing: 0.6),
          side: BorderSide(color: scheme.hairline),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: 11,
          ),
          textStyle: const TextStyle(
            fontSize: TypeScale.label,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.accent,
          shape: const ContinuousRRect(radius: Radii.sm, smoothing: 0.6),
          textStyle: const TextStyle(
            fontSize: TypeScale.body,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.primaryText,
          shape: const ContinuousRRect(radius: Radii.pill, smoothing: 0.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.blockSurface,
        selectedColor: scheme.accent,
        side: BorderSide.none,
        shape: const ContinuousRRect(radius: Radii.pill, smoothing: 0.6),
        labelStyle: TextStyle(
          fontSize: TypeScale.label,
          color: scheme.primaryText,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A2A2E),
        elevation: 0,
        shape: const ContinuousRRect(radius: Radii.md, smoothing: 0.6),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: TypeScale.body,
          fontWeight: FontWeight.w500,
        ),
        insetPadding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          96,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.hairline,
        space: 1,
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.accent,
        linearTrackColor: scheme.insetSurface,
        linearMinHeight: 5,
      ),
      iconTheme: IconThemeData(color: scheme.primaryText),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.secondaryText,
        textColor: scheme.primaryText,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _buildTextTheme(ColorScheme scheme) {
    TextStyle t(
      double size, {
      FontWeight weight = FontWeight.w400,
      double? height,
      Color? color,
      double? spacing,
    }) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height ?? TypeScale.lineHeight,
      color: color ?? scheme.primaryText,
      letterSpacing: spacing,
    );

    return TextTheme(
      displaySmall: t(
        TypeScale.display,
        weight: FontWeight.w700,
        height: 1.1,
        spacing: -0.8,
      ),
      headlineMedium: t(
        TypeScale.headline,
        weight: FontWeight.w700,
        height: 1.2,
        spacing: -0.6,
      ),
      titleLarge: t(TypeScale.titleLarge, weight: FontWeight.w700, height: 1.3),
      titleMedium: t(TypeScale.title, weight: FontWeight.w600, height: 1.35),
      titleSmall: t(TypeScale.bodyLarge, weight: FontWeight.w600, height: 1.4),
      bodyLarge: t(TypeScale.bodyLarge),
      bodyMedium: t(TypeScale.body),
      bodySmall: t(
        TypeScale.caption,
        height: TypeScale.lineHeightTight,
        color: scheme.secondaryText,
      ),
      labelLarge: t(TypeScale.body, weight: FontWeight.w600),
      labelMedium: t(TypeScale.label, weight: FontWeight.w500),
      labelSmall: t(
        TypeScale.caption,
        weight: FontWeight.w500,
        height: TypeScale.lineHeightTight,
        color: scheme.secondaryText,
      ),
    );
  }

  // ── 兼容旧 API：主题构建期无法拿到 context，这里给出静态装饰 ──
  static ShapeDecoration cardDecoration(ColorScheme scheme) => ShapeDecoration(
    color: scheme.cardSurface,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.xl),
      side: BorderSide(color: scheme.hairline),
    ),
  );
}

/// 轻量卡片装饰（普通圆角版本，供 BoxDecoration 使用）。
///
/// 需要连续圆角请用 `ContinuousSurface` / `MellowCard` 组件。
class SoftDecoration {
  const SoftDecoration._();

  static ShapeDecoration card(ColorScheme scheme) => ShapeDecoration(
    color: scheme.cardSurface,
    shadows: Shadows.card(scheme),
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.xl),
      side: BorderSide.none,
    ),
  );

  static ShapeDecoration sheet(ColorScheme scheme) => ShapeDecoration(
    color: scheme.cardSurface,
    shape: RoundedSuperellipseBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(Radii.huge),
      ),
      side: BorderSide.none,
    ),
  );

  static ShapeDecoration chip(ColorScheme scheme) => ShapeDecoration(
    color: scheme.blockSurface,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(Radii.pill),
      side: BorderSide.none,
    ),
  );
}

/// 连续圆角面板 —— 用 CustomPaint 绘制，不进图层缓存。
///
/// 这是全应用卡片的统一容器，替代旧的 SoftContainer。
class ContinuousSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final double smoothing;
  final SurfaceLevel level;
  final Color? color;
  final BorderSide? border;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool shadow;

  const ContinuousSurface({
    super.key,
    required this.child,
    this.radius = Radii.xl,
    this.smoothing = 0.6,
    this.level = SurfaceLevel.card,
    this.color,
    this.border,
    this.padding,
    this.onTap,
    this.shadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MellowPanel(
      radius: radius,
      smoothing: smoothing,
      color: color ?? level.colorOf(scheme),
      border: border ?? BorderSide.none,
      padding: padding,
      shadow: shadow,
      onTap: onTap,
      child: child,
    );
  }
}

/// 底层绘制组件。所有连续圆角面板最终都走这里。
class MellowPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final double smoothing;
  final Color color;
  final BorderSide border;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final VoidCallback? onTap;

  const MellowPanel({
    super.key,
    required this.child,
    required this.color,
    this.radius = Radii.xl,
    this.smoothing = 0.6,
    this.border = BorderSide.none,
    this.padding,
    this.shadow = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = ContinuousRRect(
      radius: radius,
      smoothing: smoothing,
      side: border,
    );

    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(Spacing.cardPadding),
      child: child,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        customBorder: shape,
        splashColor: scheme.accent.withValues(alpha: 0.06),
        highlightColor: scheme.accent.withValues(alpha: 0.04),
        child: content,
      );
    }

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: shadow ? Shadows.card(scheme) : null,
      ),
      child: Material(
        color: color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}

/// 面板绘制器。
///
/// 不用 canvas.drawShadow：模糊卷积每帧每卡片一次，是滚动掉帧的主因。
/// 层次改由「投影 BoxShadow（只在外层一次）+ 底色差 + 描边」表达。
class MellowPanelPainter extends CustomPainter {
  final ContinuousRRect shape;
  final Color color;
  final bool shadow;

  const MellowPanelPainter({
    required this.shape,
    required this.color,
    this.shadow = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    canvas.drawPath(path, Paint()..color = color);
    if (shape.side.style != BorderStyle.none) {
      canvas.drawPath(
        shape.getOuterPath(rect.deflate(shape.side.strokeInset / 2)),
        shape.side.toPaint(),
      );
    }
  }

  @override
  bool shouldRepaint(MellowPanelPainter old) =>
      old.color != color ||
      old.shape.radius != shape.radius ||
      old.shape.smoothing != shape.smoothing ||
      old.shape.side != shape.side;
}

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  /// 详情页转场：保留 iOS 左滑入观感，但不使用 Cupertino 内置的整层边缘阴影，
  /// 以降低进出详情页时的每帧重绘开销（方案 C）。
  static Widget detailTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final direction = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;
    final curved = animation.drive(
      CurveTween(curve: Motion.fadeIn),
    );
    return SlideTransition(
      position: curved.drive(
        Tween(begin: Offset(1.0 * direction, 0), end: Offset.zero),
      ),
      child: RepaintBoundary(child: child),
    );
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return transition(context, animation, secondaryAnimation, child);
  }

  static Widget transition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = animation.drive(CurveTween(curve: Motion.fadeIn));
    final direction = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;
    // 只做位移，不做淡入。
    //
    // 原来这里是 FadeTransition（opacity 从 0 到 1）。问题是淡入期间
    // 新页面整层还是透明的，底下什么都看不到——如果此时底层没有不透明的
    // 背景兜着（详情页是独立路由，底下就是空的），就会露出白/黑底，
    // 观感是「进出页面闪一下」。
    //
    // 位移已经足够表达「从右侧进来」，且从头到尾画面都是不透明的，
    // 不会露出背景。位移幅度保持 0.035（约屏宽 3.5%），够轻。
    return SlideTransition(
      position: curved.drive(
        Tween(begin: Offset(0.035 * direction, 0), end: Offset.zero),
      ),
      child: child,
    );
  }
}
