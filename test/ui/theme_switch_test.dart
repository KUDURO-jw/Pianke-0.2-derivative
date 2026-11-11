// 回归：切换主题不得产生逐帧颜色插值（那是「切深色闪一下」的来源）。
//
// 背景：MaterialApp 默认用 kThemeAnimationDuration（200ms）+
// Curves.linear 把整套颜色从浅插值到深。实测采样到 14 帧中间态：
//   f0f1f4 → dedfe2 → cccdd0 → babbbe → a8a9ac → 96979a → 848588
//   → 737477 → 616265 → 4f5053 → 3d3e41 → 2b2c2f → 191a1d → 101114
// 本项目大量使用固定中性色（SurfaceLevel 刻意不随 seed 染色），
// 这些颜色在插值中间态并不协调，观感就是闪一下。
//
// 修复：MaterialApp.themeAnimationDuration 设为 Duration.zero。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';

class _Theme extends ChangeNotifier {
  ThemeMode mode = ThemeMode.light;
  void toggle() {
    mode = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}

void main() {
  /// 采样主题切换过程中 scaffoldBackgroundColor 的取值序列。
  Future<List<int>> sampleColors(
    WidgetTester tester, {
    required Duration themeAnimationDuration,
  }) async {
    final theme = _Theme();
    final samples = <int>[];

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (context, _) => MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: theme.mode,
          themeAnimationDuration: themeAnimationDuration,
          home: Builder(
            builder: (context) {
              final color = Theme.of(context).scaffoldBackgroundColor;
              if (samples.isEmpty || samples.last != color.toARGB32()) {
                samples.add(color.toARGB32());
              }
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );

    theme.toggle();
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return samples;
  }

  testWidgets('默认主题动画会产生多个中间色（闪屏来源）', (tester) async {
    final samples = await sampleColors(
      tester,
      themeAnimationDuration: kThemeAnimationDuration,
    );
    debugPrint('DIAG 默认动画采样 ${samples.length} 个色值');
    expect(
      samples.length,
      greaterThan(3),
      reason: '这正是逐帧插值造成的闪烁',
    );
  });

  testWidgets('本项目设为零后只有起止两色，无中间态', (tester) async {
    final samples = await sampleColors(
      tester,
      themeAnimationDuration: Duration.zero,
    );
    debugPrint('DIAG 零动画采样 ${samples.length} 个色值');
    expect(
      samples.length,
      2,
      reason: '应当只有「浅色」和「深色」两个状态，中间不产生插值',
    );
    // 首尾必须是两套主题的页面底色，不能是任何中间灰。
    expect(samples.first, AppColors.pageLight.toARGB32());
    expect(samples.last, AppColors.pageDark.toARGB32());
  });
}
