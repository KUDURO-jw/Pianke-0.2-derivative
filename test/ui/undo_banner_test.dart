// 验证自绘撤销条：自动消失、点撤销、下滑关闭、视觉参数。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/undo_delete.dart';

Widget host({required VoidCallback onDelete}) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: onDelete,
          child: const Text('删除'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('提示条在 undoWindow 后自动消失并提交删除', (tester) async {
    var committed = false;
    var hidden = false;
    var restored = false;

    await tester.pumpWidget(
      host(
        onDelete: () {},
      ),
    );

    final context = tester.element(find.text('删除'));

    // 直接调用，不经过按钮回调，便于控制时序。
    deleteWithUndo(
      context,
      label: '已删除《测试》',
      undoWindow: const Duration(milliseconds: 500),
      hide: () => hidden = true,
      restore: () => restored = true,
      commit: () async => committed = true,
    );

    await tester.pump();
    expect(hidden, isTrue, reason: '条目应立即从界面消失');
    expect(find.text('已删除《测试》'), findsOneWidget, reason: '应显示撤销提示条');

    // 推进超过 undoWindow。
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(
      find.text('已删除《测试》'),
      findsNothing,
      reason: '提示条应自动消失，不该要求用户手动下滑',
    );
    expect(committed, isTrue, reason: '超时后应真正提交删除');
    expect(restored, isFalse);
  });

  testWidgets('点撤销后提示条消失且不提交删除', (tester) async {
    var committed = false;
    var restored = false;

    await tester.pumpWidget(host(onDelete: () {}));
    final context = tester.element(find.text('删除'));

    deleteWithUndo(
      context,
      label: '已删除',
      undoWindow: const Duration(seconds: 5),
      hide: () {},
      restore: () => restored = true,
      commit: () async => committed = true,
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(restored, isTrue);
    expect(committed, isFalse, reason: '点了撤销就不该删库');
    expect(find.text('已删除'), findsNothing, reason: '点撤销后提示条也应消失');
  });

  testWidgets('下滑关闭视为确认删除', (tester) async {
    var committed = false;

    await tester.pumpWidget(host(onDelete: () {}));
    final context = tester.element(find.text('删除'));

    deleteWithUndo(
      context,
      label: '已删除',
      undoWindow: const Duration(seconds: 5),
      hide: () {},
      restore: () {},
      commit: () async => committed = true,
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 向下快速拖动。
    await tester.fling(find.text('已删除'), const Offset(0, 200), 800);
    await tester.pumpAndSettle();

    expect(committed, isTrue, reason: '下滑关闭应视为确认删除');
    expect(find.text('已删除'), findsNothing);
  });

  testWidgets('视觉参数符合项目规范', (tester) async {
    await tester.pumpWidget(host(onDelete: () {}));
    final context = tester.element(find.text('删除'));

    deleteWithUndo(
      context,
      label: '已删除',
      undoWindow: const Duration(seconds: 5),
      hide: () {},
      restore: () {},
      commit: () async {},
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 深色胶囊 #2A2A2E，与全局 snackBarTheme 一致。
    final materials = tester
        .widgetList<Material>(find.byType(Material))
        .where((m) => m.color == const Color(0xFF2A2A2E));
    expect(
      materials,
      isNotEmpty,
      reason: '提示条底色应为 #2A2A2E，与全局 snackBarTheme 一致',
    );

    // 撤销按钮存在且用主题强调色。
    final button = tester.widget<TextButton>(find.byType(TextButton));
    final foreground = button.style?.foregroundColor?.resolve({});
    expect(foreground, isNotNull, reason: '撤销按钮应有前景色');
    expect(
      foreground,
      AppTheme.lightScheme().accent,
      reason: '撤销按钮应使用主题强调色',
    );

    // 收尾：让提示条的 5 秒窗口走完，避免测试结束时留下 pending timer。
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
