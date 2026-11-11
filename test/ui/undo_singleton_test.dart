// 回归：连续删除多个影片时的提示条行为。
//
// 用户反馈：「一定时间内删除多个，底下状态栏会显示多个，然后卡顿 + 闪屏」。
// 根因是 _showUndoBanner 每次都 overlay.insert 一条新 entry，没有做单例，
// 同时删三部会叠三层提示条，每层各跑倒计时与弹簧动画。
//
// 设计：全局只保留一条。新提示出现时，旧提示立刻关闭（按「被顶掉」处理
// → 确认删除前一部），这样每一部都会被正确提交，界面永远只有一条。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/widgets/common/undo_delete.dart';

Widget host() => MaterialApp(
  theme: AppTheme.lightTheme,
  home: const Scaffold(body: Center(child: Text('删除'))),
);

void main() {
  group('撤销提示条全局单例', () {
    testWidgets('连续删除三次，界面上只有一条提示', (tester) async {
      await tester.pumpWidget(host());
      final context = tester.element(find.text('删除'));

      for (var i = 0; i < 3; i++) {
        deleteWithUndo(
          context,
          label: '已删除第$i部',
          undoWindow: const Duration(seconds: 5),
          hide: () {},
          restore: () {},
          commit: () async {},
        );
        // 每次之间推进一点，模拟用户连续点击。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
      }

      await tester.pump(const Duration(milliseconds: 150));

      // 只应存在最后一条文案。
      expect(
        find.text('已删除第2部'),
        findsOneWidget,
        reason: '最后一条提示应当显示',
      );
      expect(
        find.text('已删除第0部'),
        findsNothing,
        reason: '第一条应被顶掉，不能叠加',
      );
      expect(
        find.text('已删除第1部'),
        findsNothing,
        reason: '第二条应被顶掉，不能叠加',
      );

      // 收尾。
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('被顶掉的提示按「确认删除」提交，不会丢删除', (tester) async {
      await tester.pumpWidget(host());
      final context = tester.element(find.text('删除'));

      final committed = <int>[];

      for (var i = 0; i < 2; i++) {
        deleteWithUndo(
          context,
          label: '已删除第$i部',
          undoWindow: const Duration(seconds: 5),
          hide: () {},
          restore: () {},
          commit: () async => committed.add(i),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
      }

      // 让第一次的退场弹簧跑完。
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        committed,
        contains(0),
        reason: '被顶掉的第一条也必须提交删除，否则它既从界面消失、'
            '又没写进数据库，重启后会「复活」',
      );

      // 收尾第二条。
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('只有一条提示时，超时后正常提交', (tester) async {
      await tester.pumpWidget(host());
      final context = tester.element(find.text('删除'));

      var committed = false;
      deleteWithUndo(
        context,
        label: '已删除',
        undoWindow: const Duration(milliseconds: 400),
        hide: () {},
        restore: () {},
        commit: () async => committed = true,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(committed, isTrue);
      expect(find.text('已删除'), findsNothing);
    });
  });
}
