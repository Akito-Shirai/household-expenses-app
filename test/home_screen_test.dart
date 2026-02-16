import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/transaction.dart';
import 'package:household_mvp/repositories/transaction_repository.dart';
import 'package:household_mvp/models/user_settings.dart';
import 'package:household_mvp/utils/fx_converter.dart';

/// HomeScreenの主要ロジック（サマリー計算・表示フォーマット）のユニットテスト。
/// Supabase依存のため画面全体のWidgetテストは不可。
/// ロジック部分を独立してテストし、主要導線の回帰を検知する。
void main() {
  group('ホーム画面: サマリー計算ロジック', () {
    test('取引0件のサマリーは全項目ゼロ', () {
      final summary = TransactionRepository.summarize([]);
      expect(summary.totalIncome, 0);
      expect(summary.totalExpense, 0);
      expect(summary.net, 0);
      expect(summary.expenseByCategory, isEmpty);
      expect(summary.incomeByCategory, isEmpty);
    });

    test('支出と収入の混在サマリーが正しく計算される', () {
      final transactions = [
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

      final summary = TransactionRepository.summarize(transactions);
      expect(summary.totalExpense, 1500);
      expect(summary.totalIncome, 3000);
      expect(summary.net, 1500);
      expect(summary.expenseByCategory['食費'], 1500);
      expect(summary.incomeByCategory['給与'], 3000);
    });

    test('netが負の場合（支出超過）', () {
      final transactions = [
        Transaction(
          id: '1', userId: 'u', date: DateTime(2026, 2, 1),
          type: 'expense', amount: 5000, categoryId: 'c1',
          categoryName: '家賃', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
        Transaction(
          id: '2', userId: 'u', date: DateTime(2026, 2, 2),
          type: 'income', amount: 2000, categoryId: 'c2',
          categoryName: '給与', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
      ];

      final summary = TransactionRepository.summarize(transactions);
      expect(summary.net, -3000);
    });
  });

  group('ホーム画面: 金額フォーマット表示', () {
    test('JPY設定での金額フォーマット', () {
      final settings = UserSettings.defaults('test');
      final formatted = MoneyFormatter.format(1500, settings);
      expect(formatted, contains('1,500'));
      expect(formatted, contains('¥'));
    });

    test('USD設定でレートありの金額フォーマット', () {
      final settings = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'manual',
        manualRate: 150.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final formatted = MoneyFormatter.format(15000, settings);
      // 15000 / 150 = 100.00 USD
      expect(formatted, contains('100.00'));
      expect(formatted, contains('\$'));
    });

    test('符号付きフォーマット（収支表示）', () {
      final settings = UserSettings.defaults('test');
      // 正の値は符号なし（そのまま）
      final positive = MoneyFormatter.formatSigned(3000, settings);
      expect(positive, contains('3,000'));
      expect(positive, isNot(startsWith('-')));

      // 負の値はマイナス付き
      final negative = MoneyFormatter.formatSigned(-1500, settings);
      expect(negative, startsWith('-'));
      expect(negative, contains('1,500'));

      final zero = MoneyFormatter.formatSigned(0, settings);
      expect(zero, contains('0'));
    });

    test('取引リスト表示（支出: マイナス、収入: プラス）', () {
      final settings = UserSettings.defaults('test');
      final expense = MoneyFormatter.formatWithSign(1000, settings, isExpense: true);
      expect(expense, startsWith('-'));

      final income = MoneyFormatter.formatWithSign(1000, settings, isExpense: false);
      expect(income, startsWith('+'));
    });
  });

  group('ホーム画面: 通貨フォールバック', () {
    test('レート未設定時はJPYフォールバック', () {
      final settings = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'manual',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      // effectiveRateがnullのためJPYフォールバック
      expect(settings.effectiveRate, isNull);
      final formatted = MoneyFormatter.format(1000, settings);
      expect(formatted, contains('¥'));
    });

    test('デフォルト設定（JPY）ではeffectiveRateはnull', () {
      final settings = UserSettings.defaults('test');
      expect(settings.effectiveRate, isNull);
      expect(settings.displayCurrency, 'JPY');
    });
  });
}
