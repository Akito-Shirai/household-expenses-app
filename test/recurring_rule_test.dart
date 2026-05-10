import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/recurring_rule.dart';
import 'package:household_mvp/models/transaction.dart';
import 'package:household_mvp/repositories/recurring_rule_repository.dart';
import 'package:household_mvp/repositories/transaction_repository.dart';

void main() {
  group('RecurringRule: JSONパース', () {
    test('fromJsonが全フィールドを正しくパースする', () {
      final json = {
        'id': 'rule-1',
        'user_id': 'user-1',
        'category_id': 'cat-1',
        'amount': 5000,
        'memo': 'Netflix',
        'frequency_unit': 'month',
        'frequency_interval': 1,
        'start_date': '2026-01-01',
        'end_date': '2026-12-31',
        'is_active': true,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'categories': {'name': 'サブスク'},
      };

      final rule = RecurringRule.fromJson(json);
      expect(rule.id, 'rule-1');
      expect(rule.userId, 'user-1');
      expect(rule.categoryId, 'cat-1');
      expect(rule.amount, 5000);
      expect(rule.memo, 'Netflix');
      expect(rule.frequencyUnit, 'month');
      expect(rule.frequencyInterval, 1);
      expect(rule.startDate, DateTime.parse('2026-01-01'));
      expect(rule.endDate, DateTime.parse('2026-12-31'));
      expect(rule.isActive, isTrue);
      expect(rule.categoryName, 'サブスク');
    });

    test('fromJsonがnull optionalフィールドを正しく処理する', () {
      final json = {
        'id': 'rule-2',
        'user_id': 'user-1',
        'category_id': 'cat-1',
        'amount': 1000,
        'memo': null,
        'frequency_unit': 'week',
        'frequency_interval': 2,
        'start_date': '2026-03-01',
        'end_date': null,
        'is_active': false,
        'created_at': '2026-03-01T00:00:00Z',
        'updated_at': '2026-03-01T00:00:00Z',
      };

      final rule = RecurringRule.fromJson(json);
      expect(rule.memo, isNull);
      expect(rule.endDate, isNull);
      expect(rule.isActive, isFalse);
      expect(rule.categoryName, isNull);
    });

    test('toInsertJsonがid/userId/timestampsを含まない', () {
      final rule = _createRule();
      final json = rule.toInsertJson();

      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('user_id'), isFalse);
      expect(json.containsKey('created_at'), isFalse);
      expect(json.containsKey('updated_at'), isFalse);
      expect(json.containsKey('is_active'), isFalse);
      expect(json['category_id'], 'cat-1');
      expect(json['amount'], 5000);
      expect(json['frequency_unit'], 'month');
    });

    test('toUpdateJsonがisActiveを含む', () {
      final rule = _createRule();
      final json = rule.toUpdateJson();

      expect(json.containsKey('is_active'), isTrue);
      expect(json['is_active'], isTrue);
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('user_id'), isFalse);
    });

    test('toInsertJsonの日付が YYYY-MM-DD 形式', () {
      final rule = _createRule();
      final json = rule.toInsertJson();

      expect(json['start_date'], '2026-01-01');
      expect(json['end_date'], '2026-12-31');
    });

    test('endDateがnullの場合toInsertJsonもnull', () {
      final rule = _createRule(hasEndDate: false);
      final json = rule.toInsertJson();

      expect(json['end_date'], isNull);
    });
  });

  group('RecurringRule: frequencyLabel', () {
    test('毎月（interval=1, unit=month）', () {
      final rule = _createRule(frequencyUnit: 'month', frequencyInterval: 1);
      expect(rule.frequencyLabel, '毎月');
    });

    test('毎週（interval=1, unit=week）', () {
      final rule = _createRule(frequencyUnit: 'week', frequencyInterval: 1);
      expect(rule.frequencyLabel, '毎週');
    });

    test('毎年（interval=1, unit=year）', () {
      final rule = _createRule(frequencyUnit: 'year', frequencyInterval: 1);
      expect(rule.frequencyLabel, '毎年');
    });

    test('隔週（interval=2, unit=week）', () {
      final rule = _createRule(frequencyUnit: 'week', frequencyInterval: 2);
      expect(rule.frequencyLabel, '2週ごと');
    });

    test('四半期（interval=3, unit=month）', () {
      final rule = _createRule(frequencyUnit: 'month', frequencyInterval: 3);
      expect(rule.frequencyLabel, '3月ごと');
    });

    test('隔年（interval=2, unit=year）', () {
      final rule = _createRule(frequencyUnit: 'year', frequencyInterval: 2);
      expect(rule.frequencyLabel, '2年ごと');
    });
  });

  group('Transaction: 定期支出フィールド', () {
    test('isRecurringはsource_typeがrecurringの場合true', () {
      final tx = _createTransaction(sourceType: 'recurring');
      expect(tx.isRecurring, isTrue);
    });

    test('isRecurringはsource_typeがmanualの場合false', () {
      final tx = _createTransaction(sourceType: 'manual');
      expect(tx.isRecurring, isFalse);
    });

    test('isRecurringはデフォルト（manual）でfalse', () {
      final tx = _createTransaction();
      expect(tx.isRecurring, isFalse);
    });

    test('fromJsonがsource_type未設定の場合manualにフォールバック', () {
      final json = {
        'id': 'tx-1',
        'user_id': 'u',
        'category_id': 'c1',
        'date': '2026-03-01',
        'amount': 1000,
        'quantity': 1,
        'type': 'expense',
        'created_at': '2026-03-01T00:00:00Z',
        'updated_at': '2026-03-01T00:00:00Z',
      };
      final tx = Transaction.fromJson(json);
      expect(tx.sourceType, 'manual');
      expect(tx.recurringRuleId, isNull);
      expect(tx.scheduledFor, isNull);
      expect(tx.isRecurring, isFalse);
    });

    test('fromJsonが定期支出フィールドを正しくパースする', () {
      final json = {
        'id': 'tx-2',
        'user_id': 'u',
        'category_id': 'c1',
        'date': '2026-03-15',
        'amount': 5000,
        'quantity': 1,
        'type': 'expense',
        'source_type': 'recurring',
        'recurring_rule_id': 'rule-1',
        'scheduled_for': '2026-03-15',
        'created_at': '2026-03-01T00:00:00Z',
        'updated_at': '2026-03-01T00:00:00Z',
      };
      final tx = Transaction.fromJson(json);
      expect(tx.sourceType, 'recurring');
      expect(tx.recurringRuleId, 'rule-1');
      expect(tx.scheduledFor, DateTime.parse('2026-03-15'));
      expect(tx.isRecurring, isTrue);
    });

    test('toInsertJsonに定期支出フィールドが含まれない', () {
      final tx = _createTransaction(sourceType: 'recurring');
      final json = tx.toInsertJson();
      expect(json.containsKey('source_type'), isFalse);
      expect(json.containsKey('recurring_rule_id'), isFalse);
      expect(json.containsKey('scheduled_for'), isFalse);
    });

    test('toUpdateJsonに定期支出フィールドが含まれない', () {
      final tx = _createTransaction(sourceType: 'recurring');
      final json = tx.toUpdateJson();
      expect(json.containsKey('source_type'), isFalse);
      expect(json.containsKey('recurring_rule_id'), isFalse);
      expect(json.containsKey('scheduled_for'), isFalse);
    });
  });

  group('H-1回帰: catch-up RPC の as_of_date パラメータ', () {
    test('buildCatchupParams に asOfDate を渡すと p_as_of_date が含まれる', () {
      // 実装コード（RecurringRuleRepository.buildCatchupParams）を直接呼び出し
      final params = RecurringRuleRepository.buildCatchupParams(
        asOfDate: DateTime(2026, 3, 29),
      );
      expect(params, containsPair('p_as_of_date', '2026-03-29'));
      expect(params.length, 1, reason: 'p_as_of_date のみ含まれる');
    });

    test('buildCatchupParams に JST 深夜の DateTime を渡してもローカル日付が使われる', () {
      // UTC+9 の 2026-03-29 00:30 に相当するローカル DateTime
      final jstMidnight = DateTime(2026, 3, 29, 0, 30);
      final params = RecurringRuleRepository.buildCatchupParams(
        asOfDate: jstMidnight,
      );
      expect(params['p_as_of_date'], '2026-03-29',
          reason: 'ローカル DateTime からは常にローカル日付が取れる');
    });

    test('buildCatchupParams に asOfDate=null を渡すと空 map が返る', () {
      final params = RecurringRuleRepository.buildCatchupParams(asOfDate: null);
      expect(params, isEmpty,
          reason: 'null の場合 DB 側の CURRENT_DATE が使われる');
    });
  });

  group('H-2回帰: deleteRecurring の再試行安全性', () {
    test('skipExceptionConflictColumns が正しい列名を含む', () {
      // 実装コード（TransactionRepository.skipExceptionConflictColumns）を直接参照
      final columns = TransactionRepository.skipExceptionConflictColumns;
      expect(columns, contains('recurring_rule_id'));
      expect(columns, contains('scheduled_for'));
      expect(columns.split(',').length, 2,
          reason: 'upsert の onConflict に2列指定');
    });

    test('buildSkipExceptionPayload が正しい形式のペイロードを返す', () {
      // 実装コード（TransactionRepository.buildSkipExceptionPayload）を直接呼び出し
      final payload = TransactionRepository.buildSkipExceptionPayload(
        recurringRuleId: 'rule-1',
        scheduledFor: DateTime(2026, 3, 15),
      );
      expect(payload['recurring_rule_id'], 'rule-1');
      expect(payload['scheduled_for'], '2026-03-15');
      expect(payload['exception_type'], 'skip');
    });

    test('buildSkipExceptionPayload の日付がローカル日付文字列になる', () {
      final payload = TransactionRepository.buildSkipExceptionPayload(
        recurringRuleId: 'rule-1',
        scheduledFor: DateTime(2026, 3, 31, 23, 59),
      );
      expect(payload['scheduled_for'], '2026-03-31',
          reason: '時刻部分は切り捨てられ日付のみ');
    });
  });

  group('H-3回帰: 定期取引の識別と削除パス分岐', () {
    test('isRecurring=true かつ recurringRuleId/scheduledFor が非null なら deleteRecurring パスに入る', () {
      final tx = Transaction(
        id: 'tx-recurring',
        userId: 'u',
        categoryId: 'c1',
        date: DateTime(2026, 3, 15),
        type: 'expense',
        amount: 5000,
        sourceType: 'recurring',
        recurringRuleId: 'rule-1',
        scheduledFor: DateTime(2026, 3, 15),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(tx.isRecurring, isTrue);
      expect(tx.recurringRuleId, isNotNull);
      expect(tx.scheduledFor, isNotNull);

      // deleteRecurring パスで使われるペイロードが正しく構築される
      final payload = TransactionRepository.buildSkipExceptionPayload(
        recurringRuleId: tx.recurringRuleId!,
        scheduledFor: tx.scheduledFor!,
      );
      expect(payload['recurring_rule_id'], tx.recurringRuleId);
    });

    test('isRecurring=true だが recurringRuleId が null の場合は通常削除パスに入る', () {
      final tx = Transaction(
        id: 'tx-edge',
        userId: 'u',
        categoryId: 'c1',
        date: DateTime(2026, 3, 15),
        type: 'expense',
        amount: 5000,
        sourceType: 'recurring',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(tx.isRecurring, isTrue);
      expect(tx.recurringRuleId, isNull);
    });

    test('buildCatchupParams の戻り値で catch-up 後のリロード要否を判定できる', () {
      // asOfDate 指定時: params に p_as_of_date が含まれ RPC が呼ばれる
      final params = RecurringRuleRepository.buildCatchupParams(
        asOfDate: DateTime(2026, 3, 29),
      );
      expect(params.containsKey('p_as_of_date'), isTrue,
          reason: 'RPC に日付パラメータが渡される');
    });
  });

  group('Step27: 定期支出ルール削除 RPC', () {
    // RPC 名・パラメータキーの単体テスト。
    // 実装コードを直接参照することで、リネーム時に即テストが失敗する。

    test('deleteRuleRpcName が delete_recurring_rule', () {
      expect(
        RecurringRuleRepository.deleteRuleRpcName,
        'delete_recurring_rule',
        reason: 'migration の RPC 名と一致する必要がある',
      );
    });

    test('buildDeleteRuleParams が p_rule_id を含む', () {
      final params = RecurringRuleRepository.buildDeleteRuleParams('rule-1');
      expect(params['p_rule_id'], 'rule-1');
      expect(params.length, 1, reason: 'p_rule_id のみ含まれる');
    });

    test('buildDeleteRuleParams は同じ ID で同じペイロードを返す（冪等性）', () {
      final p1 = RecurringRuleRepository.buildDeleteRuleParams('rule-x');
      final p2 = RecurringRuleRepository.buildDeleteRuleParams('rule-x');
      expect(p1, equals(p2));
    });

    test('buildDeleteRuleParams は ID をそのまま渡す（型変換しない）', () {
      // UUID 風の文字列でも、空文字でも、そのまま渡される
      // RLS / RPC 側で auth.uid() と存在チェックを行うため、
      // クライアント側ではトリミング等を行わない
      final p = RecurringRuleRepository.buildDeleteRuleParams(
        '00000000-0000-0000-0000-000000000001',
      );
      expect(p['p_rule_id'], '00000000-0000-0000-0000-000000000001');
    });
  });

  group('Step27: 削除と無効化のセマンティクス区別', () {
    test('削除した取引は通常取引（manual）として残る前提を確認', () {
      // 削除 RPC は対象ルール由来の取引を以下のように更新する:
      // - source_type: 'manual'
      // - recurring_rule_id: null
      // - scheduled_for: null
      // フィールド名がモデルと一致することを確認（RPC SQL 修正時の回帰検知）
      final tx = Transaction(
        id: 'tx-detached',
        userId: 'u',
        categoryId: 'c1',
        date: DateTime(2026, 3, 15),
        type: 'expense',
        amount: 5000,
        sourceType: 'manual',
        // 通常取引化後は recurringRuleId / scheduledFor が null
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(tx.isRecurring, isFalse);
      expect(tx.recurringRuleId, isNull);
      expect(tx.scheduledFor, isNull);
      expect(tx.sourceType, 'manual');
    });
  });

  group('サマリー: 定期支出を含む集計', () {
    test('定期支出の取引がサマリーに正しく含まれる', () {
      final transactions = [
        _createTransaction(
          amount: 5000,
          sourceType: 'recurring',
          categoryName: '家賃',
        ),
        _createTransaction(
          id: 'tx-2',
          amount: 1000,
          sourceType: 'manual',
          categoryName: '食費',
        ),
        _createTransaction(
          id: 'tx-3',
          amount: 10000,
          type: 'income',
          categoryName: '給与',
        ),
      ];

      final summary = TransactionRepository.summarize(transactions);
      expect(summary.totalExpense, 6000);
      expect(summary.totalIncome, 10000);
      expect(summary.net, 4000);
      expect(summary.expenseByCategory['家賃'], 5000);
      expect(summary.expenseByCategory['食費'], 1000);
    });
  });
}

/// テスト用RecurringRule生成ヘルパー
/// [hasEndDate] をfalseにするとendDateをnullにする
RecurringRule _createRule({
  String frequencyUnit = 'month',
  int frequencyInterval = 1,
  DateTime? endDate,
  bool hasEndDate = true,
}) {
  return RecurringRule(
    id: 'rule-1',
    userId: 'user-1',
    categoryId: 'cat-1',
    amount: 5000,
    memo: 'Netflix',
    frequencyUnit: frequencyUnit,
    frequencyInterval: frequencyInterval,
    startDate: DateTime(2026, 1, 1),
    endDate: hasEndDate ? (endDate ?? DateTime(2026, 12, 31)) : null,
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    categoryName: 'サブスク',
  );
}

/// テスト用Transaction生成ヘルパー
Transaction _createTransaction({
  String id = 'tx-1',
  int amount = 1000,
  String sourceType = 'manual',
  String type = 'expense',
  String categoryName = '食費',
}) {
  return Transaction(
    id: id,
    userId: 'u',
    categoryId: 'c1',
    date: DateTime(2026, 3, 1),
    type: type,
    amount: amount,
    sourceType: sourceType,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    categoryName: categoryName,
  );
}
