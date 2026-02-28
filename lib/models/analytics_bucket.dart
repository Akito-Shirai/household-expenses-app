import 'transaction.dart';

/// 集計粒度
enum AnalyticsPeriod { daily, monthly, yearly }

/// 1バケットの集計結果（日/月/年ごとの支出・収入・収支）
class AnalyticsBucket {
  /// バケットのラベル（例: "2/15", "3月", "2025"）
  final String label;

  /// バケットのソートキー（日付文字列: "2026-02-15", "2026-03", "2026"）
  final String sortKey;

  final int expense;
  final int income;

  int get net => income - expense;

  const AnalyticsBucket({
    required this.label,
    required this.sortKey,
    required this.expense,
    required this.income,
  });
}

/// 集計ロジック（純粋関数）
class AnalyticsAggregator {
  AnalyticsAggregator._();

  /// 取引リストを指定粒度でバケット化
  /// [categoryIds] が空でなければ、該当カテゴリのみ集計
  static List<AnalyticsBucket> aggregate({
    required List<Transaction> transactions,
    required AnalyticsPeriod period,
    Set<String> categoryIds = const {},
  }) {
    // カテゴリフィルタ適用
    final filtered = categoryIds.isEmpty
        ? transactions
        : transactions.where((tx) => categoryIds.contains(tx.categoryId)).toList();

    // バケットキー生成関数
    String Function(Transaction) keyFn;
    String Function(String) labelFn;

    switch (period) {
      case AnalyticsPeriod.daily:
        keyFn = (tx) => tx.date.toIso8601String().substring(0, 10);
        labelFn = (key) {
          final d = DateTime.parse(key);
          return '${d.month}/${d.day}';
        };
      case AnalyticsPeriod.monthly:
        keyFn = (tx) =>
            '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
        labelFn = (key) => '${int.parse(key.split('-')[1])}月';
      case AnalyticsPeriod.yearly:
        keyFn = (tx) => '${tx.date.year}';
        labelFn = (key) => '$key年';
    }

    // バケットに振り分け
    final expenseMap = <String, int>{};
    final incomeMap = <String, int>{};

    for (final tx in filtered) {
      final key = keyFn(tx);
      if (tx.type == 'expense') {
        expenseMap[key] = (expenseMap[key] ?? 0) + tx.amount;
      } else if (tx.type == 'income') {
        incomeMap[key] = (incomeMap[key] ?? 0) + tx.amount;
      }
    }

    // 全キーを統合してソート
    final allKeys = {...expenseMap.keys, ...incomeMap.keys}.toList()..sort();

    return allKeys
        .map((key) => AnalyticsBucket(
              label: labelFn(key),
              sortKey: key,
              expense: expenseMap[key] ?? 0,
              income: incomeMap[key] ?? 0,
            ))
        .toList();
  }

  /// フィルタ適用後の合計を計算（グラフと同一条件）
  static ({int totalExpense, int totalIncome, int net}) totals({
    required List<Transaction> transactions,
    Set<String> categoryIds = const {},
  }) {
    final filtered = categoryIds.isEmpty
        ? transactions
        : transactions.where((tx) => categoryIds.contains(tx.categoryId)).toList();

    int totalExpense = 0;
    int totalIncome = 0;

    for (final tx in filtered) {
      if (tx.type == 'expense') {
        totalExpense += tx.amount;
      } else if (tx.type == 'income') {
        totalIncome += tx.amount;
      }
    }

    return (
      totalExpense: totalExpense,
      totalIncome: totalIncome,
      net: totalIncome - totalExpense,
    );
  }
}
