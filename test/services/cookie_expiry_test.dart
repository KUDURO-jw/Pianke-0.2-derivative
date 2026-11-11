// Cookie 过期处理的回归测试。
//
// 背景：豆瓣挑战凭证 dbsawcv1 只有 120 秒有效期。原实现不解析过期时间，
// 把凭证永久存进 prefs 并反复发送，导致用户「一直 403 怎么重试都没用」。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/movie_scraper_service.dart';

/// 构造一个只带 Set-Cookie 的 Headers，模拟豆瓣响应。
Headers headersWithCookie(String setCookie) {
  return Headers.fromMap({
    'set-cookie': [setCookie],
  });
}

void main() {
  group('DoubanCookieJar 过期处理', () {
    test('Max-Age=0 的 cookie 立刻失效，不进入请求头', () {
      final jar = DoubanCookieJar();
      jar.absorb(headersWithCookie('dbsawcv1=abc; Max-Age=0; Path=/'));
      expect(jar.buildHeader(), isEmpty);
      expect(jar.hasCookies, isFalse);
    });

    test('未过期的 cookie 正常发送', () {
      final jar = DoubanCookieJar();
      jar.absorb(headersWithCookie('bid=xyz; Max-Age=3600; Path=/'));
      expect(jar.buildHeader(), contains('bid=xyz'));
      expect(jar.hasCookies, isTrue);
    });

    test('session cookie（无 Max-Age / Expires）会被保留', () {
      final jar = DoubanCookieJar();
      jar.absorb(headersWithCookie('sess=keepme; Path=/'));
      expect(jar.buildHeader(), contains('sess=keepme'));
    });

    test('值为空表示服务端删除该 cookie', () {
      final jar = DoubanCookieJar();
      jar.absorb(headersWithCookie('bid=xyz; Max-Age=3600'));
      expect(jar.hasCookies, isTrue);

      jar.absorb(headersWithCookie('bid=; Max-Age=0'));
      expect(jar.buildHeader(), isNot(contains('bid')));
    });

    test('多个 cookie 混合时只过滤过期的那个', () {
      final jar = DoubanCookieJar();
      jar.absorb(headersWithCookie('bid=keep; Max-Age=3600'));
      jar.absorb(headersWithCookie('dbsawcv1=dead; Max-Age=0'));

      final header = jar.buildHeader();
      expect(header, contains('bid=keep'));
      expect(header, isNot(contains('dbsawcv1')));
    });

    test('serialize 不写出已过期 cookie', () {
      final jar = DoubanCookieJar();
      jar.absorb(headersWithCookie('bid=keep; Max-Age=3600'));
      jar.absorb(headersWithCookie('dead=1; Max-Age=0'));

      final saved = jar.serialize();
      expect(saved, contains('bid=keep'));
      expect(saved, isNot(contains('dead=1')));
    });

    test('clear 清空全部 cookie', () {
      final jar = DoubanCookieJar();
      jar.absorb(headersWithCookie('a=1; Max-Age=3600'));
      jar.absorb(headersWithCookie('b=2'));
      expect(jar.hasCookies, isTrue);

      jar.clear();
      expect(jar.hasCookies, isFalse);
      expect(jar.buildHeader(), isEmpty);
    });

    test('从持久化字符串恢复后可正常发送', () {
      final jar = DoubanCookieJar();
      jar.restore('bid=fromdisk; other=val');
      final header = jar.buildHeader();
      expect(header, contains('bid=fromdisk'));
      expect(header, contains('other=val'));
    });

    test('Expires 属性在过去时间也被判定为过期', () {
      final jar = DoubanCookieJar();
      jar.absorb(
        headersWithCookie(
          'old=1; Expires=Wed, 01 Jan 2020 00:00:00 GMT; Path=/',
        ),
      );
      expect(jar.buildHeader(), isEmpty);
    });

    test('Expires 在未来时间仍然有效', () {
      final jar = DoubanCookieJar();
      jar.absorb(
        headersWithCookie(
          'future=1; Expires=Wed, 01 Jan 2030 00:00:00 GMT; Path=/',
        ),
      );
      expect(jar.buildHeader(), contains('future=1'));
    });

    test('同名 cookie 后到的覆盖先到的', () {
      final jar = DoubanCookieJar();
      jar.absorb(headersWithCookie('bid=old; Max-Age=3600'));
      jar.absorb(headersWithCookie('bid=new; Max-Age=3600'));
      final header = jar.buildHeader();
      expect(header, contains('bid=new'));
      expect(header, isNot(contains('bid=old')));
    });
  });
}
