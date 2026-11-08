import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:random_movie/pages/settings/settings_page.dart';
import 'package:random_movie/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages_test.dart' show providers;

class FakeUpdateService extends UpdateService {
  int checks = 0;
  bool fail = false;
  @override
  Future<UpdateCheckResult> checkForUpdate() async {
    checks++;
    if (fail) throw Exception('offline');
    return UpdateCheckResult(
      current: PackageInfo(
        appName: '片刻',
        packageName: 'app.pianke.personal',
        version: '0.2.1',
        buildNumber: '6',
      ),
      update: const AppUpdateInfo(
        versionName: '0.2.2',
        versionCode: 7,
        title: '新版',
        changelog: ['体验修复'],
        downloadUrl:
            'https://github.com/example/app/releases/download/v7/app.apk',
        forceUpdate: false,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    PackageInfo.setMockInitialValues(
      appName: '片刻',
      packageName: 'app.pianke.personal',
      version: '0.2.1',
      buildNumber: '6',
      buildSignature: '',
    );
  });
  testWidgets(
    'only manual check opens update dialog and launches external browser',
    (tester) async {
      final service = FakeUpdateService();
      MethodCall? launch;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/url_launcher'),
            (call) async {
              launch = call;
              return true;
            },
          );
      await tester.pumpWidget(
        providers(MaterialApp(home: SettingsPage(updateService: service))),
      );
      await tester.pumpAndSettle();
      expect(service.checks, 0);
      await tester.scrollUntilVisible(
        find.text('检查更新'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.checks, 1);
      expect(find.text('发现焕新版更新'), findsOneWidget);
      expect(find.text('稍后'), findsOneWidget);
      await tester.tap(find.text('下载新版'));
      await tester.pumpAndSettle();
      expect(launch?.method, 'launch');
      expect(
        launch?.arguments['url'],
        'https://github.com/example/app/releases/download/v7/app.apk',
      );
      expect(launch?.arguments['useWebView'], isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      service.fail = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(service.checks, 2);
      expect(find.text('检查更新失败，请稍后再试'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );
}
