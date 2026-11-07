import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/app_components.dart';

/// 验证真实组件库的渲染效果（非 mock）。
void main() {
  testWidgets('组件库样张', (tester) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor:
              SurfaceLevel.page.colorOf(AppTheme.lightScheme()),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PageHeader(title: '片库', subtitle: '共 89 部 · 已看 36 部'),
                  const SizedBox(height: Spacing.md),
                  AppSearchField(
                    controller: TextEditingController(),
                    hint: '搜索片库',
                  ),
                  const SizedBox(height: Spacing.lg),
                  const SegmentedSwitch(
                    labels: ['全部', '未看', '已看'],
                    counts: [89, 53, 36],
                    selectedIndex: 0,
                    onChanged: _noop,
                  ),
                  const SizedBox(height: Spacing.lg),
                  AppCard(
                    child: Row(
                      children: const [
                        Expanded(child: StatBlock(value: '39', label: '本月观影', icon: Icons.play_arrow_rounded)),
                        Expanded(child: StatBlock(value: '292', label: '累计记录', icon: Icons.history_rounded)),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.gap),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.movie_filter_rounded,
                                size: 18, color: Color(0xFF8A8D93)),
                            const SizedBox(width: 6),
                            const Text('最近记录',
                                style: TextStyle(
                                    fontSize: TypeScale.title,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: Spacing.md),
                        AppTileGroup(
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 60,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3A4A5E),
                                  borderRadius: BorderRadius.circular(Radii.sm),
                                ),
                              ),
                              const SizedBox(width: Spacing.md),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text('我不是大师',
                                      style: TextStyle(
                                          fontSize: TypeScale.bodyLarge,
                                          fontWeight: FontWeight.w600)),
                                  SizedBox(height: 3),
                                  Text('⭐ 7.3 · 2026',
                                      style: TextStyle(
                                          fontSize: TypeScale.caption,
                                          color: Color(0xFF8A8D93))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.gap),
                  const CompactStats(
                    items: [('39', '实时连接'), ('292', '最近请求'), ('403', 'DNS 查询')],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/components.png'),
    );
  });

  testWidgets('底部导航', (tester) async {
    tester.view.physicalSize = const Size(1170, 400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor:
              SurfaceLevel.page.colorOf(AppTheme.lightScheme()),
          body: const Center(child: Text('页面内容')),
          bottomNavigationBar: FloatingNavBar(
            currentIndex: 0,
            onSelected: _noopIndex,
            items: const [
              NavItemData(
                icon: Icons.video_library_rounded,
                selectedIcon: Icons.video_library_rounded,
                label: '片库',
              ),
              NavItemData(
                icon: Icons.casino_outlined,
                selectedIcon: Icons.casino_rounded,
                label: '抽片',
              ),
              NavItemData(
                icon: Icons.insights_outlined,
                selectedIcon: Icons.insights_rounded,
                label: '观影',
              ),
              NavItemData(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/navbar.png'),
    );
  });
}

void _noop(int _) {}
void _noopIndex(int _) {}
