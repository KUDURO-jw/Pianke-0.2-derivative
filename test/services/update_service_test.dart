import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/services/update_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '片刻·焕新版',
      packageName: 'app.pianke.personal',
      version: '0.2.1',
      buildNumber: '6',
      buildSignature: '',
    );
  });
  Map<String, dynamic> manifest(int code) => {
    'versionName': '0.2.1',
    'versionCode': code,
    'title': '焕新版',
    'changelog': ['修复体验'],
    'downloadUrl':
        'https://github.com/KUDURO-jw/Pianke-0.2-derivative/releases/download/v0.2.1-ui.1/Pianke-UI-arm64-release.apk',
    'forceUpdate': false,
  };
  UpdateService service(Object data) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.uri.toString(), ApiConfig.updateManifestUrl);
          expect(options.uri.path, endsWith('/update-ui.json'));
          handler.resolve(Response(requestOptions: options, data: data));
        },
      ),
    );
    return UpdateService(dio: dio);
  }

  test('higher build is offered and can be skipped', () async {
    final result = await service(manifest(7)).checkForUpdate();
    expect(result.hasUpdate, isTrue);
    expect(result.update!.forceUpdate, isFalse);
  });
  test('parses text/plain JSON and BOM returned by raw GitHub', () async {
    for (final prefix in ['', '\ufeff']) {
      final result = await service(
        '$prefix${jsonEncode(manifest(7))}',
      ).checkForUpdate();
      expect(result.update!.versionCode, 7);
    }
    expect(
      (await service(jsonEncode(manifest(6))).checkForUpdate()).hasUpdate,
      isFalse,
    );
  });
  test(
    'real HTTP text/plain response is decoded by the update service',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(jsonEncode(manifest(7)));
        request.response.close();
      });
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.baseUrl = '';
            options.path = 'http://127.0.0.1:${server.port}/update-ui.json';
            handler.next(options);
          },
        ),
      );
      try {
        expect(
          (await HttpOverrides.runWithHttpOverrides(
            () => UpdateService(dio: dio).checkForUpdate(),
            _RealHttpOverrides(),
          )).hasUpdate,
          isTrue,
        );
      } finally {
        dio.close(force: true);
        await server.close(force: true);
      }
    },
  );
  test('same and older builds are not offered', () async {
    for (final code in [5, 6]) {
      expect(
        (await service(manifest(code)).checkForUpdate()).hasUpdate,
        isFalse,
      );
    }
  });
  test(
    'falls back to semantic version for old manifest without build number',
    () async {
      final data = manifest(7)..remove('versionCode');
      data['versionName'] = '0.2.2';
      expect((await service(data).checkForUpdate()).hasUpdate, isTrue);
    },
  );
  test('invalid manifest and download URL report errors', () async {
    for (final data in [
      'not a manifest',
      {...manifest(7), 'versionName': ''},
      {...manifest(7), 'downloadUrl': 'file:///wrong.apk'},
      {...manifest(7), 'sha256': 'invalid'},
    ]) {
      await expectLater(
        service(data).checkForUpdate(),
        throwsA(isA<UpdateCheckException>()),
      );
    }
  });
  test(
    'network timeout completes with an error instead of an update',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );
      await expectLater(
        UpdateService(dio: dio).checkForUpdate(),
        throwsA(isA<DioException>()),
      );
    },
  );
}
