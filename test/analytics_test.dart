import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/analytics_bucket.dart';
import 'package:household_mvp/models/transaction.dart';

/// テスト用Transactionヘルパー
Transaction _tx({
  required DateTime date,
  required String type,
  required int amount,
  String categoryId = 'cat-1',
  String categoryName = 'テスト',
}) {
  return Transaction(
    id: 'id-${date.toIso8601String()}-$type-$amount',
    userId: 'user',
    categoryId: categoryId,
    date: date,
    amount: amount,
    type: type,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    categoryName: categoryName,
  );
}

void main() {
  group('AnalyticsAggregator.aggregate: 日別', () {
    test('同月内の日別バケットが正しく生成される', () {
      final transactions = [
        _tx(date: DateTime(2026, 2, 1), type: 'expense', amount: 1000),
        _tx(date: DateTime(2026, 2, 1), type: 'income', amount: 5000),
        _tx(date: DateTime(2026, 2, 3), type: 'expense', amount: 2000),
        _tx(date: DateTime(2026, 2, 5), type: 'expense', amount: 500),
      ];

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.daily,
      );

      expect(buckets.length, 3); // 2/1, 2/3, 2/5
      expect(buckets[0].label, '2/1');
      expect(buckets[0].expense, 1000);
      expect(buckets[0].income, 5000);
      expect(buckets[0].net, 4000);
      expect(buckets[1].label, '2/3');
      expect(buckets[1].expense, 2000);
      expect(buckets[2].label, '2/5');
      expect(buckets[2].expense, 500);
    });

    test('空リストで空バケット', () {
      final buckets = AnalyticsAggregator.aggregate(
        transactions: [],
        period: AnalyticsPeriod.daily,
      );
      expect(buckets, isEmpty);
    });
  });

  group('AnalyticsAggregator.aggregate: 月別', () {
    test('年内の月別バケットが正しく生成される', () {
      final transactions = [
        _tx(date: DateTime(2026, 1, 15), type: 'expense', amount: 10000),
        _tx(date: DateTime(2026, 3, 10), type: 'expense', amount: 20000),
        _tx(date: DateTime(2026, 3, 20), type: 'income', amount: 50000),
        _tx(date: DateTime(2026, 6, 1), type: 'income', amount: 300000),
      ];

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.monthly,
      );

      expect(buckets.length, 3); // 1月, 3月, 6月
      expect(buckets[0].label, '1月');
      expect(buckets[0].expense, 10000);
      expect(buckets[1].label, '3月');
      expect(buckets[1].expense, 20000);
      expect(buckets[1].income, 50000);
      expect(buckets[2].label, '6月');
      expect(buckets[2].income, 300000);
    });
  });

  group('AnalyticsAggregator.aggregate: 年別', () {
    test('複数年のバケットが正しく生成される', () {
      final transactions = [
        _tx(date: DateTime(2024, 6, 1), type: 'expense', amount: 100000),
        _tx(date: DateTime(2025, 3, 1), type: 'expense', amount: 200000),
        _tx(date: DateTime(2025, 9, 1), type: 'income', amount: 500000),
        _tx(date: DateTime(2026, 1, 1), type: 'income', amount: 300000),
      ];

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.yearly,
      );

      expect(buckets.length, 3); // 2024, 2025, 2026
      expect(buckets[0].label, '2024年');
      expect(buckets[0].expense, 100000);
      expect(buckets[1].label, '2025年');
      expect(buckets[1].expense, 200000);
      expect(buckets[1].income, 500000);
      expect(buckets[1].net, 300000);
      expect(buckets[2].label, '2026年');
      expect(buckets[2].income, 300000);
    });
  });

  group('AnalyticsAggregator.aggregate: カテゴリフィルタ', () {
    test('指定カテゴリのみ集計される', () {
      final transactions = [
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 1000,
          categoryId: 'food',
        ),
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 5000,
          categoryId: 'rent',
        ),
        _tx(
          date: DateTime(2026, 2, 2),
          type: 'expense',
          amount: 2000,
          categoryId: 'food',
        ),
      ];

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.daily,
        categoryIds: {'food'},
      );

      expect(buckets.length, 2); // 2/1, 2/2（rentはフィルタで除外）
      expect(buckets[0].expense, 1000); // foodのみ
      expect(buckets[1].expense, 2000);
    });

    test('空フィルタは全カテゴリ', () {
      final transactions = [
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 1000,
          categoryId: 'food',
        ),
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 5000,
          categoryId: 'rent',
        ),
      ];

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.daily,
        categoryIds: {},
      );

      expect(buckets.length, 1);
      expect(buckets[0].expense, 6000); // 全カテゴリ合計
    });

    test('複数カテゴリ選択', () {
      final transactions = [
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 1000,
          categoryId: 'food',
        ),
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 5000,
          categoryId: 'rent',
        ),
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 3000,
          categoryId: 'transport',
        ),
      ];

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.daily,
        categoryIds: {'food', 'transport'},
      );

      expect(buckets.length, 1);
      expect(buckets[0].expense, 4000); // food + transport
    });
  });

  group('AnalyticsAggregator.totals', () {
    test('合計が正しく計算される', () {
      final transactions = [
        _tx(date: DateTime(2026, 2, 1), type: 'expense', amount: 1000),
        _tx(date: DateTime(2026, 2, 2), type: 'expense', amount: 2000),
        _tx(date: DateTime(2026, 2, 3), type: 'income', amount: 50000),
      ];

      final totals = AnalyticsAggregator.totals(transactions: transactions);

      expect(totals.totalExpense, 3000);
      expect(totals.totalIncome, 50000);
      expect(totals.net, 47000);
    });

    test('カテゴリフィルタ適用時の合計', () {
      final transactions = [
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 1000,
          categoryId: 'food',
        ),
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 5000,
          categoryId: 'rent',
        ),
      ];

      final totals = AnalyticsAggregator.totals(
        transactions: transactions,
        categoryIds: {'food'},
      );

      expect(totals.totalExpense, 1000);
      expect(totals.totalIncome, 0);
      expect(totals.net, -1000);
    });

    test('空リストの合計はゼロ', () {
      final totals = AnalyticsAggregator.totals(transactions: []);
      expect(totals.totalExpense, 0);
      expect(totals.totalIncome, 0);
      expect(totals.net, 0);
    });
  });

  group('AnalyticsBucket モデル', () {
    test('netは収入-支出', () {
      const bucket = AnalyticsBucket(
        label: '2/1',
        sortKey: '2026-02-01',
        expense: 3000,
        income: 5000,
      );

      expect(bucket.net, 2000);
    });

    test('支出のみの場合netはマイナス', () {
      const bucket = AnalyticsBucket(
        label: '2/1',
        sortKey: '2026-02-01',
        expense: 3000,
        income: 0,
      );

      expect(bucket.net, -3000);
    });
  });

  group('AnalyticsAggregator: バケットソート順', () {
    test('日別バケットは日付昇順', () {
      final transactions = [
        _tx(date: DateTime(2026, 2, 15), type: 'expense', amount: 500),
        _tx(date: DateTime(2026, 2, 3), type: 'expense', amount: 1000),
        _tx(date: DateTime(2026, 2, 28), type: 'expense', amount: 200),
      ];

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.daily,
      );

      expect(buckets[0].sortKey, '2026-02-03');
      expect(buckets[1].sortKey, '2026-02-15');
      expect(buckets[2].sortKey, '2026-02-28');
    });

    test('月別バケットは月昇順', () {
      final transactions = [
        _tx(date: DateTime(2026, 12, 1), type: 'expense', amount: 500),
        _tx(date: DateTime(2026, 1, 1), type: 'expense', amount: 1000),
        _tx(date: DateTime(2026, 6, 1), type: 'expense', amount: 200),
      ];

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.monthly,
      );

      expect(buckets[0].sortKey, '2026-01');
      expect(buckets[1].sortKey, '2026-06');
      expect(buckets[2].sortKey, '2026-12');
    });
  });

  group('AnalyticsAggregator: 年別ナビゲーション回帰', () {
    test('5年分のデータから該当レンジのみ集計される', () {
      // 2020〜2028のデータを用意し、2024基準（2020〜2024）で集計
      final transactions = [
        _tx(date: DateTime(2020, 6, 1), type: 'expense', amount: 1000),
        _tx(date: DateTime(2022, 6, 1), type: 'expense', amount: 2000),
        _tx(date: DateTime(2024, 6, 1), type: 'expense', amount: 3000),
        _tx(date: DateTime(2026, 6, 1), type: 'expense', amount: 4000),
        _tx(date: DateTime(2028, 6, 1), type: 'expense', amount: 5000),
      ];

      // 2024基準（2020〜2024のみ含まれる想定）
      final filtered = transactions
          .where(
            (tx) =>
                tx.date.year >= 2020 && tx.date.year <= 2024,
          )
          .toList();

      final buckets = AnalyticsAggregator.aggregate(
        transactions: filtered,
        period: AnalyticsPeriod.yearly,
      );

      // 2020, 2022, 2024の3バケット（2026, 2028は範囲外）
      expect(buckets.length, 3);
      expect(buckets[0].label, '2020年');
      expect(buckets[1].label, '2022年');
      expect(buckets[2].label, '2024年');
    });

    test('年別ナビゲーション前後移動でレンジが変わる', () {
      // 同じデータセットに対して異なるレンジでフィルタ
      final transactions = [
        _tx(date: DateTime(2018, 1, 1), type: 'expense', amount: 100),
        _tx(date: DateTime(2020, 1, 1), type: 'expense', amount: 200),
        _tx(date: DateTime(2024, 1, 1), type: 'expense', amount: 300),
        _tx(date: DateTime(2026, 1, 1), type: 'expense', amount: 400),
      ];

      // _year=2026相当: 2022〜2026
      final range2026 = transactions
          .where((tx) => tx.date.year >= 2022 && tx.date.year <= 2026)
          .toList();
      final buckets2026 = AnalyticsAggregator.aggregate(
        transactions: range2026,
        period: AnalyticsPeriod.yearly,
      );

      // _year=2021相当（前へ5年移動）: 2017〜2021
      final range2021 = transactions
          .where((tx) => tx.date.year >= 2017 && tx.date.year <= 2021)
          .toList();
      final buckets2021 = AnalyticsAggregator.aggregate(
        transactions: range2021,
        period: AnalyticsPeriod.yearly,
      );

      // 2026基準: 2024, 2026
      expect(buckets2026.length, 2);
      expect(buckets2026[0].label, '2024年');
      expect(buckets2026[1].label, '2026年');

      // 2021基準: 2018, 2020
      expect(buckets2021.length, 2);
      expect(buckets2021[0].label, '2018年');
      expect(buckets2021[1].label, '2020年');
    });
  });

  group('AnalyticsAggregator: グラフと合計の整合性', () {
    test('バケット合算と totals の値が一致する', () {
      final transactions = [
        _tx(date: DateTime(2026, 2, 1), type: 'expense', amount: 1000),
        _tx(date: DateTime(2026, 2, 5), type: 'expense', amount: 2000),
        _tx(date: DateTime(2026, 2, 10), type: 'income', amount: 50000),
        _tx(date: DateTime(2026, 2, 15), type: 'expense', amount: 3000),
      ];

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.daily,
      );
      final totals = AnalyticsAggregator.totals(transactions: transactions);

      final bucketExpense =
          buckets.fold<int>(0, (sum, b) => sum + b.expense);
      final bucketIncome =
          buckets.fold<int>(0, (sum, b) => sum + b.income);

      expect(bucketExpense, totals.totalExpense);
      expect(bucketIncome, totals.totalIncome);
    });

    test('カテゴリフィルタ適用時もグラフと合計が一致する', () {
      final transactions = [
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 1000,
          categoryId: 'food',
        ),
        _tx(
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 5000,
          categoryId: 'rent',
        ),
      ];

      final filter = {'food'};

      final buckets = AnalyticsAggregator.aggregate(
        transactions: transactions,
        period: AnalyticsPeriod.daily,
        categoryIds: filter,
      );
      final totals = AnalyticsAggregator.totals(
        transactions: transactions,
        categoryIds: filter,
      );

      final bucketExpense =
          buckets.fold<int>(0, (sum, b) => sum + b.expense);

      expect(bucketExpense, totals.totalExpense);
      expect(bucketExpense, 1000);
    });
  });
}
