import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/pages/draw/draw_history_page.dart';

/// 抽片入口页 — 「今晚看什么？」主卡 + 抽片历史
class DrawHubPage extends StatelessWidget {
  const DrawHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingLarge,
            AppTheme.spacingLarge,
            AppTheme.spacingLarge,
            AppTheme.spacingXLarge,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 主入口 —— 今晚看什么？
              _PrimaryDrawCard(onTap: () => context.push('/draw/start')),
              const SizedBox(height: AppTheme.spacingLarge),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '抽片历史',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '最近的决定都在这里',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              const DrawHistoryList(embedded: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主入口大卡片 —— 今晚看什么？
class _PrimaryDrawCard extends StatelessWidget {
  final VoidCallback onTap;

  const _PrimaryDrawCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.accent, AppTheme.accentLight],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: isDark ? 0.35 : 0.25),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '今晚看什么？',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '交给片刻，一键帮你决定',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMedium),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMedium,
                      vertical: AppTheme.spacingSmall,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.casino, size: 18, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          '开始抽片',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.movie_filter_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ],
        ),
      ),
    );
  }
}
