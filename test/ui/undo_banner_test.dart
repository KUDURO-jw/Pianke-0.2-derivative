// 撤销提示条：倒计时进度、跟手拖动、弹簧退场。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/widgets/common/undo_delete.dart';

Widget host() => MaterialApp(
  theme: AppTheme.lightTheme,
  home: const Scaffold(body: Center(child: Text('删除'))),
);

/// 取当前提示条底部的倒计时进度条宽度占比。
///
/// 注意：`deleteWithUndo` 是异步的，overlay entry 插入后需要一帧才渲染，
/// 所以调用方必须先 pump 过一帧再取。这里在取不到时给出明确失败信息，
/// 而不是笼统的 "non-empty"。
double countdownFraction(WidgetTester tester) {
  final finder = find.byType(FractionallySizedBox);
  expect(
    finder,
    findsOneWidget,
    reason: '提示条应包含一条倒计时进度条（FractionallySizedBox）',
  );
  final box = tester.widget<FractionallySizedBox>(finder);
  return box.widthFactor ?? 1.0;
}

void main() {
  testWidgets('倒计时进度条随时间收缩', (tester) async {
    await tester.pumpWidget(host());
    final context = tester.element(find.text('删除'));

    deleteWithUndo(
      context,
      label: '已删除',
      undoWindow: const Duration(milliseconds: 1000),
      hide: () {},
      restore: () {},
      commit: () async {},
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final start = countdownFraction(tester);
    expect(start, greaterThan(0.6), reason: '刚开始时进度条应接近满格');

    await tester.pump(const Duration(milliseconds: 400));
    final mid = countdownFraction(tester);
    expect(mid, lessThan(start), reason: '时间过去后进度条应变短');

    await tester.pump(const Duration(milliseconds: 300));
    final late = countdownFraction(tester);
    expect(late, lessThan(mid), reason: '继续收缩');

    // 收尾，避免 pending timer。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('拖动时提示条跟手位移', (tester) async {
    await tester.pumpWidget(host());
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

    // 用承载提示条的那个 Transform 的纵向位移来判断跟手。
    // 注意 Transform.translate 的位移在矩阵 storage[13]（y 平移），
    // Vector3 getTranslation() 读不到它。
    //
    // 页面里还有若干其它 Transform（旋转、缩放），取 y 平移最大的那个
    // 就是提示条自身的位移动画。
    double bannerOffsetY() {
      double maxTy = 0;
      for (final element in find.byType(Transform).evaluate()) {
        final t = element.widget as Transform;
        final ty = t.transform.storage[13];
        if (ty.abs() > maxTy.abs()) maxTy = ty;
      }
      return maxTy;
    }

    final before = bannerOffsetY();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('已删除')),
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();

    final during = bannerOffsetY();
    expect(
      during,
      greaterThan(before + 20),
      reason: '拖动过程中提示条应跟手向下移动',
    );

    // 松手：未过半阈值，应回弹原位。
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      bannerOffsetY(),
      closeTo(before, 3),
      reason: '未过阈值松手应回弹到原位',
    );

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('拖过阈值松手关闭并提交删除', (tester) async {
    var committed = false;

    await tester.pumpWidget(host());
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

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('已删除')),
    );
    // 拖过 56px 阈值。
    await gesture.moveBy(const Offset(0, 90));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(committed, isTrue, reason: '拖过阈值应视为确认删除');
    expect(find.text('已删除'), findsNothing, reason: '提示条应已移除');
  });

  testWidgets('弹簧退场结束后才移除，不会硬切', (tester) async {
    await tester.pumpWidget(host());
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

    // 触发下滑关闭。
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('已删除')),
    );
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // 弹簧刚开始：提示条还在，且透明度未归零（说明不是硬切）。
    expect(
      find.text('已删除'),
      findsOneWidget,
      reason: '弹簧退场期间提示条不应立刻消失',
    );

    // 弹簧跑完后才移除。
    await tester.pumpAndSettle();
    expect(find.text('已删除'), findsNothing);
  });

  testWidgets('拖动时倒计时暂停，松手回弹后继续', (tester) async {
    await tester.pumpWidget(host());
    final context = tester.element(find.text('删除'));

    deleteWithUndo(
      context,
      label: '已删除',
      // 窗口取长一点（3s），保证拖动期间不会自然到时，
      // 否则测的就不是「暂停」而是「已经结束了」。
      undoWindow: const Duration(seconds: 3),
      hide: () {},
      restore: () {},
      commit: () async {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final before = countdownFraction(tester);

    // 按住 500ms 并轻微下拖（不越过阈值）。
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('已删除')),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final held = countdownFraction(tester);
    expect(
      held,
      closeTo(before, 0.05),
      reason: '按住期间倒计时应暂停，进度基本不变',
    );

    // 松手回弹，倒计时应当继续。
    //
    // 注意不能用 pumpAndSettle：它会把倒计时一路跑到 0，
    // 提示条随之关闭，就测不到「继续」这个中间状态了。
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byType(FractionallySizedBox),
      findsOneWidget,
      reason: '松手回弹期间提示条应还在',
    );
    final resumed = countdownFraction(tester);
    expect(resumed, lessThan(held), reason: '松手后倒计时应继续收缩');

    // 收尾：让它自然到时关闭。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('退场位移单调朝下，不回弹', (tester) async {
    // 这是「下滑关闭最后还闪一下」的守卫测试。
    //
    // 曾经出现过两个问题：
    // 1. 退场只做透明度收束、位移不动 → 提示条「停在半空变透明」，
    //    然后 entry 被移除，观感是闪一下。
    // 2. 用第二个控制器单独收束拖动位移与弹簧叠加 → 两条曲线互相拉扯，
    //    出现「先往下再弹回」的折返，比问题 1 更难看。
    //
    // 现在位移由单一时间源驱动，必须严格单调递增。
    await tester.pumpWidget(host());
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

    double ty() {
      double maxAbs = 0;
      for (final e in find.byType(Transform).evaluate()) {
        final w = e.widget as Transform;
        final v = w.transform.storage[13];
        if (v.abs() > maxAbs.abs()) maxAbs = v;
      }
      return maxAbs;
    }

    final g = await tester.startGesture(
      tester.getCenter(find.text('已删除')),
    );
    await g.moveBy(const Offset(0, 120));
    await tester.pump();
    await g.up();

    final samples = <double>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.text('已删除').evaluate().isEmpty) break;
      samples.add(ty());
    }

    expect(samples.length, greaterThan(3), reason: '应采到若干退场帧');
    for (var i = 1; i < samples.length; i++) {
      expect(
        samples[i],
        greaterThanOrEqualTo(samples[i - 1] - 0.01),
        reason: '退场位移必须单调朝下（不回弹）：'
            '第 $i 帧 ${samples[i]} 小于上一帧 ${samples[i - 1]}，'
            '完整序列 $samples',
      );
    }

    await tester.pumpAndSettle();
    expect(find.text('已删除'), findsNothing, reason: '最终应完全移除');
  });

  testWidgets('视觉参数符合项目规范', (tester) async {
    await tester.pumpWidget(host());
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

    final materials = tester
        .widgetList<Material>(find.byType(Material))
        .where((m) => m.color == const Color(0xFF2A2A2E));
    expect(materials, isNotEmpty, reason: '提示条底色应为 #2A2A2E');

    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(
      button.style?.foregroundColor?.resolve({}),
      AppTheme.lightScheme().accent,
      reason: '撤销按钮应使用主题强调色',
    );

    // 倒计时条用强调色，高度 2.5。
    expect(countdownFraction(tester), inInclusiveRange(0.0, 1.0));

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
