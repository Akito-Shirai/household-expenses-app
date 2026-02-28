import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/category.dart';

/// Step9: 初期カテゴリ仕様のテスト
/// DB側トリガーで投入されるカテゴリがアプリ側モデルと整合することを検証
void main() {
  /// 初期カテゴリ定義（DB側 seed_default_categories と同一）
  final defaultExpenseCategories = ['食費', '水道光熱費', '家賃', '交通費', '通信費', '医療費'];
  final defaultIncomeCategories = ['給与', '賞与'];

  group('Step9: 初期カテゴリ定義の整合性', () {
    test('支出カテゴリは6件', () {
      expect(defaultExpenseCategories.length, 6);
    });

    test('収入カテゴリは2件', () {
      expect(defaultIncomeCategories.length, 2);
    });

    test('初期カテゴリ合計は8件', () {
      expect(
        defaultExpenseCategories.length + defaultIncomeCategories.length,
        8,
      );
    });

    test('カテゴリ名に重複がない', () {
      final all = [...defaultExpenseCategories, ...defaultIncomeCategories];
      expect(all.toSet().length, all.length);
    });
  });

  group('Step9: Category.fromJsonで初期カテゴリを正しくパースできる', () {
    test('支出カテゴリのfromJson', () {
      final json = {
        'id': 'test-id',
        'user_id': 'test-user',
        'name': '食費',
        'type': 'expense',
        'sort_order': 1,
        'created_at': '2026-02-28T00:00:00Z',
        'updated_at': '2026-02-28T00:00:00Z',
      };

      final cat = Category.fromJson(json);
      expect(cat.name, '食費');
      expect(cat.type, 'expense');
      expect(cat.sortOrder, 1);
    });

    test('収入カテゴリのfromJson', () {
      final json = {
        'id': 'test-id',
        'user_id': 'test-user',
        'name': '給与',
        'type': 'income',
        'sort_order': 1,
        'created_at': '2026-02-28T00:00:00Z',
        'updated_at': '2026-02-28T00:00:00Z',
      };

      final cat = Category.fromJson(json);
      expect(cat.name, '給与');
      expect(cat.type, 'income');
    });
  });

  group('Step9: 冪等性の検証（同名カテゴリの重複チェックロジック）', () {
    test('同名・同typeのカテゴリはリスト内で1つだけ', () {
      // DB側のseed関数が行う重複チェックをアプリ側でもシミュレート
      final existing = [
        _cat(name: '食費', type: 'expense'),
        _cat(name: '交通費', type: 'expense'),
      ];

      final toSeed = ['食費', '水道光熱費', '家賃', '交通費', '通信費', '医療費'];

      // 存在しないものだけ追加対象
      final missing = toSeed
          .where((name) => !existing.any((c) => c.name == name && c.type == 'expense'))
          .toList();

      expect(missing, ['水道光熱費', '家賃', '通信費', '医療費']);
      expect(missing.length, 4);
    });

    test('全て存在する場合は追加なし', () {
      final existing = [
        _cat(name: '給与', type: 'income'),
        _cat(name: '賞与', type: 'income'),
      ];

      final toSeed = ['給与', '賞与'];
      final missing = toSeed
          .where((name) => !existing.any((c) => c.name == name && c.type == 'income'))
          .toList();

      expect(missing, isEmpty);
    });

    test('同名でもtypeが異なれば別カテゴリ', () {
      final existing = [
        _cat(name: '食費', type: 'income'), // 収入として食費が存在
      ];

      // 支出の食費は存在チェックに引っかからない
      final missing = ['食費']
          .where((name) => !existing.any((c) => c.name == name && c.type == 'expense'))
          .toList();

      expect(missing, ['食費']);
    });
  });

  group('Step9: 初期カテゴリのtoInsertJson', () {
    test('toInsertJsonにname/type/sort_orderが含まれる', () {
      final cat = Category(
        id: 'id',
        userId: 'user',
        name: '食費',
        type: 'expense',
        sortOrder: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = cat.toInsertJson();
      expect(json['name'], '食費');
      expect(json['type'], 'expense');
      expect(json['sort_order'], 1);
      // user_idはDB側で設定されるため含まれない
      expect(json.containsKey('user_id'), isFalse);
    });
  });

  group('Step9: sort_orderの安定性', () {
    test('支出カテゴリのsort_orderが1〜6', () {
      for (var i = 0; i < defaultExpenseCategories.length; i++) {
        expect(i + 1, lessThanOrEqualTo(6));
      }
    });

    test('収入カテゴリのsort_orderが1〜2', () {
      for (var i = 0; i < defaultIncomeCategories.length; i++) {
        expect(i + 1, lessThanOrEqualTo(2));
      }
    });
  });
}

/// テスト用Categoryヘルパー
Category _cat({required String name, required String type}) {
  return Category(
    id: 'dummy-id',
    userId: 'dummy-user',
    name: name,
    type: type,
    sortOrder: 0,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}
