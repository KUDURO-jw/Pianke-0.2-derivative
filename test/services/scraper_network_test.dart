import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/movie_scraper_service.dart';

void main() {
  for (final status in [403, 429, 404, 500]) {
    test(
      'scraper network $status reports an actionable error without private request details',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: status,
                  ),
                  type: DioExceptionType.badResponse,
                  message: 'sensitive-proxy-address',
                ),
              );
            },
          ),
        );
        final scraper = MovieScraperService(dio: dio);
        for (final task in [
          () => scraper.scrapeMovie('https://movie.douban.com/subject/123/'),
          () => scraper.searchMovies('影片'),
        ]) {
          await expectLater(
            task(),
            throwsA(
              isA<ScraperException>().having(
                (e) => e.message,
                'safe actionable message',
                allOf(
                  isNot(contains('sensitive-proxy-address')),
                  contains(
                    status == 403 || status == 429
                        ? '限制'
                        : status == 404
                        ? '不存在'
                        : '无法连接',
                  ),
                ),
              ),
            ),
          );
        }
      },
    );
  }
}
