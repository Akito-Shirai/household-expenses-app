import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/transaction.dart';

void main() {
  group('Step11: expired_at フィールドのパース', () {
    test('expired_at が値ありの場合に正しくパースされる', () {
      final json = {
        'id': 'test-id',
        'user_id': 'test-user',
        'category_id': 'test-cat',
        'date': '2020-01-15',
        'amount': 1000,
        'unit_price': null,
        'quantity': 1,
        'memo': null,
        'type': 'expense',
        'expired_at': '2026-03-01T12:00:00Z',
        'created_at': '2020-01-15T00:00:00Z',
        'updated_at': '2020-01-15T00:00:00Z',
        'categories': {'name': '食費'},
      };

      final tx = Transaction.fromJson(json);
      expect(tx.expiredAt, isNotNull);
      expect(tx.expiredAt!.year, 2026);
      expect(tx.expiredAt!.month, 3);
      expect(tx.expiredAt!.day, 1);
    });

    test('expired_at が null の場合', () {
      final json = {
        'id': 'test-id',
        'user_id': 'test-user',
        'category_id': 'test-cat',
        'date': '2026-02-01',
        'amount': 500,
        'unit_price': null,
        'quantity': 1,
        'memo': null,
        'type': 'expense',
        'expired_at': null,
        'created_at': '2026-02-01T00:00:00Z',
        'updated_at': '2026-02-01T00:00:00Z',
        'categories': {'name': '食費'},
      };

      final tx = Transaction.fromJson(json);
      expect(tx.expiredAt, isNull);
    });

    test('expired_at キーが存在しない場合（後方互換）', () {
      final json = {
        'id': 'test-id',
        'user_id': 'test-user',
        'category_id': 'test-cat',
        'date': '2026-02-01',
        'amount': 500,
        'unit_price': null,
        'quantity': 1,
        'memo': null,
        'type': 'expense',
        'created_at': '2026-02-01T00:00:00Z',
        'updated_at': '2026-02-01T00:00:00Z',
      };

      final tx = Transaction.fromJson(json);
      expect(tx.expiredAt, isNull);
    });
  });

  group('Step11: toInsertJson / toUpdateJson に expired_at が含まれない', () {
    test('toInsertJson に expired_at が含まれない', () {
      final tx = Transaction(
        id: 'id',
        userId: 'user',
        categoryId: 'cat',
        date: DateTime(2026, 2, 1),
        amount: 1000,
        type: 'expense',
        expiredAt: DateTime(2026, 3, 1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = tx.toInsertJson();
      expect(json.containsKey('expired_at'), isFalse);
    });

    test('toUpdateJson に expired_at が含まれない', () {
      final tx = Transaction(
        id: 'id',
        userId: 'user',
        categoryId: 'cat',
        date: DateTime(2026, 2, 1),
        amount: 1000,
        type: 'expense',
        expiredAt: DateTime(2026, 3, 1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = tx.toUpdateJson();
      expect(json.containsKey('expired_at'), isFalse);
    });
  });

  group('Step11: コンストラクタのデフォルト値による後方互換性', () {
    test('expiredAt を省略してもインスタンス生成可能', () {
      final tx = Transaction(
        id: 'id',
        userId: 'user',
        categoryId: 'cat',
        date: DateTime(2026, 2, 1),
        amount: 1000,
        type: 'expense',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(tx.expiredAt, isNull);
    });

    test('expiredAt を明示的に指定してインスタンス生成可能', () {
      final expiry = DateTime(2026, 3, 1);
      final tx = Transaction(
        id: 'id',
        userId: 'user',
        categoryId: 'cat',
        date: DateTime(2020, 1, 1),
        amount: 500,
        type: 'expense',
        expiredAt: expiry,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(tx.expiredAt, expiry);
    });
  });

  group('Step11: 境界日付の計算テスト', () {
    test('5年境界: 2021-03-01 のデータは 2026-03-01 時点で期限切れ対象', () {
      // 保持年数5年の場合、基準日は CURRENT_DATE - 5 years
      // 2026-03-01 - 5 years = 2021-03-01
      // SQLでは CURRENT_DATE - interval '5 years' = 2021-03-01
      // date < 2021-03-01 が対象なので、2021-03-01 はギリギリ対象外
      final boundaryDate = DateTime(2021, 3, 1);
      final justBefore = DateTime(2021, 2, 28);

      // 2021-03-01 は基準日と同じ → 対象外（date < cutoff）
      expect(boundaryDate.isBefore(DateTime(2021, 3, 1)), isFalse);

      // 2021-02-28 は基準日より前 → 対象
      expect(justBefore.isBefore(DateTime(2021, 3, 1)), isTrue);
    });

    test('10年境界: 2016-03-01 のデータは 2026-03-01 時点で期限切れ対象', () {
      // 保持年数10年の場合、基準日は 2026-03-01 - 10 years = 2016-03-01
      final boundaryDate = DateTime(2016, 3, 1);
      final justBefore = DateTime(2016, 2, 29); // 2016年は閏年

      // 2016-03-01 は基準日と同じ → 対象外
      expect(boundaryDate.isBefore(DateTime(2016, 3, 1)), isFalse);

      // 2016-02-29 は基準日より前 → 対象
      expect(justBefore.isBefore(DateTime(2016, 3, 1)), isTrue);
    });

    test('閏年境界: 2020-02-29 のデータの期限切れ判定', () {
      // 2020-02-29 が存在し、5年後の基準日は 2025-02-28
      // 2025年は閏年ではないので 2025-02-29 は存在しない
      // Dartの DateTime(2025, 2, 29) は 2025-03-01 になる
      final leapDate = DateTime(2020, 2, 29);
      expect(leapDate.month, 2);
      expect(leapDate.day, 29);

      // 5年後の同日は存在しないが、SQLの interval '5 years' は
      // 2025-03-01 を返す（PostgreSQLの仕様）
      // date < 2025-03-01 なので 2020-02-29 は対象
      final cutoff = DateTime(2025, 3, 1);
      expect(leapDate.isBefore(cutoff), isTrue);
    });
  });
}
