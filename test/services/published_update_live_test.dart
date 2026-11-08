import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:random_movie/services/update_download_service.dart';
import 'package:random_movie/services/update_service.dart';

class _PublicHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'published UI channel upgrades the previous build and streams a verified APK',
    () async {
      final expectedCode = int.parse(
        Platform.environment['PIANKE_LIVE_EXPECTED_CODE']!,
      );
      final expectedBytes = int.parse(
        Platform.environment['PIANKE_LIVE_EXPECTED_BYTES']!,
      );
      final expectedHash = Platform.environment['PIANKE_LIVE_EXPECTED_SHA256']!;
      final previousCode = int.parse(
        Platform.environment['PIANKE_LIVE_PREVIOUS_CODE']!,
      );
      final directory = await Directory.systemTemp.createTemp(
        'pianke-published-update-',
      );
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final proxy = Platform.environment['PIANKE_TEST_PROXY'];
      if (proxy != null && proxy.isNotEmpty) {
        dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => HttpClient()..findProxy = (_) => proxy,
        );
      }
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          void setInstalled(int code) => PackageInfo.setMockInitialValues(
            appName: '片刻·焕新版',
            packageName: 'app.pianke.personal',
            version: '0.0.0',
            buildNumber: '$code',
            buildSignature: '',
          );
          setInstalled(previousCode);
          final service = UpdateService(dio: dio);
          final available = await service.checkForUpdate();
          expect(available.hasUpdate, isTrue);
          expect(available.update!.versionCode, expectedCode);
          expect(available.update!.sha256, expectedHash);
          expect(available.update!.forceUpdate, isFalse);
          var progressEvents = 0;
          final path =
              await UpdateDownloadService(
                dio: dio,
                cacheDirectory: () async => directory,
              ).download(
                available.update!,
                cancelToken: CancelToken(),
                onProgress: (_, _) => progressEvents++,
              );
          expect(await File(path).length(), expectedBytes);
          expect(progressEvents, greaterThan(1));
          setInstalled(expectedCode);
          expect((await service.checkForUpdate()).hasUpdate, isFalse);
        }, _PublicHttpOverrides());
      } finally {
        dio.close(force: true);
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['PIANKE_CHANNEL_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
