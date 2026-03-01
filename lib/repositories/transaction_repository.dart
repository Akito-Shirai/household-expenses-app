import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/transaction.dart';

/// 月次サマリー（集計結果）
class MonthlySummary {
  final int totalExpense;
  final int totalIncome;

  /// カテゴリ別支出 {カテゴリ名: 合計額}
  final Map<String, int> expenseByCategory;

  /// カテゴリ別収入 {カテゴリ名: 合計額}
  final Map<String, int> incomeByCategory;

  MonthlySummary({
    required this.totalExpense,
    required this.totalIncome,
    required this.expenseByCategory,
    required this.incomeByCategory,
  });

  /// 収支（収入 - 支出）
  int get net => totalIncome - totalExpense;
}

/// 取引のCRUD操作と集計を提供するリポジトリ
class TransactionRepository {
  final SupabaseClient _client;

  TransactionRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  /// 指定月の取引一覧を取得（カテゴリ名JOIN、日付降順）
  Future<List<Transaction>> listByMonth(int year, int month) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 1);

    final data = await _client
        .from('transactions')
        .select('*, categories(name)')
        .gte('date', startDate.toIso8601String().substring(0, 10))
        .lt('date', endDate.toIso8601String().substring(0, 10))
        .isFilter('expired_at', null)
        .order('date', ascending: false);

    return data.map((json) => Transaction.fromJson(json)).toList();
  }

  /// 指定日付範囲の取引一覧を取得（カテゴリ名JOIN、日付降順）
  /// [startDate] 以上 [endDate] 未満のレコードを返す
  Future<List<Transaction>> listByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final data = await _client
        .from('transactions')
        .select('*, categories(name)')
        .gte('date', startDate.toIso8601String().substring(0, 10))
        .lt('date', endDate.toIso8601String().substring(0, 10))
        .isFilter('expired_at', null)
        .order('date', ascending: false);

    return data.map((json) => Transaction.fromJson(json)).toList();
  }

  /// 取引を作成（user_id はDB側 default auth.uid() で設定）
  /// 支出時: amount = unitPrice * quantity で自動計算
  /// 収入時: amount をそのまま保存（unitPrice=null, quantity=1）
  Future<Transaction> create({
    required String categoryId,
    required DateTime date,
    required int amount,
    required String type,
    int? unitPrice,
    int quantity = 1,
    String? memo,
  }) async {
    // 支出時は単価×個数で合計を自動計算
    final effectiveAmount =
        (type == 'expense' && unitPrice != null) ? unitPrice * quantity : amount;

    final data = await _client
        .from('transactions')
        .insert({
          'category_id': categoryId,
          'date': date.toIso8601String().substring(0, 10),
          'amount': effectiveAmount,
          'unit_price': type == 'expense' ? unitPrice : null,
          'quantity': quantity,
          'type': type,
          'memo': memo,
        })
        .select('*, categories(name)')
        .single();
    return Transaction.fromJson(data);
  }

  /// 取引を更新（user_id条件でRLS+アプリ層の二重防御）
  /// 支出時: amount = unitPrice * quantity で自動計算
  Future<Transaction> update({
    required String id,
    required String categoryId,
    required DateTime date,
    required int amount,
    required String type,
    int? unitPrice,
    int quantity = 1,
    String? memo,
  }) async {
    // 支出時は単価×個数で合計を自動計算
    final effectiveAmount =
        (type == 'expense' && unitPrice != null) ? unitPrice * quantity : amount;

    final data = await _client
        .from('transactions')
        .update({
          'category_id': categoryId,
          'date': date.toIso8601String().substring(0, 10),
          'amount': effectiveAmount,
          'unit_price': type == 'expense' ? unitPrice : null,
          'quantity': quantity,
          'type': type,
          'memo': memo,
        })
        .eq('id', id)
        .eq('user_id', _userId)
        .select('*, categories(name)')
        .single();
    return Transaction.fromJson(data);
  }

  /// 取引を削除（user_id条件付き）
  Future<void> delete(String id) async {
    await _client
        .from('transactions')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId);
  }

  /// 取引リストから月次サマリーを集計する（純粋関数）
  static MonthlySummary summarize(List<Transaction> transactions) {
    int totalExpense = 0;
    int totalIncome = 0;
    final expenseByCategory = <String, int>{};
    final incomeByCategory = <String, int>{};

    for (final tx in transactions) {
      final catName = tx.categoryName ?? '不明';
      if (tx.type == 'expense') {
        totalExpense += tx.amount;
        expenseByCategory[catName] =
            (expenseByCategory[catName] ?? 0) + tx.amount;
      } else if (tx.type == 'income') {
        totalIncome += tx.amount;
        incomeByCategory[catName] =
            (incomeByCategory[catName] ?? 0) + tx.amount;
      }
    }

    return MonthlySummary(
      totalExpense: totalExpense,
      totalIncome: totalIncome,
      expenseByCategory: expenseByCategory,
      incomeByCategory: incomeByCategory,
    );
  }
}
