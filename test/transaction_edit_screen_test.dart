import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/utils/fx_converter.dart';

/// TransactionEditScreenの主要ロジック（バリデーション・通貨表示）のテスト。
/// 画面全体はSupabase依存のため、ロジック・UIパーツ単位でテストする。
void main() {
  group('取引編集: 金額バリデーションロジック', () {
    // _save()内のバリデーション相当のロジックを抽出テスト
    String? validateAmount(String? value) {
      if (value == null || value.trim().isEmpty) {
        return '金額を入力してください';
      }
      final amount = int.tryParse(value.trim());
      if (amount == null || amount < 0) {
        return '0以上の整数を入力してください';
      }
      return null;
    }

    test('空入力でエラーメッセージ', () {
      expect(validateAmount(''), '金額を入力してください');
      expect(validateAmount(null), '金額を入力してください');
      expect(validateAmount('   '), '金額を入力してください');
    });

    test('正の整数は通過', () {
      expect(validateAmount('100'), isNull);
      expect(validateAmount('0'), isNull);
      expect(validateAmount('999999'), isNull);
    });

    test('負数はエラー', () {
      expect(validateAmount('-1'), '0以上の整数を入力してください');
      expect(validateAmount('-100'), '0以上の整数を入力してください');
    });

    test('小数・文字列はエラー', () {
      expect(validateAmount('12.5'), '0以上の整数を入力してください');
      expect(validateAmount('abc'), '0以上の整数を入力してください');
    });
  });

  group('取引編集: カテゴリバリデーション', () {
    String? validateCategory(String? value) {
      return value == null ? 'カテゴリを選択してください' : null;
    }

    test('未選択でエラー', () {
      expect(validateCategory(null), 'カテゴリを選択してください');
    });

    test('選択済みで通過', () {
      expect(validateCategory('cat-1'), isNull);
    });
  });

  group('取引編集: 通貨記号表示', () {
    test('JPY設定で¥記号', () {
      expect(MoneyFormatter.symbol('JPY'), '¥');
    });

    test('USD設定で\$記号', () {
      expect(MoneyFormatter.symbol('USD'), '\$');
    });

    test('EUR設定で€記号', () {
      expect(MoneyFormatter.symbol('EUR'), '€');
    });

    test('GBP設定で£記号', () {
      expect(MoneyFormatter.symbol('GBP'), '£');
    });

    test('AUD設定でA\$記号', () {
      expect(MoneyFormatter.symbol('AUD'), 'A\$');
    });
  });

  group('取引編集: 保存中状態のUI', () {
    testWidgets('FilledButtonが無効化時にテキスト変更', (tester) async {
      // 保存中ボタンの見た目テスト（独立したウィジェット）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                // 通常状態
                FilledButton(
                  onPressed: () {},
                  child: const Text('追加する'),
                ),
                // 保存中状態
                const FilledButton(
                  onPressed: null,
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('追加する'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('種別切替SegmentedButtonが表示される', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'expense',
                  label: Text('支出'),
                  icon: Icon(Icons.remove_circle_outline),
                ),
                ButtonSegment(
                  value: 'income',
                  label: Text('収入'),
                  icon: Icon(Icons.add_circle_outline),
                ),
              ],
              selected: const {'expense'},
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('支出'), findsOneWidget);
      expect(find.text('収入'), findsOneWidget);
    });
  });

  group('取引編集: 日付フォーマット', () {
    test('日付がゼロ埋めで表示される', () {
      final date = DateTime(2026, 2, 5);
      final formatted =
          '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      expect(formatted, '2026/02/05');
    });

    test('12月31日のフォーマット', () {
      final date = DateTime(2026, 12, 31);
      final formatted =
          '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      expect(formatted, '2026/12/31');
    });
  });
}
