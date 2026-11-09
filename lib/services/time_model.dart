// Modified for the personal UI edition, 2026-11-08. Apache-2.0.
/// 观影时间的两套表示。
///
/// 「某天看了电影」本质是一个**日期**，不是时刻。原先只存一个不带时区的
/// 本地时间字符串，快照里又用 UTC，按字符串排序在格式不一致时会错，
/// 用时刻推日历在换时区时还会偏一天。
///
/// 于是拆成两个各司其职的值：
/// - [watchedAtUtcMs]：UTC 毫秒，**只用来排序 / 比较**，与时区无关；
/// - [watchedOn]：用户当地日期 `YYYY-MM-DD`，**只用来分组**（日历、年度回顾）。
///
/// 两者在写入时一起算出，此后永不再从对方反推，避免时区一换就漂移。
library;

/// 把本地日期格式化成 `YYYY-MM-DD`。
String formatWatchedOn(DateTime local) {
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// 由「本地时刻」推出当地日期。
///
/// 注意调用方传入的应当已经是本地时间；传入 UTC 时间会得到 UTC 的日期。
String watchedOnOf(DateTime dateTime) => formatWatchedOn(dateTime.toLocal());

/// 把 ISO 字符串解析成 UTC 毫秒；解析失败返回 null（迁移时用于记录异常数据）。
int? parseUtcMillis(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw.trim());
  return parsed?.toUtc().millisecondsSinceEpoch;
}

/// 从可能是任意格式的旧字符串里尽力取出「当地日期」。
///
/// 迁移历史数据时用：优先用能解析出的时间；解析不了就退而取字符串前 10 位
/// （若形如 `YYYY-MM-DD`）。两者都不成立返回 null，由调用方记录并跳过。
String? salvageWatchedOn(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final parsed = DateTime.tryParse(trimmed);
  if (parsed != null) return watchedOnOf(parsed);

  final head = trimmed.length >= 10 ? trimmed.substring(0, 10) : trimmed;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(head)) return head;
  return null;
}

/// 由 UTC 毫秒还原成本地时刻；为空返回 null。
DateTime? localFromUtcMillis(int? millis) {
  if (millis == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
}
