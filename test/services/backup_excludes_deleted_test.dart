// 回归：软删除的条目不得进入备份。
//
// 背景：用户反馈「片库显示 94 部，但上传备份的确认框说 116 部」。
// 根因是 readBackupBundle 直接 `txn.query(table)` 没有过滤
// `deleted_at IS NULL`，把墓碑行一并导出。
//
// 影响不只是数字对不上：
// - 上传云端后，被删掉的条目会跟着同步到别的设备
// - 备份文件体积虚增，且包含用户以为已经删除的内容
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('备份只包含未删除的数据', () {
    test('删除影片后，备份里的影片数与片库计数一致', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      for (var i = 0; i < 5; i++) {
        await storage.addMovie(Movie(id: 'm$i', title: '片$i'));
      }
      await storage.deleteMovie('m0');
      await storage.deleteMovie('m1');

      final liveCount = await storage.countMovies();
      final bundle = await storage.readBackupBundle();

      expect(liveCount, 3);
      expect(
        bundle.movies.length,
        liveCount,
        reason: '备份里的影片数必须与片库可见数一致，'
            '否则「上传」确认框会显示比实际多',
      );
      expect(
        bundle.movies.map((m) => m.id).toSet(),
        {'m2', 'm3', 'm4'},
        reason: '已删除的 m0 / m1 不应出现在备份里',
      );
    });

    test('删除观影会话后，备份里的会话数同步减少', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'm1', title: '片1'));
      for (var i = 0; i < 4; i++) {
        await storage.addSession(
          ViewingSession(
            id: 's$i',
            movieId: 'm1',
            watchedAt: DateTime(2026, 1 + i, 1),
          ),
        );
      }
      await storage.deleteSession('s0');

      final bundle = await storage.readBackupBundle();
      expect(
        bundle.sessions.where((s) => s.id == 's0'),
        isEmpty,
        reason: '已删除的会话不应出现在备份里',
      );
      expect(bundle.sessions.length, 3);
    });

    test('删除标签后，关联表里的孤儿行也被排除', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'm1', title: '片1'));
      final tag = await storage.addTag(MovieTag(id: 't1', name: '测试标签', colorValue: 0xFF00FF00));
      await storage.setMovieTags('m1', {tag.id});

      var bundle = await storage.readBackupBundle();
      expect(bundle.collectionsAndTags['tags'], isNotEmpty);
      expect(bundle.collectionsAndTags['movieTags'], isNotEmpty);

      await storage.deleteTag(tag.id);

      bundle = await storage.readBackupBundle();
      expect(
        bundle.collectionsAndTags['tags'],
        isEmpty,
        reason: '已删除的标签不应出现在备份里',
      );
      expect(
        bundle.collectionsAndTags['movieTags'],
        isEmpty,
        reason: '指向已删除标签的关联行不应出现在备份里',
      );
    });

    test('抽片记录不受影响（该表没有 deleted_at）', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'm1', title: '片1'));
      await storage.addDrawRecord(
        DrawRecord(
          id: 'd1',
          movieId: 'm1',
          movieTitle: '片1',
          moviePoster: '',
          seed: 1,
          candidateCount: 5,
          outcome: DrawOutcome.pending,
          drawnAt: DateTime(2026, 5, 1),
        ),
      );

      final bundle = await storage.readBackupBundle();
      expect(
        bundle.drawRecords.length,
        1,
        reason: '抽片记录表没有 deleted_at，不应被条件误伤而查不到',
      );
    });

    test('全部删除后备份为空，不会因空列表报错', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      await storage.addMovie(Movie(id: 'm1', title: '片1'));
      await storage.deleteMovie('m1');

      final bundle = await storage.readBackupBundle();
      expect(bundle.movies, isEmpty);
      expect(await storage.countMovies(), 0);
    });

    test('备份 → 导入往返后，已删除的条目不会复活', () async {
      // 这是这个 bug 最实际的后果：
      // 删除是软删除，墓碑行留在表里。如果备份把它们带上，
      // _replaceAllInTxn 会先全删再插入，而 _stamp 写的是
      // deleted_at: null —— 于是「已删除」的条目在导入后变成正常影片。
      //
      // 修复后备份里本就只有活数据，往返不会让任何东西复活。
      final source = await openTestStorage();
      addTearDown(source.closeForTest);

      for (var i = 0; i < 4; i++) {
        await source.addMovie(Movie(id: 'm$i', title: '片$i'));
      }
      await source.deleteMovie('m0');
      await source.deleteMovie('m1');

      final bundle = await source.readBackupBundle();
      expect(bundle.movies.length, 2, reason: '备份应只含 2 部存活影片');

      // 导入到另一个库。
      final target = await openTestStorage();
      addTearDown(target.closeForTest);

      final fingerprint = await target.localFingerprint();
      await target.replaceBackupDataIfUnchanged(
        expectedFingerprint: fingerprint,
        movies: bundle.movies,
        drawRecords: bundle.drawRecords,
        sessions: bundle.sessions,
        tableData: bundle.collectionsAndTags,
      );

      expect(
        await target.countMovies(),
        2,
        reason: '导入后片库应只有 2 部，不能把墓碑行复活成正常影片',
      );
      final ids = (await target.queryMovies(limit: 100, offset: 0))
          .map((m) => m.id)
          .toSet();
      expect(ids, {'m2', 'm3'});
    });
  });
}
