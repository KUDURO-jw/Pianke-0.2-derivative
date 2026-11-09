// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:flutter_test/flutter_test.dart';
import 'package:random_movie/services/hlc.dart';
import 'package:random_movie/services/record_merge.dart';

/// 构造一条记录：物理时间用「秒」当单位方便阅读。
VersionedRow _row(
  String id, {
  int ms = 1000,
  int counter = 0,
  String device = 'A',
  String? deletedAt,
  Map<String, dynamic> payload = const {},
}) => VersionedRow(
  id: id,
  updatedAt: Hlc(physicalMs: ms, counter: counter, deviceId: device).encode(),
  deletedAt: deletedAt,
  payload: payload,
);

VersionedRow _tombstone(String id, {int ms = 1000, String device = 'A'}) =>
    VersionedRow(
      id: id,
      updatedAt: Hlc(physicalMs: ms, counter: 0, deviceId: device).encode(),
      deletedAt: Hlc(physicalMs: ms, counter: 0, deviceId: device).encode(),
    );

void main() {
  group('T3 HLC 编码与比较', () {
    test('字符串形式字典序等于时间序', () {
      final early = Hlc(physicalMs: 1000, counter: 0, deviceId: 'A');
      final late = Hlc(physicalMs: 2000, counter: 0, deviceId: 'A');
      expect(early.encode().compareTo(late.encode()), lessThan(0));
      expect(early < late, isTrue);
    });

    test('同一毫秒内用计数器分出先后', () {
      final first = Hlc(physicalMs: 1000, counter: 0, deviceId: 'A');
      final second = Hlc(physicalMs: 1000, counter: 1, deviceId: 'A');
      expect(second > first, isTrue);
      expect(second.encode().compareTo(first.encode()), greaterThan(0));
    });

    test('编码可无损往返', () {
      const original = Hlc(
        physicalMs: 1730000000000,
        counter: 42,
        deviceId: 'device-with-dash',
      );
      final restored = Hlc.tryParse(original.encode());
      expect(restored, original);
    });

    test('非法字符串解析为 null（调用方按最旧处理）', () {
      expect(Hlc.tryParse(null), isNull);
      expect(Hlc.tryParse(''), isNull);
      expect(Hlc.tryParse('乱码'), isNull);
      expect(Hlc.tryParse('123'), isNull);
    });

    test('补零保证 19 位物理时间与 4 位计数器', () {
      final hlc = Hlc(physicalMs: 5, counter: 3, deviceId: 'A');
      final encoded = hlc.encode();
      expect(encoded.split('-')[0].length, 19);
      expect(encoded.split('-')[1].length, 4);
    });

    test('不同设备同时刻的并发修改仍可确定比较', () {
      final a = Hlc(physicalMs: 1000, counter: 0, deviceId: 'A');
      final b = Hlc(physicalMs: 1000, counter: 0, deviceId: 'B');
      expect(a.compareTo(b), isNot(0), reason: '必须能分出确定顺序');
      // 反过来比较结果取反，保证全序一致。
      expect(b.compareTo(a), isNot(0));
      expect(a.compareTo(b).sign, -b.compareTo(a).sign);
    });
  });

  group('T3 HlcClock：时钟慢 5 分钟也不回退', () {
    test('墙钟静止时计数器递增', () {
      final clock = HlcClock(
        deviceId: 'A',
        wallClock: () => DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final first = clock.now();
      final second = clock.now();
      final third = clock.now();

      expect(second > first, isTrue);
      expect(third > second, isTrue);
      expect(second.physicalMs, first.physicalMs, reason: '物理时间不该前进');
    });

    test('墙钟被回拨到更早，时间戳仍然递增', () {
      var wall = 10000;
      final clock = HlcClock(
        deviceId: 'A',
        wallClock: () => DateTime.fromMillisecondsSinceEpoch(wall),
      );

      final before = clock.now();
      // 用户手动把系统时间调早 5 分钟。
      wall = 10000 - 5 * 60 * 1000;
      final after = clock.now();

      expect(
        after > before,
        isTrue,
        reason: '时钟回拨后新时间戳必须仍然更新（否则新修改会被旧数据覆盖）',
      );
      expect(after.physicalMs, 10000, reason: '物理时间不应倒退');
    });

    test('墙钟正常前进时物理时间接管且计数器归零', () {
      var wall = 1000;
      final clock = HlcClock(
        deviceId: 'A',
        wallClock: () => DateTime.fromMillisecondsSinceEpoch(wall),
      );

      clock.now();
      clock.now(); // 同一毫秒，counter=1
      wall = 2000;
      final jumped = clock.now();

      expect(jumped.physicalMs, 2000);
      expect(jumped.counter, 0);
    });

    test('observe 能吸收历史时间戳，重启后不会更旧', () {
      final clock = HlcClock(
        deviceId: 'A',
        wallClock: () => DateTime.fromMillisecondsSinceEpoch(500),
      );
      final previous = Hlc(physicalMs: 9000, counter: 7, deviceId: 'B');
      clock.observe(previous);

      final next = clock.now();
      expect(next > previous, isTrue);
    });
  });

  group('T3 mergeRows：各改各的，都不丢', () {
    test('两个设备改的是不同影片 → 两条都在', () {
      final local = [_row('m1', ms: 1000, device: 'A', payload: {'t': 'A改'})];
      final remote = [_row('m2', ms: 1000, device: 'B', payload: {'t': 'B改'})];

      final result = mergeRows(local, remote);
      expect(result.rows.length, 2);
      expect(result.rows.map((r) => r.id).toSet(), {'m1', 'm2'});
      expect(result.conflictsResolved, 0);
    });

    test('同一影片两边都改 → 取更晚的一方', () {
      final local = [_row('m1', ms: 1000, payload: {'t': '旧'})];
      final remote = [_row('m1', ms: 2000, payload: {'t': '新'})];

      final result = mergeRows(local, remote);
      expect(result.rows.single.payload['t'], '新');
      expect(result.takenFromRemote, 1);
      expect(result.conflictsResolved, 1);
    });

    test('本地更晚时保留本地', () {
      final local = [_row('m1', ms: 3000, payload: {'t': '本地新'})];
      final remote = [_row('m1', ms: 2000, payload: {'t': '云端旧'})];

      final result = mergeRows(local, remote);
      expect(result.rows.single.payload['t'], '本地新');
      expect(result.keptLocal, 1);
      expect(result.takenFromRemote, 0);
    });

    test('内容完全相同不算冲突', () {
      final row = _row('m1', ms: 1000, payload: {'t': '一样'});
      final result = mergeRows([row], [_row('m1', ms: 1000, payload: {'t': '一样'})]);
      expect(result.conflictsResolved, 0);
      expect(result.rows.single.payload['t'], '一样');
    });
  });

  group('T3 mergeRows：删除与修改谁胜出', () {
    test('A 删除、B 在删除之前修改 → 删除胜出', () {
      // 删除发生在 2000，B 的修改发生在 1000（更早）。
      final local = [_tombstone('m1', ms: 2000, device: 'A')];
      final remote = [_row('m1', ms: 1000, device: 'B', payload: {'t': 'B改'})];

      final result = mergeRows(local, remote);
      expect(result.rows.single.isTombstone, isTrue, reason: '删除更新，应胜出');
    });

    test('A 删除、B 在删除之后修改 → 修改胜出（复活）', () {
      final local = [_tombstone('m1', ms: 1000, device: 'A')];
      final remote = [_row('m1', ms: 2000, device: 'B', payload: {'t': 'B改'})];

      final result = mergeRows(local, remote);
      expect(result.rows.single.isTombstone, isFalse, reason: '修改更新，应复活');
      expect(result.rows.single.payload['t'], 'B改');
    });

    test('远端删除、本地更晚修改 → 本地复活', () {
      final local = [_row('m1', ms: 3000, device: 'A', payload: {'t': '本地改'})];
      final remote = [_tombstone('m1', ms: 2000, device: 'B')];

      final result = mergeRows(local, remote);
      expect(result.rows.single.isTombstone, isFalse);
      expect(result.rows.single.payload['t'], '本地改');
    });

    test('墓碑参与比较而不是被直接跳过', () {
      final local = [ _row('m1', ms: 1000) ];
      final remote = [ _tombstone('m1', ms: 5000) ];
      final result = mergeRows(local, remote);
      // 若墓碑被跳过，这里会保留本地；正确行为是删除生效。
      expect(result.rows.single.isTombstone, isTrue);
    });
  });

  group('T3 子表随父记录墓碑一起消失', () {
    test('父是墓碑时，其子记录被过滤掉', () {
      final parents = [_tombstone('m1'), _row('m2')];
      final children = [
        _row('s1', payload: {'movieId': 'm1'}),
        _row('s2', payload: {'movieId': 'm2'}),
      ];

      final kept = dropChildrenOfTombstones(
        children,
        parents,
        parentIdOf: (child) => child.payload['movieId'] as String,
      );

      expect(kept.map((c) => c.id), ['s2']);
    });

    test('没有墓碑时不改变任何子记录', () {
      final parents = [_row('m1')];
      final children = [_row('s1', payload: {'movieId': 'm1'})];
      final kept = dropChildrenOfTombstones(
        children,
        parents,
        parentIdOf: (child) => child.payload['movieId'] as String,
      );
      expect(kept.length, 1);
    });
  });

  group('T3 墓碑保留期', () {
    test('未满 90 天的墓碑保留（避免离线设备复活旧数据）', () {
      final now = DateTime.utc(2026, 6, 1);
      final recent = _tombstone(
        'm1',
        ms: now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
      );
      final kept = purgeOldTombstones([recent], now: now);
      expect(kept.length, 1);
    });

    test('超过 90 天的墓碑被物理清除', () {
      final now = DateTime.utc(2026, 6, 1);
      final old = _tombstone(
        'm1',
        ms: now.subtract(const Duration(days: 100)).millisecondsSinceEpoch,
      );
      final kept = purgeOldTombstones([old], now: now);
      expect(kept, isEmpty);
    });

    test('普通记录永远不会被清理', () {
      final now = DateTime.utc(2026, 6, 1);
      final ancient = _row('m1', ms: 1); // 1970 年的记录
      final kept = purgeOldTombstones([ancient], now: now);
      expect(kept.length, 1);
    });
  });

  group('T3 合并的确定性与幂等', () {
    test('交换两边顺序结果一致（对称）', () {
      final a = [
        _row('m1', ms: 1000, payload: {'t': 'A'}),
        _row('m2', ms: 3000, payload: {'t': 'A2'}),
      ];
      final b = [
        _row('m1', ms: 2000, payload: {'t': 'B'}),
        _row('m3', ms: 500, payload: {'t': 'B3'}),
      ];

      final ab = mergeRows(a, b);
      final ba = mergeRows(b, a);

      final abById = {for (final r in ab.rows) r.id: r.payload['t']};
      final baById = {for (final r in ba.rows) r.id: r.payload['t']};
      expect(abById, baById);
    });

    test('合并两次与合并一次结果相同（幂等）', () {
      final local = [_row('m1', ms: 1000, payload: {'t': 'L'})];
      final remote = [_row('m1', ms: 2000, payload: {'t': 'R'}), _row('m2', ms: 500)];

      final once = mergeRows(local, remote);
      final twice = mergeRows(once.rows, remote);
      expect(
        {for (final r in twice.rows) r.id: r.updatedAt},
        {for (final r in once.rows) r.id: r.updatedAt},
      );
    });

    test('空的一侧不成问题', () {
      expect(mergeRows([], []).rows, isEmpty);
      expect(mergeRows([], [_row('m1')]).rows.length, 1);
      expect(mergeRows([_row('m1')], []).rows.length, 1);
    });
  });

  group('T3 VersionedRow 序列化', () {
    test('往返保留时间戳、墓碑与载荷', () {
      final row = VersionedRow(
        id: 'm1',
        updatedAt: Hlc(physicalMs: 1000, counter: 2, deviceId: 'A').encode(),
        deletedAt: Hlc(physicalMs: 2000, counter: 0, deviceId: 'A').encode(),
        payload: {'title': '片名', 'year': '2020'},
      );
      final restored = VersionedRow.fromJson(row.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, 'm1');
      expect(restored.updatedAt, row.updatedAt);
      expect(restored.deletedAt, row.deletedAt);
      expect(restored.payload['title'], '片名');
      expect(restored.isTombstone, isTrue);
    });

    test('缺 id 的行返回 null（调用方跳过）', () {
      expect(VersionedRow.fromJson({'updatedAt': 'x'}), isNull);
      expect(VersionedRow.fromJson({'id': ''}), isNull);
    });
  });
}
