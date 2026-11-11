// 回归：限流退避重试。
//
// 背景：豆瓣的限流是短窗口。用户反馈「刚进去添加报错 403，过几秒就好了」。
// 与其把这个窗口暴露给用户，不如内部退避重试（1s / 2s，最多 3 次）。
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/movie_scraper_service.dart';

/// 记录调用次数、按脚本返回结果或抛错的 Dio 替身。
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);

  /// 每次调用的行为：返回 (statusCode, body) 或抛 DioException。
  final List<Object> script;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = calls < script.length ? calls : script.length - 1;
    calls++;
    final step = script[index];

    if (step is DioException) throw step;

    final tuple = step as (int, String);
    return ResponseBody.fromString(
      tuple.$2,
      tuple.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  group('限流退避重试', () {
    test('搜索遇到 403 会退避重试，最终成功', () async {
      final adapter = _ScriptedAdapter([
        (403, 'rate limited'),
        (403, 'rate limited'),
        (200, '<html>window.__DATA__ = {"items":[]}</html>'),
      ]);
      final service = MovieScraperService(dio: _dioWith(adapter));

      final results = await service.searchMovies('测试');

      expect(results, isEmpty);
      expect(adapter.calls, 3, reason: '应当在第三次尝试时成功');
    });

    test('搜索连续 403 超过上限后抛出', () async {
      final adapter = _ScriptedAdapter([
        (403, 'rate limited'),
        (403, 'rate limited'),
        (403, 'rate limited'),
        (403, 'rate limited'),
      ]);
      final service = MovieScraperService(dio: _dioWith(adapter));

      await expectLater(
        service.searchMovies('测试'),
        throwsA(
          isA<ScraperException>().having(
            (e) => e.message,
            'message',
            contains('403'),
          ),
        ),
      );
      // 3 次尝试后放弃。
      expect(adapter.calls, 3);
    });

    test('非限流错误不重试，立即抛出', () async {
      final adapter = _ScriptedAdapter([
        (500, 'server error'),
        (200, 'should not reach'),
      ]);
      final service = MovieScraperService(dio: _dioWith(adapter));

      await expectLater(
        service.searchMovies('测试'),
        throwsA(isA<ScraperException>()),
      );
      expect(adapter.calls, 1, reason: '500 不属于限流，不应重试');
    });

    test('首次就成功时不产生额外请求', () async {
      final adapter = _ScriptedAdapter([
        (200, '<html>window.__DATA__ = {"items":[]}</html>'),
      ]);
      final service = MovieScraperService(dio: _dioWith(adapter));

      await service.searchMovies('测试');
      expect(adapter.calls, 1);
    });
  });
}
