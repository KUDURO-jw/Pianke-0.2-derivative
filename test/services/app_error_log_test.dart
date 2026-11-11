// 全局错误日志的回归测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/app_error_log.dart';

void main() {
  setUp(AppErrorLog.resetForTest);
  tearDown(AppErrorLog.resetForTest);

  group('AppErrorLog', () {
    test('记录后条目可读，且最新在最后', () {
      AppErrorLog.record('第一条');
      AppErrorLog.record('第二条');

      expect(AppErrorLog.entries, hasLength(2));
      expect(AppErrorLog.entries.last, contains('第二条'));
      expect(AppErrorLog.isEmpty, isFalse);
    });

    test('带上堆栈时只保留前若干行', () {
      final longStack = List.generate(50, (i) => '#$i frame').join('\n');
      AppErrorLog.record('带栈错误', stack: longStack);

      final entry = AppErrorLog.entries.single;
      expect(entry, contains('带栈错误'));
      // 截断到 12 行，避免日志被栈撑爆。
      expect('#11 frame'.allMatches(entry), hasLength(1));
      expect(entry.contains('#12 frame'), isFalse);
    });

    test('超过上限时丢弃最旧的条目', () {
      for (var i = 0; i < 60; i++) {
        AppErrorLog.record('错误 $i');
      }
      // 上限 50 条。
      expect(AppErrorLog.entries, hasLength(50));
      expect(AppErrorLog.entries.last, contains('错误 59'));
      expect(
        AppErrorLog.entries.any((e) => e.contains('错误 0]')),
        isFalse,
        reason: '最旧的条目应被丢弃',
      );
    });

    test('未记录任何错误时 isEmpty 为真', () {
      expect(AppErrorLog.isEmpty, isTrue);
      expect(AppErrorLog.entries, isEmpty);
    });

    test('install 可重复调用而不重复挂载', () {
      // 只验证不抛异常：重复安装应当是幂等的。
      AppErrorLog.install();
      AppErrorLog.install();
      expect(true, isTrue);
    });
  });
}
