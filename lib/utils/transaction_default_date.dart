import '../models/transaction.dart' as model;

/// 新規取引追加時のデフォルト日付を、表示中年月と当月取引一覧から決定する。
///
/// - 表示中年月が当月: 本日
/// - 表示中年月が当月以外で取引あり: 表示中年月内の最新取引日
/// - 表示中年月が当月以外で取引なし: 表示中年月の1日
///
/// [now] はテスト容易性のために注入可能。省略時は `DateTime.now()`。
DateTime defaultDateForNewTransaction({
  required int year,
  required int month,
  required List<model.Transaction> transactions,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);

  if (year == today.year && month == today.month) {
    return today;
  }

  DateTime? latest;
  for (final tx in transactions) {
    final d = DateTime(tx.date.year, tx.date.month, tx.date.day);
    // 表示中月以外の取引は無視（防御的: 通常は当月分のみ渡される想定）
    if (d.year != year || d.month != month) continue;
    if (latest == null || d.isAfter(latest)) latest = d;
  }

  return latest ?? DateTime(year, month, 1);
}
