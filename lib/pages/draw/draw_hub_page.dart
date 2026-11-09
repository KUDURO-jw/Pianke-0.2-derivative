// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/app_components.dart';
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
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('draw-hub'),
          slivers: [
            const SliverToBoxAdapter(child: PageHeader(title: '抽片')),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                Spacing.page,
                Spacing.sm,
                Spacing.page,
                DockMetrics.insetOf(context) + Spacing.xxl,
              ),
              sliver: SliverList.list(
                children: [
                  _PrimaryDrawCard(onTap: () => context.push('/draw/start')),
                  const SizedBox(height: Spacing.xxl),
                  Text('抽片历史', style: textTheme.titleMedium),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '最近的决定都在这里',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  const DrawHistoryList(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主入口大卡片 —— 今晚看什么？
class _PrimaryDrawCard extends StatefulWidget {
  final VoidCallback onTap;

  const _PrimaryDrawCard({required this.onTap});

  @override
  State<_PrimaryDrawCard> createState() => _PrimaryDrawCardState();
}

class _PrimaryDrawCardState extends State<_PrimaryDrawCard>
    with SingleTickerProviderStateMixin {
  /// 「开始抽片」按钮呼吸的次数：只在进入页面时提示几下，之后保持静止，
  /// 不再无限循环（省电，也不会一直抢注意力）。
  static const int _breathCycles = 3;

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: Motion.breath,
  );
  bool _breathStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_breathStarted) return;
    _breathStarted = true;
    // 系统开启「减少动态效果」时不呼吸，按钮保持静止。
    if (!MediaQuery.disableAnimationsOf(context)) _runBreath();
  }

  Future<void> _runBreath() async {
    for (var i = 0; i < _breathCycles; i++) {
      await _breath.forward();
      if (!mounted) return;
      await _breath.reverse();
      if (!mounted) return;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(Spacing.xxl),
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: ShapeDecoration(
              color: scheme.blockSurface,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Icon(Icons.casino_outlined, size: 30, color: scheme.accent),
          ),
          const SizedBox(height: Spacing.xxl),
          Text('今晚看什么？', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Spacing.sm),
          Text(
            '从你的片库里，为今晚选一个答案。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.secondaryText),
          ),
          const SizedBox(height: Spacing.xxl),
          SizedBox(
            width: double.infinity,
            child: FadeTransition(
              opacity: Tween<double>(begin: 1.0, end: 0.85).animate(
                CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
              ),
              child: FilledButton.icon(
                onPressed: widget.onTap,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('开始抽片'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
