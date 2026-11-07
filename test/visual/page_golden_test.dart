import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/continuous_rrect.dart';

/// 页面级视觉快照：验证整体设计语言（层次 / 间距 / 字号 / 圆角）。
void main() {
  Future<void> pump(WidgetTester tester, Widget child, {Brightness? b}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: b == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('片库页设计稿', (tester) async {
    await pump(tester, const _LibraryMock());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/library_mock.png'),
    );
  });

  testWidgets('片库页设计稿 · 暗色', (tester) async {
    await pump(tester, const _LibraryMock(), b: Brightness.dark);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/library_mock_dark.png'),
    );
  });
}

class _LibraryMock extends StatelessWidget {
  const _LibraryMock();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.pageSurface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 大标题
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.page, Spacing.md, Spacing.page, Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('片库',
                            style: TextStyle(
                              fontSize: TypeScale.headline,
                              fontWeight: FontWeight.w700,
                              color: scheme.primaryText,
                              letterSpacing: -0.6,
                            )),
                        const SizedBox(height: 2),
                        Text('89 部影片',
                            style: TextStyle(
                              fontSize: TypeScale.caption,
                              color: scheme.secondaryText,
                            )),
                      ],
                    ),
                  ),
                  Container(
                    width: 38, height: 38,
                    child: Material(
                      color: scheme.cardSurface,
                      shape: ContinuousRRect(
                        radius: Radii.pill,
                        smoothing: 0.6,
                        side: BorderSide(color: scheme.hairline),
                      ),
                      child: Icon(Icons.add_rounded, size: 20, color: scheme.primaryText),
                    ),
                  ),
                ],
              ),
            ),
            // 搜索框
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.page),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 20, color: scheme.secondaryText),
                    const SizedBox(width: Spacing.sm),
                    Text('搜索片库',
                        style: TextStyle(fontSize: TypeScale.body, color: scheme.secondaryText)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            // 分段控件
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.page),
              child: Container(
                height: 40,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: SurfaceLevel.inset.colorOf(scheme),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Row(
                  children: [
                    _seg(context, scheme, '全部', '89', true),
                    _seg(context, scheme, '未看', '53', false),
                    _seg(context, scheme, '已看', '36', false),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            // 海报网格
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.page, 0, Spacing.page, 100),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.52,
                  crossAxisSpacing: Spacing.gap,
                  mainAxisSpacing: Spacing.lg,
                ),
                itemCount: 4,
                itemBuilder: (_, i) => _posterCard(context, scheme, i),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.lg),
        child: _navBar(context, scheme),
      ),
    );
  }

  Widget _seg(BuildContext c, ColorScheme s, String label, String count, bool on) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: on ? s.cardSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: TypeScale.label,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: on ? s.primaryText : s.secondaryText,
                )),
            const SizedBox(width: 5),
            Text(count,
                style: TextStyle(
                  fontSize: TypeScale.caption,
                  color: s.secondaryText,
                )),
          ],
        ),
      ),
    );
  }

  Widget _posterCard(BuildContext c, ColorScheme s, int i) {
    final colors = [
      [const Color(0xFF3A4A5E), const Color(0xFF8FA8C4)],
      [const Color(0xFF6E4B3A), const Color(0xFFC9A58A)],
      [const Color(0xFF2E3B34), const Color(0xFF7FA08C)],
      [const Color(0xFF4A2E3A), const Color(0xFFB08A9C)],
    ][i];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
                    child: SizedBox(),
                  ),
                ),
                Positioned(
                  left: Spacing.sm, top: Spacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: const Text('0/25',
                        style: TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ),
                Positioned(
                  right: Spacing.sm, top: Spacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: const Text('7.3',
                        style: TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Text(['我不是大师', '悬案', '边境杀手', '暗狼'][i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: TypeScale.bodyLarge,
              fontWeight: FontWeight.w600,
              color: s.primaryText,
            )),
        const SizedBox(height: Spacing.xs),
        Text(['2026', '2026', '2015', '2023'][i],
            style: TextStyle(fontSize: TypeScale.caption, color: s.secondaryText)),
        const SizedBox(height: Spacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: LinearProgressIndicator(
            value: [0.0, 0.06, 0.0, 0.0][i],
            backgroundColor: SurfaceLevel.inset.colorOf(s),
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  Widget _navBar(BuildContext c, ColorScheme s) {
    final items = [
      (Icons.video_library_rounded, '片库'),
      (Icons.casino_outlined, '抽片'),
      (Icons.insights_outlined, '观影'),
      (Icons.settings_outlined, '设置'),
    ];
    // 参考图一的形态：图标在上、文字在下，四项等宽全可见。
    // 选中项只给图标加胶囊底色，文字变强调色——横向更省空间，也不会溢出。
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: s.cardSurface,
        borderRadius: BorderRadius.circular(Radii.pill),
        boxShadow: Shadows.floating(s),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg, vertical: 3),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? s.accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Icon(
                      items[i].$1,
                      size: 21,
                      color: i == 0 ? s.accent : s.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500,
                      color: i == 0 ? s.accent : s.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
