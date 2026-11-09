// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
/// 混合逻辑时钟（Hybrid Logical Clock, HLC）。
///
/// 记录级合并需要「谁更新」这一个判断。用墙钟时间直接比是危险的：
/// 手机时间可能被手动调慢、或在飞行模式下漂移，于是一次「更晚」的修改
/// 反而带着更早的时间戳，合并时被丢弃——数据就这么没了。
///
/// HLC 的做法是：物理时间只增不减，同一毫秒内用计数器区分先后，
/// 再拼上设备 id 打破平局。这样：
/// - 时钟回拨不会让时间戳倒退；
/// - 同一设备同一毫秒的多次修改仍有确定顺序；
/// - 不同设备的并发修改有稳定的比较结果（不依赖谁先跑）。
///
/// 字符串形式 `物理毫秒(19位补零)-计数器(4位)-设备id`，
/// **字典序即时间序**，可以直接存进 TEXT 列用 SQL 排序和比较。
class Hlc implements Comparable<Hlc> {
  /// 物理时间部分（毫秒）。
  final int physicalMs;

  /// 同一毫秒内的序号，从 0 开始。
  final int counter;

  /// 产生这条记录的设备标识，用于跨设备平局。
  final String deviceId;

  const Hlc({
    required this.physicalMs,
    required this.counter,
    required this.deviceId,
  });

  /// 最小可能值，用于「还没有时间戳」的记录。
  static const Hlc zero = Hlc(physicalMs: 0, counter: 0, deviceId: '');

  /// 解析字符串形式；格式不对返回 null（调用方按最旧处理）。
  static Hlc? tryParse(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('-');
    if (parts.length < 3) return null;
    final physical = int.tryParse(parts[0]);
    final counter = int.tryParse(parts[1]);
    if (physical == null || counter == null) return null;
    // 设备 id 本身可能含 '-'，后面全部拼回去。
    final deviceId = parts.sublist(2).join('-');
    return Hlc(physicalMs: physical, counter: counter, deviceId: deviceId);
  }

  /// 字符串形式：物理毫秒补到 19 位（远期不会溢出），计数器补到 4 位。
  String encode() {
    final physical = physicalMs.toString().padLeft(19, '0');
    final count = counter.toString().padLeft(4, '0');
    return '$physical-$count-$deviceId';
  }

  @override
  int compareTo(Hlc other) {
    if (physicalMs != other.physicalMs) {
      return physicalMs.compareTo(other.physicalMs);
    }
    if (counter != other.counter) return counter.compareTo(other.counter);
    // 物理时间与计数器都相同时，用设备 id 保证确定的全序。
    return deviceId.compareTo(other.deviceId);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.physicalMs == physicalMs &&
      other.counter == counter &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(physicalMs, counter, deviceId);

  @override
  String toString() => encode();
}

/// 在一台设备上生成递增的 HLC。
///
/// 用法：每次写入记录前调用 [now]，把结果存进 `updated_at`。
/// 注意它**不是**线程安全的（Dart 单线程事件循环下无此问题），
/// 但同一个实例必须被复用，否则「同一毫秒内递增」的保证会失效。
class HlcClock {
  final String deviceId;
  final DateTime Function() _wallClock;

  int _lastPhysical = 0;
  int _counter = 0;

  HlcClock({required this.deviceId, DateTime Function()? wallClock})
    : _wallClock = wallClock ?? DateTime.now;

  /// 从已有记录恢复状态，避免重启后生成比历史更旧的时间戳。
  void observe(Hlc? previous) {
    if (previous == null) return;
    if (previous.physicalMs > _lastPhysical) {
      _lastPhysical = previous.physicalMs;
      _counter = previous.counter;
    } else if (previous.physicalMs == _lastPhysical &&
        previous.counter > _counter) {
      _counter = previous.counter;
    }
  }

  /// 取一个新的时间戳。
  Hlc now() {
    final wallMs = _wallClock().millisecondsSinceEpoch;
    if (wallMs > _lastPhysical) {
      // 正常前进：物理时间接管，计数器归零。
      _lastPhysical = wallMs;
      _counter = 0;
    } else {
      // 墙钟没前进（同一毫秒内，或时钟被回拨）：保持物理时间，计数器递增。
      // 这正是「时钟慢 5 分钟也不会回退」的原因。
      _counter++;
    }
    return Hlc(
      physicalMs: _lastPhysical,
      counter: _counter,
      deviceId: deviceId,
    );
  }
}
