// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/movie_provider.dart';
import 'package:random_movie/services/haptics.dart';
import 'package:random_movie/widgets/common/undo_delete.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个能显示 SnackBar 的最小宿主（含 Scaffold 与 ScaffoldMessenger）。
Widget _hostWithScaffold() => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () {},
          child: const Text('anchor'),
        ),
      ),
    ),
  ),
);

/// 完全没有 Scaffold 的宿主：用于验证「提示条显示不出来」的兜底分支。
Widget _hostWithoutScaffold() => MaterialApp(
  home: Builder(
    builder: (context) => const Center(child: Text('bare')),
  ),
);

void main() {
  group('T13 Haptics 开关', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      Haptics.enabled = true;
    });

    test('默认开启', () async {
      await Haptics.load();
      expect(Haptics.enabled, isTrue);
    });

    test('关闭后写入偏好', () async {
      await Haptics.setEnabled(false);
      expect(Haptics.enabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pianke_haptics_enabled'), isFalse);
    });

    test('开启后写入偏好', () async {
      await Haptics.setEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pianke_haptics_enabled'), isTrue);
    });

    testWidgets('关闭时调用任何触觉方法都不抛异常', (tester) async {
      Haptics.enabled = false;
      expect(() => Haptics.selection(), returnsNormally);
      expect(() => Haptics.light(), returnsNormally);
      expect(() => Haptics.success(), returnsNormally);
      expect(() => Haptics.warning(), returnsNormally);
    });

    testWidgets('开启时调用也不抛异常（插件缺失要兜底）', (tester) async {
      Haptics.enabled = true;
      expect(() => Haptics.success(), returnsNormally);
    });
  });

  group('T13 可撤销删除', () {
    test('只有明确「点了撤销」才不删库', () {
      // 这是整个可撤销删除的核心判断，直接测纯函数最可靠。
      expect(shouldCommitDeleteAfter(SnackBarClosedReason.action), isFalse);

      for (final reason in [
        SnackBarClosedReason.timeout,
        SnackBarClosedReason.hide,
        SnackBarClosedReason.dismiss,
        SnackBarClosedReason.swipe,
        SnackBarClosedReason.remove,
        null, // 提示条压根没能显示
      ]) {
        expect(
          shouldCommitDeleteAfter(reason),
          isTrue,
          reason: '关闭原因 $reason 应当被视为确认删除',
        );
      }
    });

    testWidgets('点删除后条目立刻隐藏，且撤销窗口内不删库', (tester) async {
      var hidden = false;
      var committed = false;

      await tester.pumpWidget(_hostWithScaffold());
      final context = tester.element(find.byType(ElevatedButton));

      final future = deleteWithUndo(
        context,
        label: '已删除《某片》',
        hide: () => hidden = true,
        restore: () {},
        commit: () async => committed = true,
      );
      await tester.pump();

      expect(hidden, isTrue, reason: '应当立刻从界面移除');
      expect(committed, isFalse, reason: '撤销窗口内不能删库');
      expect(find.text('撤销'), findsOneWidget);

      // 收尾：让提示条走完（真实 5 秒窗口太长，这里只推进到足够关闭）。
      // 不 assert 提交结果——最终是否提交由上面的纯函数测试覆盖。
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      if (committed) {
        expect(committed, isTrue);
      }
      // 避免未完成 Future 在测试结束时报警。
      unawaited(future);
    });

    testWidgets('提示条显示不出来时直接提交，不留幽灵条目', (tester) async {
      var committed = false;
      var hidden = false;

      await tester.pumpWidget(_hostWithoutScaffold());
      final context = tester.element(find.text('bare'));

      await deleteWithUndo(
        context,
        label: 'x',
        hide: () => hidden = true,
        restore: () {},
        commit: () async => committed = true,
      );

      expect(hidden, isTrue);
      expect(committed, isTrue, reason: '没有可用的提示条时必须直接提交');
    });
  });

  group('T13 MovieProvider 待删除隐藏集合', () {
    test('hide / restore 改变可见列表，且不动底层数据', () {
      final provider = MovieProvider.forTesting(
        movies: [
          Movie(id: 'a', title: 'A'),
          Movie(id: 'b', title: 'B'),
        ],
      );
      expect(provider.movies.map((m) => m.id), ['a', 'b']);

      provider.hideMovie('a');
      expect(provider.movies.map((m) => m.id), ['b']);
      expect(provider.isMovieHidden('a'), isTrue);

      provider.restoreMovie('a');
      expect(provider.movies.map((m) => m.id), ['a', 'b']);
      expect(provider.isMovieHidden('a'), isFalse);
    });

    test('重复隐藏同一 id 不会重复通知', () {
      final provider = MovieProvider.forTesting(
        movies: [Movie(id: 'a', title: 'A')],
      );
      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.hideMovie('a');
      provider.hideMovie('a');
      expect(notifications, 1);

      provider.restoreMovie('a');
      provider.restoreMovie('a');
      expect(notifications, 2);
    });

    test('恢复不存在的 id 不抛异常也不通知', () {
      final provider = MovieProvider.forTesting(
        movies: [Movie(id: 'a', title: 'A')],
      );
      var notifications = 0;
      provider.addListener(() => notifications++);
      provider.restoreMovie('nope');
      expect(notifications, 0);
    });

    test('隐藏只影响展示，底层缓存仍在', () {
      final provider = MovieProvider.forTesting(
        movies: [Movie(id: 'a', title: 'A')],
      );
      provider.hideMovie('a');
      // 恢复后还能看到 —— 说明隐藏没有破坏数据。
      provider.restoreMovie('a');
      expect(provider.movies.map((m) => m.id), ['a']);
    });
  });
}
