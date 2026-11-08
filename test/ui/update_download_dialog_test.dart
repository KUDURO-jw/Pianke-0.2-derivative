import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/services/update_download_service.dart';
import 'package:random_movie/services/update_service.dart';
import 'package:random_movie/widgets/settings/update_download_dialog.dart';

class _Downloads extends UpdateDownloadService {
  int starts = 0;
  int installs = 0;
  late Completer<String> pending;
  late ProgressCallback progress;
  VoidCallback? verifying;
  CancelToken? token;
  UpdateInstallResult result = UpdateInstallResult.permissionRequired;
  PlatformException? installError;
  @override
  Future<String> download(
    AppUpdateInfo update, {
    required CancelToken cancelToken,
    required ProgressCallback onProgress,
    VoidCallback? onVerifying,
  }) {
    starts++;
    pending = Completer<String>();
    progress = onProgress;
    verifying = onVerifying;
    token = cancelToken;
    cancelToken.whenCancel.then((error) {
      if (!pending.isCompleted) pending.completeError(error);
    });
    return pending.future;
  }

  @override
  Future<UpdateInstallResult> install(String path, int code) async {
    installs++;
    if (installError != null) throw installError!;
    return result;
  }
}

const _update = AppUpdateInfo(
  versionName: '0.2.6',
  versionCode: 11,
  title: '片刻·焕新版',
  changelog: ['应用内下载进度', '下载完成后确认安装'],
  downloadUrl: 'https://github.com/example/app.apk',
  forceUpdate: false,
);

void main() {
  testWidgets(
    'system back cancels a modal download before allowing dismissal',
    (tester) async {
      final service = _Downloads();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      UpdateDownloadDialog(update: _update, service: service),
                ),
                child: const Text('打开更新'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开更新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载新版'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(service.token!.isCancelled, isTrue);
      expect(find.text('已取消下载'), findsOneWidget);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateDownloadDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shows progress, supports cancellation and retry, then requires explicit install',
    (tester) async {
      final service = _Downloads();
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateDownloadDialog(update: _update, service: service),
        ),
      );
      expect(service.starts, 0);
      await tester.tap(find.text('下载新版'));
      await tester.pump();
      service.progress(1024 * 1024, 2 * 1024 * 1024);
      await tester.pump();
      expect(find.text('50% · 1.0 MB / 2.0 MB'), findsOneWidget);
      expect(find.text('安装新版'), findsNothing);
      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();
      expect(service.token!.isCancelled, isTrue);
      expect(find.text('已取消下载'), findsOneWidget);
      await tester.tap(find.text('下载新版'));
      await tester.pump();
      expect(service.starts, 2);
      service.verifying?.call();
      await tester.pump();
      expect(find.text('正在校验安装包…'), findsOneWidget);
      service.pending.complete('/cache/updates/Pianke-UI-11.apk');
      await tester.pumpAndSettle();
      expect(service.installs, 0);
      expect(find.text('下载完成，安装包校验通过'), findsOneWidget);
      await tester.tap(find.text('安装新版'));
      await tester.pumpAndSettle();
      expect(service.installs, 1);
      expect(find.textContaining('返回后再次点击'), findsOneWidget);
      service.result = UpdateInstallResult.launched;
      await tester.tap(find.text('安装新版'));
      await tester.pumpAndSettle();
      expect(service.installs, 2);
      expect(find.textContaining('已打开系统安装确认'), findsOneWidget);
      service.installError = PlatformException(
        code: 'invalid_update',
        message: '安装包缓存不存在，请重新下载',
      );
      await tester.tap(find.text('安装新版'));
      await tester.pumpAndSettle();
      expect(find.text('重试下载'), findsOneWidget);
      expect(find.text('安装新版'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('network errors remain in the dialog with a usable retry', (
    tester,
  ) async {
    final service = _Downloads();
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateDownloadDialog(update: _update, service: service),
      ),
    );
    await tester.tap(find.text('下载新版'));
    await tester.pump();
    service.pending.completeError(
      DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionTimeout,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('下载超时'), findsOneWidget);
    await tester.tap(find.text('重试下载'));
    await tester.pump();
    expect(service.starts, 2);
    service.pending.completeError(
      const UpdateDownloadException('安装包校验失败，请重新下载'),
    );
    await tester.pumpAndSettle();
    expect(find.text('安装包校验失败，请重新下载'), findsOneWidget);
    expect(find.text('安装新版'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'download dialog fits small screen and large text, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final service = _Downloads();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: UpdateDownloadDialog(update: _update, service: service),
          ),
        );
        await tester.tap(find.text('下载新版'));
        await tester.pump();
        service.progress(1024, -1);
        await tester.pump();
        expect(find.textContaining('已下载'), findsOneWidget);
        await tester.tap(find.text('取消下载'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
