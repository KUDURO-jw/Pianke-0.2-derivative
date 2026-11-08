import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/movie_scraper_service.dart';

void main() {
  Future<String> summary(String body) async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<String>(
              requestOptions: options,
              data:
                  '''
<script type="application/ld+json">{"@type":"Movie","name":"测试","description":"简短摘要","url":"https://movie.douban.com/subject/123/"}</script>
$body
''',
            ),
          );
        },
      ),
    );
    return (await MovieScraperService(
      dio: dio,
    ).scrapeMovie('https://movie.douban.com/subject/123/')).summary;
  }

  test('prefers hidden full summary and preserves paragraph breaks', () async {
    expect(
      await summary('''<div id="link-report">
<span property="v:summary">简短…</span>
<span class="all hidden">第一段 &amp; 内容<br /> 第二段<a>收起</a></span></div>'''),
      '第一段 & 内容\n第二段',
    );
  });
  test(
    'uses visible full summary and falls back when HTML summary is absent',
    () async {
      expect(await summary('<span property="v:summary">完整内容</span>'), '完整内容');
      expect(await summary(''), '简短摘要');
    },
  );
}
