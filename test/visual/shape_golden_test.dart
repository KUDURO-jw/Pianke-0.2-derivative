import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/continuous_rrect.dart';

/// 视觉快照测试：把关键组件渲染成 PNG，供人工检查圆角、层次、间距。
///
/// 运行：flutter test test/visual --update-goldens
/// 产物：test/visual/goldens/*.png
void main() {
  Future<void> pumpAt(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: SurfaceLevel.page.colorOf(AppTheme.lightScheme()),
          body: Center(child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 用 Material 承载连续圆角（BoxDecoration 只接受 BorderRadius）。
  Widget squircleBox({
    required double width,
    required double height,
    required double radius,
    required Color color,
    BorderSide side = BorderSide.none,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: color,
        shape: ContinuousRRect(radius: radius, smoothing: 0.6, side: side),
        clipBehavior: Clip.antiAlias,
        child: const SizedBox.expand(),
      ),
    );
  }

  testWidgets('形状对照：连续圆角 vs 普通圆角', (tester) async {
    await pumpAt(
      tester,
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          squircleBox(
            width: 240,
            height: 140,
            radius: Radii.xl,
            color: const Color(0xFF2F6BFF),
          ),
          const SizedBox(height: 10),
          const Text('↑ 连续圆角',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 24),
          Container(
            width: 240,
            height: 140,
            decoration: BoxDecoration(
              color: const Color(0xFF2F6BFF),
              borderRadius: BorderRadius.circular(Radii.xl),
            ),
          ),
          const SizedBox(height: 10),
          const Text('↑ 普通圆角',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 24),
          squircleBox(
            width: 240,
            height: 140,
            radius: Radii.xl,
            color: Colors.white,
            side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
          ),
          const SizedBox(height: 10),
          const Text('↑ 带描边',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/shape_compare.png'),
    );
  });

  testWidgets('表面层次', (tester) async {
    await pumpAt(
      tester,
      Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Container(
            width: 320,
            color: SurfaceLevel.page.colorOf(scheme),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final level in SurfaceLevel.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: squircleBox(
                      width: 288,
                      height: 56,
                      radius: Radii.lg,
                      color: level.colorOf(scheme),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/surface_levels.png'),
    );
  });
}
