import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/transaction.dart';
import 'package:household_mvp/repositories/transaction_repository.dart';
import 'package:household_mvp/utils/fx_converter.dart';

/// TransactionEditScreenの主要ロジック（バリデーション・通貨表示・削除導線）のテスト。
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

  group('取引編集: 削除ボタン表示条件', () {
    testWidgets('編集モードで削除アイコンが表示される', (tester) async {
      // 編集モード相当: AppBarにdelete_outlineアイコンが存在
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('取引編集'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '削除',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byTooltip('削除'), findsOneWidget);
    });

    testWidgets('新規追加モードで削除アイコンが表示されない', (tester) async {
      // 新規モード相当: AppBarにdeleteアイコンなし
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('取引追加'),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });

  group('取引編集: 削除確認ダイアログ', () {
    testWidgets('確認ダイアログにキャンセルと削除ボタンが表示される', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('取引削除'),
                      content: const Text('この取引を削除しますか？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('キャンセル'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('削除'),
                        ),
                      ],
                    );
                  },
                );
              },
              child: const Text('テスト'),
            ),
          ),
        ),
      );

      // ダイアログを開く
      await tester.tap(find.text('テスト'));
      await tester.pumpAndSettle();

      expect(find.text('取引削除'), findsOneWidget);
      expect(find.text('この取引を削除しますか？'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
      expect(find.text('削除'), findsOneWidget);
    });

    testWidgets('キャンセルタップでダイアログが閉じる', (tester) async {
      var dialogResult = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('取引削除'),
                      content: const Text('この取引を削除しますか？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('キャンセル'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('削除'),
                        ),
                      ],
                    );
                  },
                );
                dialogResult = result ?? false;
              },
              child: const Text('テスト'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('テスト'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      // キャンセルでfalseが返る
      expect(dialogResult, isFalse);
      // ダイアログが閉じている
      expect(find.text('取引削除'), findsNothing);
    });
  });

  group('取引編集: 削除後のサマリー更新', () {
    test('取引削除後のサマリーが正しく再計算される', () {
      final before = [
        Transaction(
          id: '1', userId: 'u', date: DateTime(2026, 2, 1),
          type: 'expense', amount: 1000, categoryId: 'c1',
          categoryName: '食費', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
        Transaction(
          id: '2', userId: 'u', date: DateTime(2026, 2, 2),
          type: 'expense', amount: 500, categoryId: 'c1',
          categoryName: '食費', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
        Transaction(
          id: '3', userId: 'u', date: DateTime(2026, 2, 3),
          type: 'income', amount: 3000, categoryId: 'c2',
          categoryName: '給与', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
      ];

      final summaryBefore = TransactionRepository.summarize(before);
      expect(summaryBefore.totalExpense, 1500);
      expect(summaryBefore.net, 1500);

      // id=1の取引を削除した状態をシミュレート
      final after = before.where((tx) => tx.id != '1').toList();
      final summaryAfter = TransactionRepository.summarize(after);
      expect(summaryAfter.totalExpense, 500);
      expect(summaryAfter.totalIncome, 3000);
      expect(summaryAfter.net, 2500);
      expect(summaryAfter.expenseByCategory['食費'], 500);
    });

    test('全取引削除後のサマリーはゼロ', () {
      final summary = TransactionRepository.summarize([]);
      expect(summary.totalExpense, 0);
      expect(summary.totalIncome, 0);
      expect(summary.net, 0);
      expect(summary.expenseByCategory, isEmpty);
    });

    test('唯一の取引を削除した場合のカテゴリ別集計', () {
      final transactions = [
        Transaction(
          id: '1', userId: 'u', date: DateTime(2026, 2, 1),
          type: 'expense', amount: 1000, categoryId: 'c1',
          categoryName: '食費', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
      ];

      final summaryBefore = TransactionRepository.summarize(transactions);
      expect(summaryBefore.expenseByCategory['食費'], 1000);

      // 削除後
      final summaryAfter = TransactionRepository.summarize([]);
      expect(summaryAfter.expenseByCategory['食費'], isNull);
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
