import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/backup_service.dart';
import 'package:random_movie/services/webdav_sync_service.dart';
import 'package:random_movie/widgets/settings/webdav_sync_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnusedBackup implements SyncBackupStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No backup I/O expected');
}

class _Service extends WebDavSyncService {
  WebDavSyncConfig config;
  String? savedPassword;
  int connections = 0;
  _Service(SharedPreferences prefs, this.config)
    : super(backup: _UnusedBackup(), preferences: prefs);
  @override
  Future<WebDavSyncConfig> readConfig() async => config;
  @override
  Future<void> saveConfig({
    required String account,
    required String remoteDirectory,
    String? applicationPassword,
  }) async {
    savedPassword = applicationPassword;
    config = WebDavSyncConfig(
      account: account,
      remoteDirectory: remoteDirectory,
      hasPassword: applicationPassword?.isNotEmpty ?? config.hasPassword,
    );
  }

  @override
  Future<void> testConnection() async => connections++;
}

void main() {
  for (final configured in [false, true]) {
    testWidgets(
      'sync configuration initially ${configured ? 'collapsed' : 'expanded'} and fields survive toggling',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final service = _Service(
          await SharedPreferences.getInstance(),
          WebDavSyncConfig(
            account: configured ? 'test@example.com' : '',
            remoteDirectory: 'Pianke',
            hasPassword: configured,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: WebDavSyncSection(
                  serviceFuture: Future.value(service),
                  onRestored: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(configured ? '已配置坚果云' : '尚未配置坚果云'), findsOneWidget);
        expect(
          find.byType(TextField),
          configured ? findsNothing : findsNWidgets(3),
        );
        if (configured) {
          await tester.tap(find.text('配置'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField).first, 'new@example.com');
        await tester.tap(find.text('配置'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.text('上传备份'), findsOneWidget);
        expect(find.text('从云端恢复'), findsOneWidget);
        expect(find.text('同步'), findsOneWidget);
        await tester.tap(find.text('配置'));
        await tester.pumpAndSettle();
        expect(find.text('new@example.com'), findsOneWidget);
        if (!configured) {
          await tester.enterText(find.byType(TextField).at(1), 'new-password');
        }
        await tester.ensureVisible(find.text('保存并测试连接'));
        await tester.tap(find.text('保存并测试连接'));
        await tester.pumpAndSettle();
        expect(service.connections, 1);
        expect(service.savedPassword, configured ? isNull : 'new-password');
        expect(find.text('连接成功，远程目录可用'), findsOneWidget);
        expect(find.text('已配置坚果云'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
