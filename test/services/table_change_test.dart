// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:random_movie/services/table_change_notifier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('T5b 变更流：写操作会发出被改动的表', () {
    test('新增影片会通知 movies 表', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      final received = <Set<String>>[];
      final sub = storage.tableChanges.listen(received.add);
      addTearDown(sub.cancel);

      await storage.addMovie(Movie(id: 'm1', title: '影片'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, isNotEmpty);
      expect(received.last, contains('movies'));
    });

    test('更新影片会通知', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'm1', title: '原名'));

      final received = <Set<String>>[];
      final sub = storage.tableChanges.listen(received.add);
      addTearDown(sub.cancel);

      await storage.updateMovie(Movie(id: 'm1', title: '新名'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received.last, contains('movies'));
    });

    test('删除影片会同时通知影片与其子表', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'm1', title: '影片'));

      final received = <Set<String>>[];
      final sub = storage.tableChanges.listen(received.add);
      addTearDown(sub.cancel);

      await storage.deleteMovie('m1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received.last, containsAll(<String>['movies', 'viewing_sessions']));
    });

    test('新增会话通知 viewing_sessions', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'm1', title: '影片'));

      final received = <Set<String>>[];
      final sub = storage.tableChanges.listen(received.add);
      addTearDown(sub.cancel);

      await storage.addSession(
        ViewingSession(
          id: 's1',
          movieId: 'm1',
          watchedAt: DateTime(2026, 1, 1),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received.last, contains('viewing_sessions'));
    });

    test('删除会话（软删除）也通知', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'm1', title: '影片'));
      await storage.addSession(
        ViewingSession(
          id: 's1',
          movieId: 'm1',
          watchedAt: DateTime(2026, 1, 1),
        ),
      );

      final received = <Set<String>>[];
      final sub = storage.tableChanges.listen(received.add);
      addTearDown(sub.cancel);

      await storage.deleteSession('s1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received.last, contains('viewing_sessions'));
    });
  });

  group('T5b 变更流：失败的操作不应触发刷新', () {
    test('插入重复影片抛错时不发通知', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'dup', title: '影片'));

      final received = <Set<String>>[];
      final sub = storage.tableChanges.listen(received.add);
      addTearDown(sub.cancel);

      // 同 id 再插一次会抛 DuplicateMovieException。
      await expectLater(
        storage.addMovie(Movie(id: 'dup', title: '重复')),
        throwsA(isA<DuplicateMovieException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        received,
        isEmpty,
        reason: '失败的操作不该让界面去刷新（用户会看到闪一下又变回去）',
      );
    });
  });

  group('T5b TableChangeNotifier：防抖合并', () {
    test('连续多次变更合并成一次通知', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      final notifier = TableChangeNotifier(
        storage,
        // 防抖窗口取得足够宽（200ms）：三次真实 SQLite 写入在并发测试机
        // 上可能各自耗时几十毫秒，窗口只有 40ms 时偶发「第 2、3 次写入
        // 落在窗口外」，于是合并成 2 次通知，测试随机失败。
        // 这个用例要验证的是「窗口内的多次变更被合并」，不是「写入有多快」。
        debounce: const Duration(milliseconds: 200),
      );
      addTearDown(notifier.dispose);
      var notifications = 0;
      notifier.addListener(() => notifications++);

      // 连续写入三次，间隔小于防抖窗口。
      await storage.addMovie(Movie(id: 'a', title: 'A'));
      await storage.addMovie(Movie(id: 'b', title: 'B'));
      await storage.addMovie(Movie(id: 'c', title: 'C'));

      // 防抖窗口内还不该通知。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 等待防抖窗口过去。
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(notifier.rawNotificationCount, greaterThanOrEqualTo(3));
      expect(
        notifications,
        1,
        reason: '三次变更应当合并成一次界面刷新',
      );
    });

    test('只关心指定表时，无关变更被忽略', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);
      await storage.addMovie(Movie(id: 'm1', title: '影片'));

      final notifier = TableChangeNotifier(
        storage,
        debounce: const Duration(milliseconds: 20),
        watchTables: const {'viewing_sessions'},
      );
      addTearDown(notifier.dispose);
      var notifications = 0;
      notifier.addListener(() => notifications++);

      // 改影片：不在关注列表，应当被忽略。
      await storage.updateMovie(Movie(id: 'm1', title: '改名'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(notifications, 0);

      // 加会话：在关注列表，应当通知。
      await storage.addSession(
        ViewingSession(
          id: 's1',
          movieId: 'm1',
          watchedAt: DateTime(2026, 2, 1),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(notifications, 1);
    });

    test('dispose 之后不再通知，也不会因迟到事件报错', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      final notifier = TableChangeNotifier(
        storage,
        debounce: const Duration(milliseconds: 50),
      );
      notifier.dispose();

      // 通知器已销毁，写入不应引发异常。
      await storage.addMovie(Movie(id: 'x', title: 'X'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // 没有断言崩就说明安全（test 框架会把未捕获异常记为失败）。
    });

    test('triggerNow 立即通知（用于强制刷新）', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      final notifier = TableChangeNotifier(storage);
      addTearDown(notifier.dispose);
      var notifications = 0;
      notifier.addListener(() => notifications++);

      notifier.triggerNow();
      expect(notifications, 1);
    });
  });

  group('T5b 端到端：改影片后列表能拿到新数据', () {
    test('更新后重新查询能看到新标题（无需手动 refresh 调用点）', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'm1', title: '旧标题'));
      final before = await storage.getMovieById('m1');
      expect(before!.title, '旧标题');

      // 模拟界面订阅：收到通知后重新查询。
      String? observedTitle;
      final notifier = TableChangeNotifier(
        storage,
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(notifier.dispose);
      notifier.addListener(() async {
        final movie = await storage.getMovieById('m1');
        observedTitle = movie?.title;
      });

      await storage.updateMovie(Movie(id: 'm1', title: '新标题'));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(observedTitle, '新标题');
    });
  });
}
