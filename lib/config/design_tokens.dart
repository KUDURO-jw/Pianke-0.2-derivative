import 'package:flutter/material.dart';

/// 设计令牌 —— 全应用的视觉基准。
///
/// 视觉语言参考现代 Material You + 悬浮卡片风格（iOS 式连续圆角），
/// 全部为独立实现；未复制任何 GPL 项目代码。
///
/// 四个维度：表面层次、圆角、字号、间距。所有页面只从这里取值，
/// 避免再次出现「98 处硬编码 fontSize」的混乱。

/// ─────────────────────────────────────────────
/// 一、品牌色
/// ─────────────────────────────────────────────

/// 应用调色板。
///
/// 以蓝色为主调（对应目标设计语言），红色保留为次要强调（用于删除、
/// 重要提醒等破坏性操作），避免全站只有一种强调色导致重点不突出。
class AppColors {
  const AppColors._();

  /// 主强调色（蓝）。
  static const Color primary = Color(0xFF2F6BFF);
  static const Color primaryDark = Color(0xFF4C86FF);

  /// 次要强调（红）。仅用于危险操作、未看标记等。
  static const Color danger = Color(0xFFE94560);

  /// 成功色（用于「已看」状态、完成进度）。
  static const Color success = Color(0xFF34C759);
  static const Color successSoft = Color(0xFFD6F5DB);

  /// 警告色（评分星、提醒）。
  static const Color warning = Color(0xFFFFB020);

  /// 页面底色（浅灰，让白色卡片浮起来）。
  static const Color pageLight = Color(0xFFF2F3F5);
  static const Color pageDark = Color(0xFF0E0E10);

  /// 卡片底色。
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1A1A1D);

  /// 柔和色块（卡片内二级容器）。
  static const Color softLight = Color(0xFFF5F6F8);
  static const Color softDark = Color(0xFF242428);

  /// 主文字。
  static const Color textLight = Color(0xFF111114);
  static const Color textDark = Color(0xFFF3F3F5);

  /// 次文字。
  static const Color subTextLight = Color(0xFF8A8D93);
  static const Color subTextDark = Color(0xFF9A9DA3);

  /// 描边（极淡，只用来分隔，不抢视觉）。
  static const Color borderLight = Color(0x0F000000);
  static const Color borderDark = Color(0x14FFFFFF);
}

/// ─────────────────────────────────────────────
/// 二、表面层次
/// ─────────────────────────────────────────────

/// 表面层级。
///
/// 亮色：层级越高越白（page 灰 → card 白 → block 微灰 → inset 更灰）。
/// 暗色：层级越高越亮。
/// 两套主题的"靠前"方向一致，不会出现暗色下卡片反而更暗的问题。
enum SurfaceLevel {
  /// 页面底色
  page,

  /// 卡片
  card,

  /// 卡片内的分组
  block,

  /// 内嵌元素（输入框、进度槽）
  inset;

  /// 取本层对应的表面色。
  ///
  /// 刻意使用固定中性色而非 `scheme.surfaceContainer*`：
  /// 后者会被 seed 染色，一旦 seed 换成彩色就会让整个界面泛色。
  Color colorOf(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    if (dark) {
      return switch (this) {
        SurfaceLevel.page => AppColors.pageDark,
        SurfaceLevel.card => AppColors.cardDark,
        SurfaceLevel.block => AppColors.softDark,
        SurfaceLevel.inset => const Color(0xFF2E2E33),
      };
    }
    return switch (this) {
      SurfaceLevel.page => AppColors.pageLight,
      SurfaceLevel.card => AppColors.cardLight,
      SurfaceLevel.block => AppColors.softLight,
      SurfaceLevel.inset => const Color(0xFFECEEF1),
    };
  }

  /// 主文字色。
  Color textColorOf(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? AppColors.textDark
      : AppColors.textLight;

  /// 次文字色。
  Color subTextColorOf(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? AppColors.subTextDark
      : AppColors.subTextLight;

  /// 描边色。
  Color borderColorOf(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? AppColors.borderDark
      : AppColors.borderLight;

  /// 下一层。
  SurfaceLevel get next => switch (this) {
    SurfaceLevel.page => SurfaceLevel.card,
    SurfaceLevel.card => SurfaceLevel.block,
    SurfaceLevel.block || SurfaceLevel.inset => SurfaceLevel.inset,
  };

  /// 浮层（弹窗、底部弹窗）。
  static SurfaceLevel floating =
      // 浮层在两种模式下都用卡片色，靠阴影与蒙层区分
      SurfaceLevel.card;
}

extension SurfaceColorExt on ColorScheme {
  Color get pageSurface => SurfaceLevel.page.colorOf(this);
  Color get cardSurface => SurfaceLevel.card.colorOf(this);
  Color get blockSurface => SurfaceLevel.block.colorOf(this);
  Color get insetSurface => SurfaceLevel.inset.colorOf(this);

  Color get primaryText => SurfaceLevel.card.textColorOf(this);
  Color get secondaryText => SurfaceLevel.card.subTextColorOf(this);
  Color get hairline => SurfaceLevel.card.borderColorOf(this);

  /// 当前主题的强调色（蓝色系）。
  Color get accent => brightness == Brightness.dark
      ? AppColors.primaryDark
      : AppColors.primary;
}

/// ─────────────────────────────────────────────
/// 三、圆角
/// ─────────────────────────────────────────────

class Radii {
  const Radii._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double huge = 32;

  /// 胶囊形
  static const double pill = 999;
}

/// ─────────────────────────────────────────────
/// 四、字号
/// ─────────────────────────────────────────────

/// 字号阶梯。
///
/// 目标设计语言的字号偏大、层级分明：标题粗且大，正文舒适，
/// 辅助信息小而灰。在高密度屏幕（如 6.73" 3200×1440）上也不会显小。
class TypeScale {
  const TypeScale._();

  /// 辅助说明、计数
  static const double caption = 12;

  /// 标签、次级按钮
  static const double label = 13;

  /// 正文
  static const double body = 14;

  /// 略大正文（列表主标题）
  static const double bodyLarge = 15;

  /// 卡片标题
  static const double title = 17;

  /// 页面内大标题
  static const double titleLarge = 19;

  /// 页面主标题
  static const double headline = 26;

  /// 超大数字（统计）
  static const double display = 30;

  static const double lineHeight = 1.45;
  static const double lineHeightTight = 1.25;

  static TextStyle captionStyle(ColorScheme scheme, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontSize: caption,
        height: lineHeightTight,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? scheme.secondaryText,
      );

  static TextStyle bodyStyle(ColorScheme scheme, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontSize: body,
        height: lineHeight,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? scheme.primaryText,
      );
}

/// ─────────────────────────────────────────────
/// 五、间距
/// ─────────────────────────────────────────────

class Spacing {
  const Spacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// 页面左右边距
  static const double page = 18;

  /// 卡片内边距
  static const double cardPadding = 16;

  /// 卡片之间的间距
  static const double gap = 14;
}

/// ─────────────────────────────────────────────
/// 六、动效
/// ─────────────────────────────────────────────

class Motion {
  const Motion._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
}

/// ─────────────────────────────────────────────
/// 七、阴影
/// ─────────────────────────────────────────────

/// 阴影规格。
///
/// 目标设计语言的阴影「极淡但存在」：几乎看不出边缘，只让卡片浮起来。
/// 刻意不用大 blurRadius——那在滚动列表里非常贵。
class Shadows {
  const Shadows._();

  /// 卡片阴影（极淡）
  static List<BoxShadow> card(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.28 : 0.045),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// 悬浮元素（底部导航条）
  static List<BoxShadow> floating(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.4 : 0.08),
        blurRadius: 24,
        offset: const Offset(0, 6),
      ),
    ];
  }
}
