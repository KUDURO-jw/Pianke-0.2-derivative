import 'package:flutter/material.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/continuous_rrect.dart';

// ==================== Toast ====================

/// Toast type determines icon and color scheme
enum ToastType { success, error, info }

/// Themed floating toast — matches the app's soft skeuomorphism style.
///
/// Usage:
///   AppToast.success(context, '保存成功');
///   AppToast.error(context, '网络异常');
///   AppToast.info(context, '已复制');
class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration? duration,
  }) {
    // Capture values synchronously (context may be invalid after frame)
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, iconColor) = _iconFor(type, colorScheme);
    final textColor = colorScheme.onInverseSurface;
    final bgColor = colorScheme.inverseSurface;
    // Keep the toast above the bottom NavigationBar and safe area.
    final bottomInset = MediaQuery.of(context).padding.bottom + 88;

    // Delay so any dialog pop() animation completes first.
    Future.delayed(const Duration(milliseconds: 500), () {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: AppTheme.spacingSmall),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          elevation: 6,
          duration: duration ?? const Duration(seconds: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMedium,
            vertical: AppTheme.spacingSmall + 2,
          ),
          dismissDirection: DismissDirection.horizontal,
        ),
      );
    });
  }

  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
  }) => show(context, message, type: ToastType.success, duration: duration);

  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
  }) => show(context, message, type: ToastType.error, duration: duration);

  static void info(
    BuildContext context,
    String message, {
    Duration? duration,
  }) => show(context, message, type: ToastType.info, duration: duration);

  static (IconData, Color) _iconFor(ToastType type, ColorScheme scheme) {
    return switch (type) {
      ToastType.success => (
        Icons.check_circle_rounded,
        const Color(0xFF4CAF50),
      ),
      ToastType.error => (Icons.error_rounded, AppTheme.accent),
      ToastType.info => (
        Icons.info_rounded,
        scheme.onInverseSurface.withValues(alpha: 0.7),
      ),
    };
  }
}

// ==================== Soft Containers ====================

/// 通用表面容器。
///
/// 视觉规格已升级到新的设计令牌体系：
/// - 默认使用连续圆角（[ContinuousRRect]），在高像素密度屏幕上更柔和
/// - 默认取 [SurfaceLevel.card] 的层次色，暗色下不再比背景更暗
/// - 阴影更轻，层次主要靠颜色差异而非投影表达
///
/// 保留 [borderRadius] 参数以兼容既有调用点；一旦传入会退化为普通圆角
/// （因为该参数是 [BorderRadius] 类型，无法表达连续圆角）。
class SoftContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Color? color;
  final Border? border;
  final bool showBorder;
  final bool showShadow;

  /// 连续圆角的平滑度。
  final double smoothing;

  /// 使用的表面层级。
  final SurfaceLevel level;

  const SoftContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.borderRadius,
    this.color,
    this.border,
    this.showBorder = true,
    this.showShadow = true,
    this.smoothing = 0.6,
    this.level = SurfaceLevel.card,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final effectiveColor = color ?? level.colorOf(colorScheme);

    final side = showBorder
        ? (border?.top ??
              BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: 1,
              ))
        : BorderSide.none;

    // 传了显式 borderRadius 就退化为普通圆角，保持既有调用点的观感可控。
    if (borderRadius != null) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        padding: padding ?? const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: effectiveColor,
          borderRadius: borderRadius,
          border: showBorder ? border : null,
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: child,
      );
    }

    final shape = ContinuousRRect(
      radius: Radii.lg,
      smoothing: smoothing,
      side: side,
    );

    // 性能要点：
    // 不使用 Material(shape:..., clipBehavior: Clip.antiAlias)，
    // 那会让每个卡片产生独立裁剪图层，列表滚动时逐帧重建，实测明显掉帧。
    // 改用 CustomPaint 直接绘制形状 + 背景，绘制成本恒定且不进图层缓存。
    final inset = side.strokeInset;
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: CustomPaint(
        painter: _ContinuousSurfacePainter(
          shape: shape,
          color: effectiveColor,
          shadow: showShadow,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: inset,
            vertical: inset,
          ).add(
            padding ?? const EdgeInsets.all(Spacing.lg),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 绘制连续圆角面板：底色 + 描边（可选投影）。
///
/// 用 CustomPaint 而不是 Material + clipBehavior，避免为每张卡片创建
/// 独立裁剪图层。shouldRepaint 只在颜色/形状变化时为真。
class _ContinuousSurfacePainter extends CustomPainter {
  final ContinuousRRect shape;
  final Color color;
  final bool shadow;

  const _ContinuousSurfacePainter({
    required this.shape,
    required this.color,
    required this.shadow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);

    // 性能：完全不用 canvas.drawShadow。
    // drawShadow 会做模糊卷积，每张卡片每帧一次，滚动时是最大开销。
    // 层次感改由「底色深浅差 + 1px 描边」表达，视觉差异极小但零成本。
    canvas.drawPath(path, Paint()..color = color);

    if (shape.side.style != BorderStyle.none) {
      canvas.drawPath(
        shape.getOuterPath(rect.deflate(shape.side.strokeInset / 2)),
        shape.side.toPaint(),
      );
    }
  }

  @override
  bool shouldRepaint(_ContinuousSurfacePainter old) =>
      old.color != color ||
      old.shape.radius != shape.radius ||
      old.shape.smoothing != shape.smoothing ||
      old.shape.side != shape.side;
}

/// 轻拟物卡片 —— 在 [SoftContainer] 外包一层点击态
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final bool showShadow;
  final SurfaceLevel level;

  const SoftCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.onTap,
    this.showShadow = true,
    this.level = SurfaceLevel.card,
  });

  @override
  Widget build(BuildContext context) {
    final shape = ContinuousRRect(
      radius: Radii.lg,
      smoothing: 0.6,
      side: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.45),
      ),
    );

    Widget card = SoftContainer(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      showShadow: showShadow,
      level: level,
      child: child,
    );

    if (onTap != null) {
      card = Stack(
        children: [
          card,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, customBorder: shape),
            ),
          ),
        ],
      );
    }

    return card;
  }
}

/// 主按钮组件
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingLarge,
            vertical: AppTheme.spacingMedium,
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.onPrimary,
                  ),
                ),
              )
            : Row(
                mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: AppTheme.spacingSmall),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// 次按钮组件
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: BorderSide(color: onSurface.withValues(alpha: 0.25)),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: AppTheme.spacingSmall,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: AppTheme.spacingSmall),
          ],
          Text(label),
        ],
      ),
    );
  }
}

/// 空状态组件
class EmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionLabel;

  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppTheme.spacingSmall),
              Text(
                subtitle!,
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: AppTheme.spacingLarge),
              PrimaryButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// 加载状态组件
class LoadingState extends StatelessWidget {
  final String? message;

  const LoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
          if (message != null) ...[
            const SizedBox(height: AppTheme.spacingMedium),
            Text(message!, style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// 错误状态组件
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: AppTheme.spacingMedium),
            Text(
              message,
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppTheme.spacingMedium),
              SecondaryButton(
                label: '重试',
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
