// 回归：软删除后重新添加同一部影片不得主键冲突。
//
// 背景：movies.id 是主键，软删除只是给 deleted_at 赋值，行还在表里。
// getMovieById / _getMovieByDoubanSubjectId 都带 deleted_at IS NULL，
// 看不见墓碑行，于是「查重通过 → INSERT → UNIQUE constraint failed」。
// 用户看到「保存失败: DatabaseException(UNIQUE constraint failed: movies.id)」。
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/services/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_db.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('软删除后重新添加', () {
    test('同一 douban id 删了再加不应抛主键冲突', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      final movie = Movie(
        id: 'douban_20326665',
        title: '星球大战7：原力觉醒',
        year: '2015',
        doubanUrl: 'https://movie.douban.com/subject/20326665/',
      );

      await storage.addMovie(movie);
      await storage.deleteMovie(movie.id);

      // 删掉之后 getMovieById 返回 null（墓碑行被过滤）。
      expect(await storage.getMovieById(movie.id), isNull);

      // 重新添加：修复前这里会抛 UNIQUE constraint failed。
      final readded = await storage.addMovie(
        movie.copyWith(title: '星球大战7：原力觉醒（重看）'),
      );

      expect(readded.id, movie.id);
      final loaded = await storage.getMovieById(movie.id);
      expect(loaded, isNotNull, reason: '复活后应当能查到');
      expect(loaded!.title, '星球大战7：原力觉醒（重看）');
    });

    test('复活后旧数据被新内容覆盖', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      final original = Movie(
        id: 'douban_111',
        title: '旧标题',
        year: '2000',
        doubanUrl: 'https://movie.douban.com/subject/111/',
      );
      await storage.addMovie(original);
      await storage.deleteMovie(original.id);

      await storage.addMovie(
        Movie(
          id: 'douban_111',
          title: '新标题',
          year: '2024',
          doubanUrl: 'https://movie.douban.com/subject/111/',
        ),
      );

      final loaded = await storage.getMovieById('douban_111');
      expect(loaded!.title, '新标题');
      expect(loaded.year, '2024');
    });

    test('未删除的影片仍判定为重复，不静默覆盖', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      final movie = Movie(
        id: 'douban_222',
        title: '正常影片',
        doubanUrl: 'https://movie.douban.com/subject/222/',
      );
      await storage.addMovie(movie);

      // 没删过就重复添加，应当抛 DuplicateMovieException 而不是覆盖。
      expect(
        () => storage.addMovie(movie.copyWith(title: '改名')),
        throwsA(isA<DuplicateMovieException>()),
      );
    });

    test('按 douban_url 匹配的旧 id 也能复活', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      // 旧版用的是纯数字 id。
      final legacy = Movie(
        id: '333',
        title: '旧版 id',
        doubanUrl: 'https://movie.douban.com/subject/333/',
      );
      await storage.addMovie(legacy);
      await storage.deleteMovie(legacy.id);

      final readded = await storage.addMovie(
        Movie(
          id: '333',
          title: '旧版 id 复活',
          doubanUrl: 'https://movie.douban.com/subject/333/',
        ),
      );
      expect(readded.id, '333');
      expect((await storage.getMovieById('333'))!.title, '旧版 id 复活');
    });

    test('复活后片库计数不重复', () async {
      final storage = await openTestStorage();
      addTearDown(storage.closeForTest);

      final movie = Movie(
        id: 'douban_444',
        title: '计数测试',
        doubanUrl: 'https://movie.douban.com/subject/444/',
      );
      await storage.addMovie(movie);
      expect(await storage.countMovies(), 1);

      await storage.deleteMovie(movie.id);
      expect(await storage.countMovies(), 0);

      await storage.addMovie(movie);
      expect(await storage.countMovies(), 1, reason: '复活不应产生两条记录');
    });
  });
}
