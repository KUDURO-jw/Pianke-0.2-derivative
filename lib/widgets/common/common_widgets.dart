// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/continuous_rrect.dart';
import 'package:random_movie/widgets/common/floating_nav_bar.dart';

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

  /// 给刚关闭的弹窗留出淡出时间（Material 弹窗淡出约 150ms），
  /// 避免提示条被淡出中的遮罩盖住。过长会让用户觉得「点了没反应」。
  static const Duration _dialogSettleDelay = Motion.settle;

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
    // 提示条要浮在悬浮底栏上方。底栏高度会随系统字体放大而变高，
    // 所以跟随 DockMetrics，而不是写死一个数字；键盘弹出时底栏隐藏，
    // 此时只需要避开系统安全区。
    final media = MediaQuery.of(context);
    final bottomInset = math.max(
      DockMetrics.insetOf(context),
      media.padding.bottom + 16,
    );

    // Delay so any dialog pop() animation completes first.
    Future.delayed(_dialogSettleDelay, () {
      if (!messenger.mounted) return;
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
                    fontSize: TypeScale.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
          backgroundColor: bgColor,
          shape: RoundedSuperellipseBorder(
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
      ToastType.error => (Icons.error_rounded, scheme.error),
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
/// 显式圆角也使用 Flutter 的连续超椭圆绘制。
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
    this.showBorder = false,
    this.showShadow = false,
    this.smoothing = 0.6,
    this.level = SurfaceLevel.card,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: color ?? level.colorOf(colorScheme),
          shape: RoundedSuperellipseBorder(
            borderRadius: borderRadius ?? BorderRadius.circular(Radii.xl),
            side: showBorder
                ? (border?.top ?? BorderSide(color: colorScheme.hairline))
                : BorderSide.none,
          ),
          shadows: showShadow ? Shadows.card(colorScheme) : null,
        ),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(Spacing.lg),
          child: child,
        ),
      ),
    );
  }
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
    this.showShadow = false,
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
                  Flexible(child: Text(label, textAlign: TextAlign.center)),
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
          Flexible(child: Text(label)),
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
