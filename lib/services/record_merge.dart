// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
import 'package:random_movie/services/hlc.dart';

/// 带版本信息的记录行。
///
/// 只保留合并真正需要的东西：[id] 用来配对，[updatedAt] 用来判新旧，
/// [deletedAt] 用来表达墓碑，[payload] 是其余字段。
class VersionedRow {
  final String id;
  final String updatedAt;
  final String? deletedAt;
  final Map<String, dynamic> payload;

  const VersionedRow({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.payload = const {},
  });

  /// 是否已被删除（墓碑）。
  bool get isTombstone => deletedAt != null && deletedAt!.isNotEmpty;

  Hlc get clock => Hlc.tryParse(updatedAt) ?? Hlc.zero;

  Hlc get deletedClock => Hlc.tryParse(deletedAt) ?? Hlc.zero;

  /// 这条记录「最后发生了什么」的时间：普通更新取 updatedAt，
  /// 墓碑取 deletedAt 与 updatedAt 中较晚的那个。
  ///
  /// 这是「先删后改」与「先改后删」能分出胜负的关键。
  Hlc get latestClock {
    if (!isTombstone) return clock;
    return deletedClock > clock ? deletedClock : clock;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'updatedAt': updatedAt,
    if (deletedAt != null) 'deletedAt': deletedAt,
    ...payload,
  };

  static VersionedRow? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final payload = Map<String, dynamic>.of(json)
      ..remove('id')
      ..remove('updatedAt')
      ..remove('deletedAt');
    return VersionedRow(
      id: id,
      updatedAt: json['updatedAt']?.toString() ?? '',
      deletedAt: json['deletedAt']?.toString(),
      payload: payload,
    );
  }
}

/// 合并结果：合并后的行 + 统计（用于日志与「合并预览」）。
class MergeOutcome {
  /// 按 id 合并后的全部行（含墓碑，由调用方决定是否物理删除）。
  final List<VersionedRow> rows;

  /// 采用了云端版本的条数（本机被覆盖）。
  final int takenFromRemote;

  /// 保留了本机版本的条数。
  final int keptLocal;

  /// 两边内容不同、但按时间判定了胜负的条数。
  final int conflictsResolved;

  const MergeOutcome({
    required this.rows,
    required this.takenFromRemote,
    required this.keptLocal,
    required this.conflictsResolved,
  });

  int get total => rows.length;
}

/// 记录级合并 —— 纯函数，不碰数据库，便于穷尽测试。
///
/// 规则只有一条：**同 id 取「最后动作」更晚的一方**。
/// - 同一部影片 A 改标题、B 改评分 → 两处修改都留下（因为它们 id 不同，
///   或者同 id 时按时间取较新的整行）；
/// - A 删了、B 在删之前改 → 删除更新，删除胜出；
/// - A 删了、B 在删之后改 → 修改更新，记录复活。
///
/// 墓碑行保留在结果里（[MergeOutcome.rows] 含墓碑），
/// 由调用方过滤或按保留期清理——合并本身绝不静默丢行。
MergeOutcome mergeRows(
  List<VersionedRow> local,
  List<VersionedRow> remote,
) {
  final byId = <String, VersionedRow>{for (final row in local) row.id: row};
  var takenFromRemote = 0;
  var keptLocal = 0;
  var conflicts = 0;

  for (final incoming in remote) {
    final mine = byId[incoming.id];
    if (mine == null) {
      byId[incoming.id] = incoming;
      takenFromRemote++;
      continue;
    }

    final comparison = incoming.latestClock.compareTo(mine.latestClock);
    if (comparison > 0) {
      // 云端更新：接管。若两边内容不同，算一次「冲突已判定」。
      if (_differs(mine, incoming)) conflicts++;
      byId[incoming.id] = incoming;
      takenFromRemote++;
    } else {
      // 本机更新或完全相同：保留本机。
      if (comparison < 0 && _differs(mine, incoming)) conflicts++;
      keptLocal++;
    }
  }

  return MergeOutcome(
    rows: byId.values.toList(growable: false),
    takenFromRemote: takenFromRemote,
    keptLocal: keptLocal,
    conflictsResolved: conflicts,
  );
}

/// 两行除了时间戳之外，内容是否真的不同。
bool _differs(VersionedRow a, VersionedRow b) {
  if (a.deletedAt != b.deletedAt) return true;
  if (a.payload.length != b.payload.length) return true;
  for (final entry in a.payload.entries) {
    final other = b.payload[entry.key];
    if (!_sameValue(entry.value, other)) return true;
  }
  return false;
}

bool _sameValue(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  return a == b;
}

/// 子表过滤：父记录是墓碑时，其子记录也视为已删。
///
/// 会话、标签关联这些子记录本身不需要墓碑——影片被删了它们就不该出现。
/// 这样合并时子表可以是纯粹的「并集」，不需要每个子表都维护一套删除标记。
List<VersionedRow> dropChildrenOfTombstones(
  List<VersionedRow> children,
  Iterable<VersionedRow> parents, {
  required String Function(VersionedRow child) parentIdOf,
}) {
  final deadParentIds = {
    for (final parent in parents)
      if (parent.isTombstone) parent.id,
  };
  if (deadParentIds.isEmpty) return children;
  return children
      .where((child) => !deadParentIds.contains(parentIdOf(child)))
      .toList(growable: false);
}

/// 墓碑清理：删除满 [retentionDays] 天后，物理移除。
///
/// 保留一段时间是必要的——否则刚删掉的行立刻消失，另一台设备离线一个月后
/// 再同步，会把这条记录当成「从来没删过」而复活它。
List<VersionedRow> purgeOldTombstones(
  List<VersionedRow> rows, {
  required DateTime now,
  int retentionDays = 90,
}) {
  final cutoff = now.subtract(Duration(days: retentionDays));
  final cutoffHlc = Hlc(
    physicalMs: cutoff.millisecondsSinceEpoch,
    counter: 0,
    deviceId: '',
  );
  return rows
      .where((row) {
        if (!row.isTombstone) return true;
        // 注意用 deletedClock 而不是 latestClock：保留期是从「删除那一刻」算的。
        return row.deletedClock >= cutoffHlc;
      })
      .toList(growable: false);
}
