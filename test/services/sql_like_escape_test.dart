import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/storage_service.dart';

void main() {
  group('escapeSqlLike', () {
    test('escapes percent and underscore so they match literally', () {
      expect(escapeSqlLike('100%'), r'100\%');
      expect(escapeSqlLike('a_b'), r'a\_b');
    });

    test('escapes the escape character itself first', () {
      expect(escapeSqlLike(r'a\b'), r'a\\b');
      expect(escapeSqlLike(r'\%'), r'\\\%');
    });

    test('leaves ordinary text, including Chinese, unchanged', () {
      expect(escapeSqlLike('千与千寻'), '千与千寻');
      expect(escapeSqlLike('spirited away'), 'spirited away');
      expect(escapeSqlLike(''), '');
    });
  });
}
