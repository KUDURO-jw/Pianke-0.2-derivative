// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
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
  static const Color primary = Color(0xFF3478F6);
  static const Color primaryDark = Color(0xFF6A9CFF);

  /// 次要强调（红）。仅用于危险操作、未看标记等。
  static const Color danger = Color(0xFFE94560);

  /// 成功色（用于「已看」状态、完成进度）。
  static const Color success = Color(0xFF34C759);
  static const Color successSoft = Color(0xFFD6F5DB);

  /// 警告色（评分星、提醒）。
  static const Color warning = Color(0xFFFFB020);

  /// 页面底色（浅灰，让白色卡片浮起来）。
  static const Color pageLight = Color(0xFFF0F1F4);
  static const Color pageDark = Color(0xFF101114);

  /// 卡片底色。
  static const Color cardLight = Color(0xFFFAFAFC);
  static const Color cardDark = Color(0xFF242529);

  /// 柔和色块（卡片内二级容器）。
  static const Color softLight = Color(0xFFEFF0F3);
  static const Color softDark = Color(0xFF323338);

  /// 主文字。
  static const Color textLight = Color(0xFF111114);
  static const Color textDark = Color(0xFFF3F3F5);

  /// 次文字。
  static const Color subTextLight = Color(0xFF6F737C);
  static const Color subTextDark = Color(0xFFA9ADB7);

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
        SurfaceLevel.inset => const Color(0xFF42434A),
      };
    }
    return switch (this) {
      SurfaceLevel.page => AppColors.pageLight,
      SurfaceLevel.card => AppColors.cardLight,
      SurfaceLevel.block => AppColors.softLight,
      SurfaceLevel.inset => const Color(0xFFE3E5EA),
    };
  }

  /// 主文字色。
  Color textColorOf(ColorScheme scheme) => scheme.brightness == Brightness.dark
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
  Color get accent =>
      brightness == Brightness.dark ? AppColors.primaryDark : AppColors.primary;
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

  static TextStyle captionStyle(
    ColorScheme scheme, {
    Color? color,
    FontWeight? weight,
  }) => TextStyle(
    fontSize: caption,
    height: lineHeightTight,
    fontWeight: weight ?? FontWeight.w400,
    color: color ?? scheme.secondaryText,
  );

  static TextStyle bodyStyle(
    ColorScheme scheme, {
    Color? color,
    FontWeight? weight,
  }) => TextStyle(
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

/// 动效令牌。
///
/// 全应用只从这里取动画时长与曲线，避免 `Duration(milliseconds: N)` 散落在
/// 十几个文件里（文档写 280/220，代码里却写成 200/180，对不上就是这么来的）。
///
/// **所有**新动画都必须经由 [of] 取值：用户开启系统「移除动画」时它返回
/// `Duration.zero`，不需要每个组件各自判断。
class Motion {
  const Motion._();

  /// 极短：按下反馈、微小的颜色/透明度变化。
  static const Duration fast = Duration(milliseconds: 120);

  /// 常规：淡入淡出、卡片展开收起。
  static const Duration normal = Duration(milliseconds: 220);

  /// 慢：需要被看清的位移或强调。
  static const Duration slow = Duration(milliseconds: 320);

  /// 二级页面前进。
  static const Duration page = Duration(milliseconds: 260);

  /// 二级页面返回。返回略快于进入，是常见的手感约定。
  static const Duration pageBack = Duration(milliseconds: 220);

  /// 容器展开 / 收起（面板高度、内边距变化）。
  static const Duration panel = Duration(milliseconds: 150);

  /// 弹窗关闭后给提示条留的缓冲，避免被淡出中的遮罩盖住。
  static const Duration settle = Duration(milliseconds: 160);

  /// 骨架屏高光扫过一轮。
  static const Duration shimmer = Duration(milliseconds: 1400);

  /// 呼吸 / 脉冲循环（抽片入口、空态插图）。
  static const Duration breath = Duration(milliseconds: 1600);

  /// 结果揭晓时的弹起。
  static const Duration reveal = Duration(milliseconds: 380);

  /// 占位符交叉淡入（添加影片页的骨架文字）。
  static const Duration placeholderFade = Duration(milliseconds: 1100);

  /// 回到顶部的滚动对齐。
  static const Duration scroll = Duration(milliseconds: 420);

  /// 抽片洗牌的单步间隔。
  static const Duration shuffleTick = Duration(milliseconds: 100);


  /// 抽片转盘的完整时长（一个控制器跑完）。
  ///
  /// 从 2600ms 压到 1600ms：2600ms 加上揭晓停留，用户要纯等 3 秒以上，
  /// 而抽片是一个「快速给出答案」的动作，不该拖成仪式。
  static const Duration drawSpin = Duration(milliseconds: 1600);

  /// 抽片转盘曲线。
  ///
  /// 不用 `easeOutQuart`：它在 t=0 的导数为 4，配合 96~144 的总步数，
  /// 起步瞬间约 147 步/秒 —— 每帧都在换卡，洗牌退化成了「闪烁」。
  /// 这条曲线前段接近线性（能看清方向），末端强减速（明确「转不动了」）。
  static const Curve spinCurve = Cubic(0.12, 0.62, 0.10, 1.0);

  /// 抽片揭晓后停留多久再进入结果页。
  static const Duration resultHold = Duration(milliseconds: 400);

  /// 输入防抖：停止输入多久后才真正查询。
  static const Duration debounce = Duration(milliseconds: 250);

  /// 片单批量抓取时，批次之间的间隔。
  ///
  /// 不是动画时长，但它同样是「不该散落在业务代码里的时间常量」，
  /// 统一放在这里，方便调整时只改一处，也让 check-motion-tokens
  /// 的「时长只在此文件定义」这条规则保持无例外。
  ///
  /// 取值理由：豆瓣对高频访问会返回挑战页或限流（403/429）。
  /// 400ms 是「明显降低风控概率」与「用户还愿意等」之间的折中。
  static const Duration scraperBatchGap = Duration(milliseconds: 400);

  /// 抓取遇到限流（403 / 429）时，第 n 次重试前等待 n × 这个基数。
  ///
  /// 豆瓣的限流是短窗口：刚进应用或连续请求后会被拦，几秒后自动恢复。
  /// 用户看到的是「刚进去报错，过几秒又好了」。
  /// 与其把这个窗口暴露给用户，不如内部退避重试。
  ///
  /// 1s / 2s 两档，最多 3 次尝试，总等待上限约 3 秒。
  static const Duration scraperRetryBase = Duration(seconds: 1);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  // ── 物理语言：位移与缩放走弹簧，透明度与颜色走曲线 ──
  //
  // 一条规则能消掉现在的手感割裂：底栏用弹簧、抽片用补间，同一个应用两套语言。
  // `Transform` 相关的动画优先用下面的 SpringDescription——弹簧能接收初速度，
  // 曲线不能，所以拖动 / 甩动 / 按压这类交互必须走弹簧才跟手。

  /// 按压回弹：按下放大、松开回位。参数沿用悬浮底栏，轻微过冲。
  static final SpringDescription pressSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 311, ratio: 0.593);

  /// 吸附归位：位置对齐到整数格，不过冲。用于底栏选中块、分页吸附。
  static final SpringDescription settleSpring = SpringDescription(
    mass: 1,
    stiffness: 350,
    damping: 30,
  );

  /// 开奖弹起：抽片定格、结果登场。回弹明显但收得住。
  static final SpringDescription revealSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 180, ratio: 0.72);

  /// 快切：几乎无过冲，用于同一元素的状态切换。
  static final SpringDescription snapSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 0.9);

  /// 纯淡入淡出（没有位移语义）。
  static const Curve fade = Curves.easeOut;

  /// 带位移的淡入。
  static const Curve fadeIn = Curves.easeOutCubic;

  /// 页面间共享元素。底栏以外的位置切换用这条。
  static const Curve shared = Curves.easeInOutCubic;

  /// 回弹规格，参数取自悬浮底栏现有配置。
  static const SpringDescription spring = SpringDescription(
    mass: 1,
    stiffness: 350,
    damping: 30,
  );

  /// 统一入口：用户开启「移除动画」时返回 [Duration.zero]。
  ///
  /// 需要 `context` 是因为减少动效开关在 [MediaQuery] 上，
  /// 它支持运行中切换，不能缓存成静态值。
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  /// 当前是否应当播放动画。
  static bool enabled(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);
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
