import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/update_download_service.dart';
import 'package:random_movie/services/update_service.dart';

class _BytesAdapter implements HttpClientAdapter {
  final List<int> bytes;
  final int status;
  final int? declaredLength;
  final bool unknownLength;
  int requests = 0;
  _BytesAdapter(
    this.bytes, {
    this.status = 200,
    this.declaredLength,
    this.unknownLength = false,
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    Stream<Uint8List> chunks() async* {
      for (var i = 0; i < bytes.length; i += 64) {
        await Future<void>.delayed(Duration.zero);
        yield Uint8List.fromList(
          bytes.sublist(i, (i + 64).clamp(0, bytes.length)),
        );
      }
    }

    return ResponseBody(
      chunks(),
      status,
      headers: {
        if (!unknownLength)
          'content-length': ['${declaredLength ?? bytes.length}'],
        'content-type': ['application/octet-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final bytes = List.generate(4096, (i) => i % 256);
  AppUpdateInfo update({String? hash}) => AppUpdateInfo(
    versionName: '0.2.6',
    versionCode: 11,
    title: '新版',
    changelog: [],
    downloadUrl: 'https://github.com/example/app/releases/download/v11/app.apk',
    forceUpdate: false,
    sha256: hash ?? crypto.sha256.convert(bytes).toString(),
  );
  UpdateDownloadService service(_BytesAdapter adapter) => UpdateDownloadService(
    dio: Dio()..httpClientAdapter = adapter,
    cacheDirectory: () async => directory,
  );
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'pianke-update-test-',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));

  test(
    'streams progress, verifies hash, reuses verified cache and preserves unrelated files',
    () async {
      final adapter = _BytesAdapter(bytes);
      final downloads = service(adapter);
      final unrelated = File('${directory.path}/updates/notes.txt');
      await unrelated.parent.create();
      await unrelated.writeAsString('preserve');
      await File('${directory.path}/updates/Pianke-UI-9.apk').writeAsBytes([1]);
      var received = 0;
      var total = 0;
      var verifying = 0;
      final path = await downloads.download(
        update(),
        cancelToken: CancelToken(),
        onProgress: (r, t) {
          received = r;
          total = t;
        },
        onVerifying: () => verifying++,
      );
      expect(received, bytes.length);
      expect(total, bytes.length);
      expect(await File(path).readAsBytes(), bytes);
      expect(await unrelated.readAsString(), 'preserve');
      expect(
        await File('${directory.path}/updates/Pianke-UI-9.apk').exists(),
        isFalse,
      );
      final reused = await downloads.download(
        update(),
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
        onVerifying: () => verifying++,
      );
      expect(reused, path);
      expect(adapter.requests, 1);
      expect(verifying, 2);
    },
  );

  test('unknown content length still downloads and validates', () async {
    var total = 0;
    await service(_BytesAdapter(bytes, unknownLength: true)).download(
      update(),
      cancelToken: CancelToken(),
      onProgress: (_, t) => total = t,
    );
    expect(total, -1);
  });

  test(
    'incorrect hash, HTML response and empty response never become installable files',
    () async {
      for (final body in [bytes, '<html>error</html>'.codeUnits, <int>[]]) {
        final download = service(_BytesAdapter(body));
        await expectLater(
          download.download(
            update(hash: '0' * 64),
            cancelToken: CancelToken(),
            onProgress: (_, _) {},
          ),
          throwsA(isA<UpdateDownloadException>()),
        );
        expect(
          await Directory('${directory.path}/updates').list().toList(),
          isEmpty,
        );
      }
    },
  );

  test(
    'cancel removes partial download, resets busy state and permits retry',
    () async {
      final adapter = _BytesAdapter(bytes);
      final downloads = service(adapter);
      final token = CancelToken();
      await expectLater(
        downloads.download(
          update(),
          cancelToken: token,
          onProgress: (received, _) {
            if (received > 0) token.cancel('user');
          },
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(
        await Directory('${directory.path}/updates').list().toList(),
        isEmpty,
      );
      await downloads.download(
        update(),
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
      );
      expect(adapter.requests, 2);
    },
  );

  test('cancel during verification removes partial data', () async {
    final token = CancelToken();
    await expectLater(
      service(_BytesAdapter(bytes)).download(
        update(),
        cancelToken: token,
        onProgress: (_, _) {},
        onVerifying: () => token.cancel('user'),
      ),
      throwsA(isA<DioException>()),
    );
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
  });

  test('oversized response is stopped and cleaned', () async {
    await expectLater(
      service(
        _BytesAdapter(
          bytes,
          declaredLength: UpdateDownloadService.maxApkBytes + 1,
        ),
      ).download(update(), cancelToken: CancelToken(), onProgress: (_, _) {}),
      throwsA(isA<UpdateDownloadException>()),
    );
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
  });

  test('missing hash prevents any download, HTTP failures propagate', () async {
    final adapter = _BytesAdapter(bytes, status: 403);
    final downloads = service(adapter);
    await expectLater(
      downloads.download(
        update(hash: ''),
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
      ),
      throwsA(isA<UpdateDownloadException>()),
    );
    expect(adapter.requests, 0);
    await expectLater(
      downloads.download(
        update(),
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
      ),
      throwsA(isA<DioException>()),
    );
    expect(
      await Directory('${directory.path}/updates').list().toList(),
      isEmpty,
    );
  });

  test(
    'installer channel preserves explicit path/version and permission result',
    () async {
      MethodCall? invocation;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        UpdateDownloadService.installerChannel,
        (call) async {
          invocation = call;
          return 'permissionRequired';
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          UpdateDownloadService.installerChannel,
          null,
        ),
      );
      final downloads = UpdateDownloadService();
      expect(
        await downloads.install('/cache/updates/Pianke-UI-11.apk', 11),
        UpdateInstallResult.permissionRequired,
      );
      expect(invocation!.method, 'installUpdate');
      expect(invocation!.arguments, {
        'path': '/cache/updates/Pianke-UI-11.apk',
        'versionCode': 11,
      });
    },
  );

  // Opt in to a public-release smoke check; ordinary tests stay fully offline.
  if (Platform.environment['PIANKE_UPDATE_LIVE'] == '1') {
    test(
      'real public GitHub APK follows redirects and passes streamed SHA-256',
      () async {
        const previous = AppUpdateInfo(
          versionName: '0.2.5',
          versionCode: 10,
          title: '公开下载验证',
          changelog: [],
          downloadUrl:
              'https://github.com/KUDURO-jw/Pianke-0.2-derivative/releases/download/v0.2.5-ui.1/Pianke-UI-arm64-release.apk',
          forceUpdate: false,
          sha256:
              '02c0f2b7268a6eb6f3995b22bea54e9f6b167b09053e4f5218cf863275b1f25c',
        );
        var progressEvents = 0;
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
        final proxy = Platform.environment['PIANKE_TEST_PROXY'];
        if (proxy != null) {
          dio.httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () => HttpClient()..findProxy = (_) => proxy,
          );
        }
        final path = await HttpOverrides.runWithHttpOverrides(
          () =>
              UpdateDownloadService(
                dio: dio,
                cacheDirectory: () async => directory,
              ).download(
                previous,
                cancelToken: CancelToken(),
                onProgress: (_, _) => progressEvents++,
              ),
          _RealHttpOverrides(),
        );
        expect(await File(path).length(), 21193549);
        expect(progressEvents, greaterThan(1));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
