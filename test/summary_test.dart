import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/transaction.dart';
import 'package:household_mvp/repositories/transaction_repository.dart';

/// テスト用Transactionヘルパー
Transaction _tx({
  required String type,
  required int amount,
  String categoryName = 'テスト',
}) {
  return Transaction(
    id: 'dummy-id',
    userId: 'dummy-user',
    categoryId: 'dummy-cat',
    date: DateTime(2026, 2, 1),
    amount: amount,
    type: type,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    categoryName: categoryName,
  );
}

void main() {
  group('TransactionRepository.summarize', () {
    test('空リストの場合すべてゼロ', () {
      final summary = TransactionRepository.summarize([]);
      expect(summary.totalExpense, 0);
      expect(summary.totalIncome, 0);
      expect(summary.net, 0);
      expect(summary.expenseByCategory, isEmpty);
      expect(summary.incomeByCategory, isEmpty);
    });

    test('支出のみの集計', () {
      final transactions = [
        _tx(type: 'expense', amount: 1000, categoryName: '食費'),
        _tx(type: 'expense', amount: 2000, categoryName: '交通費'),
        _tx(type: 'expense', amount: 500, categoryName: '食費'),
      ];

      final summary = TransactionRepository.summarize(transactions);

      expect(summary.totalExpense, 3500);
      expect(summary.totalIncome, 0);
      expect(summary.net, -3500);
      expect(summary.expenseByCategory, {'食費': 1500, '交通費': 2000});
      expect(summary.incomeByCategory, isEmpty);
    });

    test('収入のみの集計', () {
      final transactions = [
        _tx(type: 'income', amount: 300000, categoryName: '給与'),
        _tx(type: 'income', amount: 5000, categoryName: '副業'),
      ];

      final summary = TransactionRepository.summarize(transactions);

      expect(summary.totalExpense, 0);
      expect(summary.totalIncome, 305000);
      expect(summary.net, 305000);
      expect(summary.incomeByCategory, {'給与': 300000, '副業': 5000});
    });

    test('支出と収入の混在', () {
      final transactions = [
        _tx(type: 'income', amount: 300000, categoryName: '給与'),
        _tx(type: 'expense', amount: 50000, categoryName: '家賃'),
        _tx(type: 'expense', amount: 30000, categoryName: '食費'),
        _tx(type: 'income', amount: 10000, categoryName: '副業'),
      ];

      final summary = TransactionRepository.summarize(transactions);

      expect(summary.totalExpense, 80000);
      expect(summary.totalIncome, 310000);
      expect(summary.net, 230000);
      expect(summary.expenseByCategory, {'家賃': 50000, '食費': 30000});
      expect(summary.incomeByCategory, {'給与': 300000, '副業': 10000});
    });

    test('categoryNameがnullの場合「不明」に集約', () {
      final tx = Transaction(
        id: 'id',
        userId: 'user',
        categoryId: 'cat',
        date: DateTime(2026, 2, 1),
        amount: 1000,
        type: 'expense',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        categoryName: null,
      );

      final summary = TransactionRepository.summarize([tx]);

      expect(summary.expenseByCategory, {'不明': 1000});
    });
  });

  group('Step8: 単価・個数を持つ取引のサマリー', () {
    test('amountベースで集計される（unit_price/quantityはサマリーに影響しない）', () {
      // サマリーはamountのみ参照する仕様
      final transactions = [
        Transaction(
          id: '1',
          userId: 'u',
          categoryId: 'c1',
          date: DateTime(2026, 2, 1),
          amount: 600, // 200 * 3
          unitPrice: 200,
          quantity: 3,
          type: 'expense',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          categoryName: '食費',
        ),
        Transaction(
          id: '2',
          userId: 'u',
          categoryId: 'c2',
          date: DateTime(2026, 2, 2),
          amount: 50000,
          type: 'income',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          categoryName: '給与',
        ),
      ];

      final summary = TransactionRepository.summarize(transactions);

      expect(summary.totalExpense, 600);
      expect(summary.totalIncome, 50000);
      expect(summary.net, 49400);
      expect(summary.expenseByCategory['食費'], 600);
    });

    test('quantityデフォルト1で従来動作と同等', () {
      final tx = Transaction(
        id: '1',
        userId: 'u',
        categoryId: 'c1',
        date: DateTime(2026, 2, 1),
        amount: 500,
        unitPrice: 500,
        quantity: 1,
        type: 'expense',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        categoryName: '雑費',
      );

      final summary = TransactionRepository.summarize([tx]);
      expect(summary.totalExpense, 500);
      expect(summary.expenseByCategory['雑費'], 500);
    });
  });

  group('Step8: TransactionモデルのfromJson', () {
    test('unit_priceとquantityを正しくパースする', () {
      final json = {
        'id': 'test-id',
        'user_id': 'test-user',
        'category_id': 'test-cat',
        'date': '2026-02-01',
        'amount': 600,
        'unit_price': 200,
        'quantity': 3,
        'memo': null,
        'type': 'expense',
        'created_at': '2026-02-01T00:00:00Z',
        'updated_at': '2026-02-01T00:00:00Z',
        'categories': {'name': '食費'},
      };

      final tx = Transaction.fromJson(json);
      expect(tx.unitPrice, 200);
      expect(tx.quantity, 3);
      expect(tx.amount, 600);
    });

    test('unit_priceがnullの場合（収入など）', () {
      final json = {
        'id': 'test-id',
        'user_id': 'test-user',
        'category_id': 'test-cat',
        'date': '2026-02-01',
        'amount': 50000,
        'unit_price': null,
        'quantity': 1,
        'memo': null,
        'type': 'income',
        'created_at': '2026-02-01T00:00:00Z',
        'updated_at': '2026-02-01T00:00:00Z',
        'categories': {'name': '給与'},
      };

      final tx = Transaction.fromJson(json);
      expect(tx.unitPrice, isNull);
      expect(tx.quantity, 1);
      expect(tx.amount, 50000);
    });

    test('quantityが未定義の場合デフォルト1', () {
      final json = {
        'id': 'test-id',
        'user_id': 'test-user',
        'category_id': 'test-cat',
        'date': '2026-02-01',
        'amount': 1000,
        'type': 'expense',
        'created_at': '2026-02-01T00:00:00Z',
        'updated_at': '2026-02-01T00:00:00Z',
      };

      final tx = Transaction.fromJson(json);
      expect(tx.quantity, 1);
      expect(tx.unitPrice, isNull);
    });
  });

  group('Step8: toInsertJson / toUpdateJsonにunit_price/quantity含む', () {
    test('支出のtoInsertJsonにunit_priceとquantityが含まれる', () {
      final tx = Transaction(
        id: 'id',
        userId: 'user',
        categoryId: 'cat',
        date: DateTime(2026, 2, 1),
        amount: 600,
        unitPrice: 200,
        quantity: 3,
        type: 'expense',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = tx.toInsertJson();
      expect(json['unit_price'], 200);
      expect(json['quantity'], 3);
      expect(json['amount'], 600);
    });

    test('収入のtoInsertJsonでunit_priceがnull', () {
      final tx = Transaction(
        id: 'id',
        userId: 'user',
        categoryId: 'cat',
        date: DateTime(2026, 2, 1),
        amount: 50000,
        type: 'income',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = tx.toInsertJson();
      expect(json['unit_price'], isNull);
      expect(json['quantity'], 1);
    });

    test('toUpdateJsonにunit_priceとquantityが含まれる', () {
      final tx = Transaction(
        id: 'id',
        userId: 'user',
        categoryId: 'cat',
        date: DateTime(2026, 2, 1),
        amount: 1000,
        unitPrice: 500,
        quantity: 2,
        type: 'expense',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = tx.toUpdateJson();
      expect(json['unit_price'], 500);
      expect(json['quantity'], 2);
      expect(json['amount'], 1000);
    });
  });

  group('月境界テスト', () {
    test('listByMonthの日付フィルタ範囲が正しい', () {
      // listByMonthで使われるのと同じロジックで境界を検証
      const year = 2026;
      const month = 2;
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 1);

      final start = startDate.toIso8601String().substring(0, 10);
      final end = endDate.toIso8601String().substring(0, 10);

      // 2月の範囲: 2026-02-01 <= date < 2026-03-01
      expect(start, '2026-02-01');
      expect(end, '2026-03-01');

      // 2/28は範囲内（2/28 >= 2/1 && 2/28 < 3/1）
      final feb28 = DateTime(2026, 2, 28);
      expect(!feb28.isBefore(startDate) && feb28.isBefore(endDate), isTrue);

      // 3/1は範囲外（3/1 < 3/1 は false）
      final mar1 = DateTime(2026, 3, 1);
      expect(!mar1.isBefore(startDate) && mar1.isBefore(endDate), isFalse);
    });

    test('12月→1月の年跨ぎ境界', () {
      final startDate = DateTime(2025, 12, 1);
      final endDate = DateTime(2025, 13, 1); // DartのDateTimeは自動繰り上げ

      final start = startDate.toIso8601String().substring(0, 10);
      final end = endDate.toIso8601String().substring(0, 10);

      expect(start, '2025-12-01');
      expect(end, '2026-01-01');
    });
  });
}
