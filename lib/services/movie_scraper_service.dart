import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:html/dom.dart' show Element;
import 'package:html/parser.dart' show parse;
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/config/design_tokens.dart';
import 'package:random_movie/models/movie.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DoulistScrapeProgress {
  final int total;
  final int completed;
  final String? currentTitle;
  final List<Movie> movies;

  const DoulistScrapeProgress({
    required this.total,
    required this.completed,
    this.currentTitle,
    this.movies = const [],
  });

  double? get progress {
    if (total <= 0) return null;
    final safeCompleted = completed < 0
        ? 0
        : (completed > total ? total : completed);
    return safeCompleted / total;
  }
}

/// 豆瓣搜索结果（轻量：仅够展示 + 定位 subject 详情页）。
class DoubanSearchResult {
  final String id;
  final String title;
  final String url;
  final String cover;
  final double rating;
  final String year;

  const DoubanSearchResult({
    required this.id,
    required this.title,
    required this.url,
    this.cover = '',
    this.rating = 0,
    this.year = '',
  });
}

/// 影片爬取服务
class MovieScraperService {
  final Dio _dio;
  final _CookieJarLite _doubanCookieJar = _CookieJarLite();

  static const String _cookiePrefsKey = 'movie_app_douban_cookies';
  bool _cookieLoaded = false;
  bool _cookieDirty = false;

  void dispose() => _dio.close(force: true);

  MovieScraperService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  /// 从本地载入上次保存的豆瓣 Cookie，跨会话复用，减少挑战页触发。
  Future<void> _ensureCookieLoaded() async {
    if (_cookieLoaded) return;
    _cookieLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _doubanCookieJar.restore(prefs.getString(_cookiePrefsKey));
    } catch (_) {
      // 读取失败不影响抓取，按无 Cookie 走挑战页流程。
    }
  }

  /// 持久化 Cookie（异步、失败静默，不阻断抓取）。
  Future<void> _persistCookie() async {
    if (!_cookieDirty) return;
    _cookieDirty = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cookiePrefsKey, _doubanCookieJar.serialize());
    } catch (_) {
      // 写入失败仅影响下次复用，不影响本次抓取。
    }
  }

  /// 爬取单个影片（直接解析豆瓣页面）
  Future<Movie> scrapeMovie(String doubanUrl) async {
    final normalizedUrl = _validateDoubanMovieUrl(doubanUrl);

    try {
      final page = await _fetchMoviePage(normalizedUrl);
      final ldJsonText = _extractLdJson(page.html);
      final ldJson = _parseLdJson(ldJsonText);
      return _buildMovieFromPage(
        requestUrl: normalizedUrl,
        finalUrl: page.finalUrl,
        html: page.html,
        ldJson: ldJson,
      );
    } on ScraperException {
      rethrow;
    } on DioException catch (error) {
      throw ScraperException(_networkErrorMessage(error));
    } catch (_) {
      throw ScraperException('影片页面解析失败，可稍后重试或手动添加');
    }
  }

  /// 豆瓣关键词搜索（解析搜索页内嵌的 `window.__DATA__`）。
  /// [start] 为豆瓣分页偏移，每页 15，用于「滚动加载下一页」。
  Future<List<DoubanSearchResult>> searchMovies(
    String query, {
    int start = 0,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final url =
        'https://search.douban.com/movie/subject_search'
        '?search_text=${Uri.encodeQueryComponent(trimmed)}&cat=1002&start=$start';

    try {
      final response = await _getPlainHtml(
        url,
        headers: _buildMovieHeaders('https://search.douban.com/'),
      );
      final html = response.data ?? '';
      if (html.isEmpty) return const [];
      return _parseSearchData(html);
    } on DioException catch (error) {
      throw ScraperException(_networkErrorMessage(error));
    } on ScraperException {
      rethrow;
    } catch (_) {
      throw ScraperException('搜索结果解析失败，请重试或使用豆瓣链接添加');
    }
  }

  List<DoubanSearchResult> _parseSearchData(String html) {
    const marker = 'window.__DATA__';
    final markerIndex = html.indexOf(marker);
    if (markerIndex < 0) return const [];
    final objectStart = html.indexOf('{', markerIndex);
    if (objectStart < 0) return const [];

    final jsonText = _extractJsonObject(html, objectStart);
    if (jsonText.isEmpty) return const [];

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (_) {
      return const [];
    }

    final items = payload['items'];
    if (items is! List) return const [];

    final results = <DoubanSearchResult>[];
    final seen = <String>{};
    for (final item in items) {
      if (item is! Map) continue;
      final result = _searchResultFromMap(Map<String, dynamic>.from(item));
      if (result == null) continue;
      if (!seen.add(result.id)) continue;
      results.add(result);
    }
    return results;
  }

  /// 平衡括号提取从 [start] 位置起的完整 JSON 对象（尊重字符串与转义）。
  String _extractJsonObject(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return '';
  }

  DoubanSearchResult? _searchResultFromMap(Map<String, dynamic> map) {
    final url = (map['url'] ?? '').toString();
    final idFromUrl = RegExp(r'/subject/(\d+)').firstMatch(url)?.group(1);
    final id = (map['id']?.toString().trim().isNotEmpty ?? false)
        ? map['id'].toString().trim()
        : (idFromUrl ?? '');
    if (id.isEmpty) return null;

    final title = _collapseWhitespace((map['title'] ?? '').toString());
    if (title.isEmpty) return null;

    final cover = (map['cover_url'] ?? map['cover'] ?? map['pic'] ?? '')
        .toString();

    double rating = 0;
    final ratingRaw = map['rating'];
    if (ratingRaw is Map) {
      rating = double.tryParse((ratingRaw['value'] ?? '').toString()) ?? 0;
    } else if (ratingRaw != null) {
      rating = double.tryParse(ratingRaw.toString()) ?? 0;
    }

    final metaText =
        '${map['abstract_2'] ?? ''} ${map['abstract'] ?? ''} $title';
    final year = RegExp(r'(?:19|20)\d{2}').firstMatch(metaText)?.group(0) ?? '';

    return DoubanSearchResult(
      id: id,
      title: title,
      url: url.isNotEmpty ? url : 'https://movie.douban.com/subject/$id/',
      cover: cover,
      rating: rating,
      year: year,
    );
  }

  String _collapseWhitespace(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 爬取片单（解析片单页 -> 并发用单片抓取详情）
  Future<List<Movie>> scrapeDoulist(
    String doulistUrl, {
    void Function(DoulistScrapeProgress progress)? onProgress,
  }) async {
    try {
      if (!doulistUrl.contains('douban.com/doulist/')) {
        throw ScraperException('无效的豆瓣片单链接');
      }

      final candidates = <({String subjectUrl, Movie fallback})>[];
      final seenIds = <String>{};
      await _collectDoulistCandidates(
        doulistUrl,
        candidates: candidates,
        seenIds: seenIds,
      );

      if (candidates.isEmpty) {
        throw ScraperException('未找到影片，片单可能为空或需要登录');
      }

      const batchSize = 4;
      final resultSlots = List<Movie?>.filled(candidates.length, null);
      var completedCount = 0;

      Future<Movie> scrapeOrFallback(
        ({String subjectUrl, Movie fallback}) candidate,
      ) async {
        try {
          return await scrapeMovie(candidate.subjectUrl);
        } catch (_) {
          return candidate.fallback;
        }
      }

      List<Movie> snapshotMovies() =>
          resultSlots.whereType<Movie>().toList(growable: false);

      void emitProgress({String? currentTitle}) {
        onProgress?.call(
          DoulistScrapeProgress(
            total: candidates.length,
            completed: completedCount,
            currentTitle: currentTitle,
            movies: snapshotMovies(),
          ),
        );
      }

      Future<void> scrapeAt(
        int index,
        ({String subjectUrl, Movie fallback}) candidate,
      ) async {
        final movie = await scrapeOrFallback(candidate);
        resultSlots[index] = movie;
        completedCount++;
        emitProgress(currentTitle: movie.title);
      }

      emitProgress();

      // 先抓第一条，用于“预热” Cookie，减少后续批量触发挑战页概率
      await scrapeAt(0, candidates.first);

      // 批次之间留出间隔，降低触发豆瓣风控（403 / 429）的概率。
      //
      // 原先批次是「打完一批立刻打下一批」，100 部的片单会连发 25 批、
      // 每批 4 个并发请求，中间没有任何停顿。豆瓣对高频访问会返回
      // 挑战页或直接限流，用户看到的是「解析失败」——错误提示里虽然
      // 写了「勿连续请求」，但代码本身并没有做任何节流。
      //
      // 代价：100 部片单大约从 30 秒变成 60~80 秒。比起整单失败重来，
      // 这个代价值得。间隔取 400ms，是「能明显降低风控概率」与
      // 「用户还愿意等」之间的折中。
      // 间隔取自设计令牌，避免时长常量散落在业务代码里。
      // 详见 Motion.scraperBatchGap 的说明。
      const batchGap = Motion.scraperBatchGap;

      final remaining = candidates.asMap().entries.skip(1).toList();
      for (var start = 0; start < remaining.length; start += batchSize) {
        final end = math.min(start + batchSize, remaining.length);
        final batch = remaining.sublist(start, end);
        await Future.wait(
          batch.map((entry) => scrapeAt(entry.key, entry.value)),
        );
        // 最后一批之后不需要再等。
        if (end < remaining.length) {
          await Future<void>.delayed(batchGap);
        }
      }

      return snapshotMovies();
    } on ScraperException {
      rethrow;
    } on DioException catch (error) {
      throw ScraperException(_networkErrorMessage(error));
    } catch (_) {
      throw ScraperException('片单解析失败，请稍后重试');
    }
  }

  String _networkErrorMessage(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return '连接豆瓣超时，请检查网络后重试；已保存的片库仍可离线使用';
    }
    final code = error.response?.statusCode;
    if (code == 403 || code == 429) return '豆瓣暂时限制了访问，请稍后再试，勿连续请求';
    if (code == 404) return '豆瓣条目不存在或已移除，可以手动添加';
    return '无法连接豆瓣，请检查网络后重试；本地片库不受影响';
  }

  /// 分页收集片单候选影片。豆瓣片单默认每页 25 条，需逐页翻直到没有下一页。
  Future<void> _collectDoulistCandidates(
    String doulistUrl, {
    required List<({String subjectUrl, Movie fallback})> candidates,
    required Set<String> seenIds,
  }) async {
    const pageSize = 25;
    const maxPages = 60; // 安全上限，避免异常分页导致死循环（最多 1500 条）

    final baseUri = Uri.parse(doulistUrl.trim());

    for (var page = 0; page < maxPages; page++) {
      final pageUrl = _buildDoulistPageUrl(baseUri, page * pageSize);
      final response = await _getPlainHtml(
        pageUrl.toString(),
        headers: ApiConfig.doubanHeaders,
        cookieJar: _doubanCookieJar,
      );

      final document = parse(response.data ?? '');
      final items = document.querySelectorAll('.doulist-item');
      if (items.isEmpty) break;

      final addedBefore = candidates.length;
      _parseDoulistItems(items, candidates: candidates, seenIds: seenIds);

      // 本页没有解析出任何新影片，说明已到末尾或分页重复，停止。
      if (candidates.length == addedBefore) break;

      // 没有“后页”链接则结束。
      final hasNext = document.querySelector('.paginator .next a') != null;
      if (!hasNext) break;
    }
  }

  /// 按当前的 start 偏移构造分页 URL，保留原有查询参数。
  Uri _buildDoulistPageUrl(Uri base, int start) {
    final params = Map<String, String>.from(base.queryParameters);
    if (start <= 0) {
      params.remove('start');
    } else {
      params['start'] = start.toString();
    }
    return base.replace(queryParameters: params.isEmpty ? null : params);
  }

  /// 解析单页 `.doulist-item` 列表，去重后追加到候选集合。
  void _parseDoulistItems(
    List<Element> items, {
    required List<({String subjectUrl, Movie fallback})> candidates,
    required Set<String> seenIds,
  }) {
    for (final item in items) {
      try {
        final linkElem = item.querySelector('.post a');
        final rawUrl = linkElem?.attributes['href'] ?? '';
        final subjectId = _extractSubjectId(rawUrl);
        if (subjectId == null || subjectId.isEmpty) continue;

        final subjectUrl = _normalizeDoubanUrl('/subject/$subjectId/');
        final movieId = 'douban_$subjectId';
        if (!seenIds.add(movieId)) continue;

        final titleElem = item.querySelector('.title a');
        final title = titleElem?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final imgElem = item.querySelector('.post img');
        var poster = imgElem?.attributes['src'] ?? '';
        poster = _convertToWebp(poster);

        final ratingElem = item.querySelector('.rating_nums');
        final rating = double.tryParse(ratingElem?.text.trim() ?? '0') ?? 0;

        final abstractElem = item.querySelector('.abstract');
        final abstractData = _parseAbstract(abstractElem?.text ?? '');

        candidates.add((
          subjectUrl: subjectUrl,
          fallback: Movie(
            id: movieId,
            title: title,
            year: abstractData['year'] ?? '',
            director: abstractData['director'] ?? '',
            cast: abstractData['cast'] ?? '',
            rating: rating,
            genre: _parseGenre(abstractData['genre'] ?? ''),
            region: abstractData['region'] ?? '',
            poster: poster,
            doubanUrl: subjectUrl,
          ),
        ));
      } catch (_) {
        continue;
      }
    }
  }

  Future<_FetchedMoviePage> _fetchMoviePage(String targetUrl) async {
    final cookieJar = _doubanCookieJar;
    final headers = _buildMovieHeaders(targetUrl);
    final firstResponse = await _getPlainHtml(
      targetUrl,
      headers: headers,
      cookieJar: cookieJar,
    );
    final firstHtml = firstResponse.data ?? '';

    if (firstHtml.isEmpty) {
      throw ScraperException('豆瓣页面内容为空');
    }

    if (!_looksLikeChallengePage(firstHtml)) {
      return _FetchedMoviePage(
        html: firstHtml,
        finalUrl: firstResponse.realUri.toString(),
      );
    }

    final token = _extractHiddenValue(firstHtml, 'tok');
    final challenge = _extractHiddenValue(firstHtml, 'cha');
    final redirectUrl = _extractHiddenValue(firstHtml, 'red');
    final solution = await _powNonce(challenge, difficulty: 4);

    final challengeHeaders = {
      'Referer':
          'https://sec.douban.com/c?r=${Uri.encodeComponent(redirectUrl)}'
          '&_s=${token.contains('@') ? token.split('@').last : ''}&a=1',
      'Origin': 'https://sec.douban.com',
      'User-Agent': headers['User-Agent']!,
      'Accept': headers['Accept']!,
      'Accept-Language': headers['Accept-Language']!,
      if (cookieJar.hasCookies) 'Cookie': cookieJar.buildHeader(),
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'same-origin',
    };

    final challengeResponse = await _dio.post<String>(
      'https://sec.douban.com/c',
      data: {
        'tok': token,
        'cha': challenge,
        'sol': solution.toString(),
        'red': redirectUrl,
      },
      options: Options(
        headers: challengeHeaders,
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    cookieJar.absorb(challengeResponse.headers);

    final statusCode = challengeResponse.statusCode ?? 0;
    if (statusCode >= 400) {
      throw ScraperException('挑战页验证失败: $statusCode');
    }

    if (_isRedirectStatus(statusCode)) {
      final location = challengeResponse.headers.value('location');
      if (location != null && location.isNotEmpty) {
        await _getPlainHtml(
          _normalizeDoubanUrl(location),
          headers: headers,
          cookieJar: cookieJar,
        );
      }
    }

    final finalResponse = await _getPlainHtml(
      _normalizeDoubanUrl(redirectUrl),
      headers: headers,
      cookieJar: cookieJar,
    );
    final finalHtml = finalResponse.data ?? '';

    if (finalHtml.isEmpty) {
      throw ScraperException('豆瓣页面内容为空');
    }

    if (_looksLikeChallengePage(finalHtml)) {
      throw ScraperException('提交验证后仍返回挑战页');
    }

    return _FetchedMoviePage(
      html: finalHtml,
      finalUrl: finalResponse.realUri.toString(),
    );
  }

  Future<Response<String>> _getPlainHtml(
    String url, {
    required Map<String, String> headers,
    _CookieJarLite? cookieJar,
  }) async {
    await _ensureCookieLoaded();
    final requestHeaders = Map<String, String>.from(headers);
    if (cookieJar != null && cookieJar.hasCookies) {
      requestHeaders['Cookie'] = cookieJar.buildHeader();
    }

    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: requestHeaders,
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    cookieJar?.absorb(response.headers);
    if (cookieJar != null) {
      _cookieDirty = true;
      unawaited(_persistCookie());
    }

    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 400) {
      throw ScraperException('请求豆瓣页面失败: $statusCode');
    }
    return response;
  }

  Map<String, String> _buildMovieHeaders(String targetUrl) {
    return {
      'Referer': targetUrl,
      'Origin': 'https://movie.douban.com',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,'
          'image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
  }

  String _validateDoubanMovieUrl(String doubanUrl) {
    final normalized = doubanUrl.trim();
    final uri = Uri.tryParse(normalized);
    final host = uri?.host ?? '';
    final path = uri?.path ?? '';
    final isDoubanHost =
        host == 'movie.douban.com' ||
        host == 'www.douban.com' ||
        host == 'm.douban.com';
    final isMoviePath =
        path.contains('/subject/') ||
        path.contains('/doubanapp/dispatch/movie/');

    if (!isDoubanHost || !isMoviePath) {
      throw ScraperException('无效的豆瓣影片链接');
    }

    return normalized;
  }

  bool _looksLikeChallengePage(String html) {
    return html.contains('name="sec"') && html.contains('action="/c"');
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  String _extractHiddenValue(String html, String name) {
    final match = RegExp(
      '<input[^>]*name="${RegExp.escape(name)}"[^>]*value="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(html);

    if (match == null) {
      throw ScraperException('豆瓣挑战页缺少字段: $name');
    }
    return match.group(1) ?? '';
  }

  String _extractLdJson(String html) {
    final match = RegExp(
      r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);

    if (match == null) {
      throw ScraperException('页面缺少影片结构化数据');
    }

    return match.group(1)?.trim() ?? '';
  }

  Map<String, dynamic> _parseLdJson(String ldJsonText) {
    final cleaned = ldJsonText.trim().replaceFirst('\ufeff', '');

    try {
      return Map<String, dynamic>.from(jsonDecode(cleaned) as Map);
    } on FormatException {
      final sanitized = _sanitizeJsonControlChars(cleaned);
      return Map<String, dynamic>.from(jsonDecode(sanitized) as Map);
    }
  }

  String _sanitizeJsonControlChars(String source) {
    final buffer = StringBuffer();
    var inString = false;
    var escaped = false;

    for (final rune in source.runes) {
      final character = String.fromCharCode(rune);

      if (!inString) {
        if (character == '"') {
          inString = true;
        }
        buffer.write(character);
        continue;
      }

      if (escaped) {
        buffer.write(character);
        escaped = false;
        continue;
      }

      if (character == r'\') {
        buffer.write(character);
        escaped = true;
        continue;
      }

      if (character == '"') {
        buffer.write(character);
        inString = false;
        continue;
      }

      if (rune < 0x20) {
        if (character == '\n') {
          buffer.write(r'\n');
        } else if (character == '\r') {
          buffer.write(r'\r');
        } else if (character == '\t') {
          buffer.write(r'\t');
        } else {
          buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
        }
        continue;
      }

      buffer.write(character);
    }

    return buffer.toString();
  }

  Future<int> _powNonce(String data, {int difficulty = 4}) async {
    // PoW 计算放到后台 isolate，避免阻塞 UI 线程。
    return compute(_powNonceInIsolate, (data: data, difficulty: difficulty));
  }

  Movie _buildMovieFromPage({
    required String requestUrl,
    required String finalUrl,
    required String html,
    required Map<String, dynamic> ldJson,
  }) {
    final ldType = ldJson['@type']?.toString().trim();
    final subjectType = switch (ldType) {
      'TVSeries' => MovieSubjectType.tvSeries,
      'Movie' => MovieSubjectType.movie,
      _ => MovieSubjectType.movie,
    };

    final normalizedUrl = _normalizeDoubanUrl(
      (ldJson['url'] ?? finalUrl ?? requestUrl).toString(),
    );
    final subjectId =
        _extractSubjectId(normalizedUrl) ??
        _extractSubjectId(finalUrl) ??
        _extractSubjectId(requestUrl);

    if (subjectId == null || subjectId.isEmpty) {
      throw ScraperException('未能提取豆瓣条目 ID');
    }

    final title = (ldJson['name'] ?? '').toString().trim();
    if (title.isEmpty) {
      throw ScraperException('页面缺少影片标题');
    }

    final aggregateRating = ldJson['aggregateRating'];
    final posterUrl = (ldJson['image'] ?? '').toString().trim();
    final summary = _extractSummary(html, ldJson['description']);
    final publishedAt = (ldJson['datePublished'] ?? '').toString().trim();
    final durationText = (ldJson['duration'] ?? '').toString().trim();

    return Movie(
      id: 'douban_$subjectId',
      subjectType: subjectType,
      title: title,
      year:
          _extractInfoValue(html, const ['年份']) ??
          _extractYearFromDate(ldJson['datePublished']),
      director: _extractPersonNames(ldJson['director']).join(' / '),
      author: _extractPersonNames(ldJson['author']).join(' / '),
      cast: _extractPersonNames(ldJson['actor']).join(' / '),
      rating: _toDouble(
        aggregateRating is Map ? aggregateRating['ratingValue'] : null,
      ),
      genre: _toStringList(ldJson['genre']),
      region: _extractInfoValue(html, const ['制片国家/地区', '国家/地区']) ?? '',
      summary: summary,
      publishedAt: publishedAt,
      durationText: durationText,
      poster: posterUrl.isEmpty ? '' : _normalizeDoubanUrl(posterUrl),
      doubanUrl: normalizedUrl,
      episodes: subjectType == MovieSubjectType.tvSeries
          ? _extractEpisodes(html)
          : const [],
    );
  }

  String _extractSummary(String html, dynamic fallback) {
    final document = parse(html);
    // The hidden full introduction follows the short version on Douban.
    final element =
        document.querySelector('#link-report .all.hidden') ??
        document.querySelector('#link-report [property="v:summary"]') ??
        document.querySelector('[property="v:summary"]');
    if (element == null) return (fallback ?? '').toString().trim();
    final content = element.clone(true);
    for (final link in content.querySelectorAll('a')) {
      link.remove();
    }
    for (final br in content.querySelectorAll('br')) {
      br.replaceWith(Element.tag('span')..text = '\n');
    }
    final text = content.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    return text.isEmpty ? (fallback ?? '').toString().trim() : text;
  }

  List<MovieEpisode> _extractEpisodes(String html) {
    final document = parse(html);
    final anchors = document.querySelectorAll('.episode_list a');

    final episodes = <MovieEpisode>[];
    for (final anchor in anchors) {
      final href = anchor.attributes['href']?.trim();
      if (href == null || href.isEmpty) continue;

      final label = anchor.text.trim();
      final numberMatch = RegExp(r'(\d+)').firstMatch(label);
      final number = numberMatch != null
          ? int.tryParse(numberMatch.group(1)!) ?? 0
          : 0;

      episodes.add(
        MovieEpisode(
          number: number,
          label: label,
          doubanUrl: _normalizeDoubanUrl(href),
        ),
      );
    }

    episodes.sort((a, b) => a.number.compareTo(b.number));
    return episodes;
  }

  String? _extractInfoValue(String html, List<String> labels) {
    for (final label in labels) {
      final match = RegExp(
        '<span[^>]*>\\s*${RegExp.escape(label)}\\s*:\\s*</span>\\s*([^<]+)',
        caseSensitive: false,
      ).firstMatch(html);

      final value = match?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? _extractSubjectId(String url) {
    final match = RegExp(r'(?:subject|movie)/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  String _extractYearFromDate(dynamic value) {
    if (value == null) return '';
    final match = RegExp(r'(\d{4})').firstMatch(value.toString());
    return match?.group(1) ?? '';
  }

  List<String> _extractPersonNames(dynamic value) {
    if (value is Map) {
      final name = (value['name'] ?? '').toString().trim();
      return name.isEmpty ? const [] : [name];
    }

    if (value is! List) {
      return const [];
    }

    final names = <String>[];
    for (final item in value) {
      if (item is! Map) continue;
      final name = (item['name'] ?? '')
          .toString()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
    return names;
  }

  List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    if (value is String) {
      return value
          .split(RegExp(r'[/,，]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }

    return const [];
  }

  double _toDouble(dynamic value) {
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  // ========== 私有工具方法 ==========

  /// 解析类型字符串
  List<String> _parseGenre(String genreStr) {
    if (genreStr.isEmpty) return [];
    return genreStr
        .split('/')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  /// 解析 abstract 字段
  Map<String, String> _parseAbstract(String text) {
    final result = <String, String>{};
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      if (line.startsWith('导演:')) {
        result['director'] = line.replaceFirst('导演:', '').trim();
      } else if (line.startsWith('主演:')) {
        result['cast'] = line.replaceFirst('主演:', '').trim();
      } else if (line.startsWith('类型:')) {
        result['genre'] = line.replaceFirst('类型:', '').trim();
      } else if (line.startsWith('制片国家/地区:')) {
        result['region'] = line.replaceFirst('制片国家/地区:', '').trim();
      } else if (line.startsWith('年份:')) {
        result['year'] = line.replaceFirst('年份:', '').trim();
      }
    }

    return result;
  }

  /// 转换为 webp 格式
  String _convertToWebp(String url) {
    if (url.isEmpty) return '';
    if (url.endsWith('.webp')) return url;
    return url.replaceAll(
      RegExp(r'\.(jpg|jpeg|png|gif)$', caseSensitive: false),
      '.webp',
    );
  }

  String _normalizeDoubanUrl(String url) {
    final baseUri = Uri.parse('https://movie.douban.com');
    return baseUri.resolve(url).toString();
  }
}

class ScraperException implements Exception {
  final String message;
  ScraperException(this.message);

  @override
  String toString() => message;
}

class _CookieJarLite {
  final Map<String, String> _cookies = {};

  bool get hasCookies => _cookies.isNotEmpty;

  String buildHeader() {
    return _cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  /// 序列化为可持久化的字符串（`k=v; k2=v2`）。
  String serialize() {
    return _cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  /// 从持久化字符串恢复。
  void restore(String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    for (final part in raw.split(';')) {
      final pair = part.trim();
      final equalsIndex = pair.indexOf('=');
      if (equalsIndex <= 0) continue;
      final name = pair.substring(0, equalsIndex).trim();
      final value = pair.substring(equalsIndex + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        _cookies[name] = value;
      }
    }
  }

  void absorb(Headers headers) {
    final values = headers.map['set-cookie'];
    if (values == null || values.isEmpty) return;

    for (final item in values) {
      final firstPart = item.split(';').first.trim();
      if (firstPart.isEmpty) continue;

      final equalsIndex = firstPart.indexOf('=');
      if (equalsIndex <= 0) continue;

      final name = firstPart.substring(0, equalsIndex).trim();
      final value = firstPart.substring(equalsIndex + 1).trim();
      if (name.isEmpty) continue;

      _cookies[name] = value;
    }
  }
}

class _FetchedMoviePage {
  final String html;
  final String finalUrl;

  const _FetchedMoviePage({required this.html, required this.finalUrl});
}

/// 在后台 isolate 里计算 PoW 答案（顶层函数，供 [compute] 使用）。
int _powNonceInIsolate(({String data, int difficulty}) args) {
  final prefix = '0' * args.difficulty;
  final data = args.data;
  var nonce = 0;
  while (true) {
    nonce++;
    if (sha512.convert(utf8.encode('$data$nonce')).toString().startsWith(prefix)) {
      return nonce;
    }
  }
}
