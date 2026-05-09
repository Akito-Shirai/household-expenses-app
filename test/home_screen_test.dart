import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/transaction.dart';
import 'package:household_mvp/repositories/recurring_rule_repository.dart';
import 'package:household_mvp/repositories/transaction_repository.dart';
import 'package:household_mvp/models/user_settings.dart';
import 'package:household_mvp/utils/fx_converter.dart';
import 'package:household_mvp/utils/transaction_default_date.dart';

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
          id: '1',
          userId: 'u',
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 1000,
          categoryId: 'c1',
          categoryName: '食費',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Transaction(
          id: '2',
          userId: 'u',
          date: DateTime(2026, 2, 2),
          type: 'expense',
          amount: 500,
          categoryId: 'c1',
          categoryName: '食費',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Transaction(
          id: '3',
          userId: 'u',
          date: DateTime(2026, 2, 3),
          type: 'income',
          amount: 3000,
          categoryId: 'c2',
          categoryName: '給与',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
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
          id: '1',
          userId: 'u',
          date: DateTime(2026, 2, 1),
          type: 'expense',
          amount: 5000,
          categoryId: 'c1',
          categoryName: '家賃',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Transaction(
          id: '2',
          userId: 'u',
          date: DateTime(2026, 2, 2),
          type: 'income',
          amount: 2000,
          categoryId: 'c2',
          categoryName: '給与',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
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
      final expense = MoneyFormatter.formatWithSign(
        1000,
        settings,
        isExpense: true,
      );
      expect(expense, startsWith('-'));

      final income = MoneyFormatter.formatWithSign(
        1000,
        settings,
        isExpense: false,
      );
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

  group('ホーム画面: 定期支出キャッチアップ回帰', () {
    test('catch-up で生成された定期取引がサマリーに正しく反映される', () {
      // catch-up で生成される取引は source_type='recurring' だが
      // summarize() は source_type を区別しない → 正しく集計される
      final transactions = [
        Transaction(
          id: 'manual-1',
          userId: 'u',
          date: DateTime(2026, 3, 1),
          type: 'expense',
          amount: 1000,
          categoryId: 'c1',
          categoryName: '食費',
          sourceType: 'manual',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Transaction(
          id: 'recurring-1',
          userId: 'u',
          date: DateTime(2026, 3, 1),
          type: 'expense',
          amount: 5000,
          categoryId: 'c2',
          categoryName: '家賃',
          sourceType: 'recurring',
          recurringRuleId: 'rule-1',
          scheduledFor: DateTime(2026, 3, 1),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Transaction(
          id: 'recurring-2',
          userId: 'u',
          date: DateTime(2026, 3, 15),
          type: 'expense',
          amount: 1000,
          categoryId: 'c3',
          categoryName: 'サブスク',
          sourceType: 'recurring',
          recurringRuleId: 'rule-2',
          scheduledFor: DateTime(2026, 3, 15),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final summary = TransactionRepository.summarize(transactions);
      expect(summary.totalExpense, 7000);
      expect(summary.expenseByCategory['家賃'], 5000);
      expect(summary.expenseByCategory['サブスク'], 1000);
      expect(summary.expenseByCategory['食費'], 1000);
    });

    test('buildCatchupParams がローカル日付を正しく変換する（タイムゾーン回帰）', () {
      // HomeScreen は DateTime.now() を buildCatchupParams に渡す
      // 実装コードを直接呼び出して検証
      final jstMidnight = DateTime(2026, 3, 29, 0, 30); // JST 0:30
      final params = RecurringRuleRepository.buildCatchupParams(
        asOfDate: jstMidnight,
      );
      expect(
        params['p_as_of_date'],
        '2026-03-29',
        reason: 'ローカル DateTime からは常にローカル日付が取れる',
      );
    });

    test('buildCatchupParams(null) は空 map を返し DB 側 CURRENT_DATE にフォールバック', () {
      final params = RecurringRuleRepository.buildCatchupParams(asOfDate: null);
      expect(params, isEmpty, reason: 'null の場合 DB 側の CURRENT_DATE が使われる');
    });

    test('同一 recurring_rule_id + scheduled_for の取引は1件のみ存在する前提', () {
      // DB側の部分一意インデックスにより保証。
      // アプリ側では二重起票されないことを前提にサマリー計算する。
      final transactions = [
        Transaction(
          id: 'dup-check',
          userId: 'u',
          date: DateTime(2026, 3, 1),
          type: 'expense',
          amount: 5000,
          categoryId: 'c2',
          categoryName: '家賃',
          sourceType: 'recurring',
          recurringRuleId: 'rule-1',
          scheduledFor: DateTime(2026, 3, 1),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];
      final summary = TransactionRepository.summarize(transactions);
      expect(summary.totalExpense, 5000, reason: '同一ルール・日付の取引が1件のみならサマリーも1件分');
    });
  });

  group('ホーム画面: 新規追加用 デフォルト日付ロジック (Step26)', () {
    // 新規追加時の初期日付を、表示中年月と当月取引一覧から決める純粋関数のテスト。
    // - 当月表示中: 本日
    // - 当月以外で取引あり: 表示中月内の最新取引日
    // - 当月以外で取引なし: 表示中月の1日

    Transaction tx(DateTime date) => Transaction(
      id: 'id-${date.toIso8601String()}',
      userId: 'u',
      categoryId: 'c1',
      date: date,
      type: 'expense',
      amount: 100,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('当月表示中なら本日を返す', () {
      final now = DateTime(2026, 5, 9, 10, 30); // 任意の時刻
      final result = defaultDateForNewTransaction(
        year: 2026,
        month: 5,
        transactions: [tx(DateTime(2026, 5, 1)), tx(DateTime(2026, 5, 7))],
        now: now,
      );
      expect(
        result,
        DateTime(2026, 5, 9),
        reason: '当月表示中は最新取引日ではなく本日（時刻は0時に丸め）',
      );
    });

    test('当月以外で取引ありなら表示中月の最新取引日を返す（過去月）', () {
      final now = DateTime(2026, 5, 9);
      final result = defaultDateForNewTransaction(
        year: 2026,
        month: 3,
        transactions: [
          tx(DateTime(2026, 3, 1)),
          tx(DateTime(2026, 3, 25)),
          tx(DateTime(2026, 3, 10)),
        ],
        now: now,
      );
      expect(result, DateTime(2026, 3, 25));
    });

    test('当月以外で取引ありなら表示中月の最新取引日を返す（未来月）', () {
      final now = DateTime(2026, 5, 9);
      final result = defaultDateForNewTransaction(
        year: 2026,
        month: 7,
        transactions: [tx(DateTime(2026, 7, 5)), tx(DateTime(2026, 7, 20))],
        now: now,
      );
      expect(result, DateTime(2026, 7, 20));
    });

    test('当月以外で取引なしなら表示中月の1日を返す', () {
      final now = DateTime(2026, 5, 9);
      final result = defaultDateForNewTransaction(
        year: 2026,
        month: 2,
        transactions: const [],
        now: now,
      );
      expect(result, DateTime(2026, 2, 1));
    });

    test('表示中月外の取引は無視される（防御的フィルタ）', () {
      final now = DateTime(2026, 5, 9);
      // 表示中月は3月、リストには2月と4月の取引も混入
      final result = defaultDateForNewTransaction(
        year: 2026,
        month: 3,
        transactions: [tx(DateTime(2026, 2, 28)), tx(DateTime(2026, 4, 1))],
        now: now,
      );
      expect(result, DateTime(2026, 3, 1), reason: '表示中月の取引が0件と同じ扱いになり1日が返る');
    });

    test('時刻成分は0時に丸められる', () {
      final now = DateTime(2026, 5, 9);
      final result = defaultDateForNewTransaction(
        year: 2026,
        month: 4,
        transactions: [tx(DateTime(2026, 4, 15, 23, 59, 59))],
        now: now,
      );
      expect(result, DateTime(2026, 4, 15));
      expect(result.hour, 0);
      expect(result.minute, 0);
    });

    test('未来年(2030-12)でも1日にフォールバックする', () {
      final now = DateTime(2026, 5, 9);
      final result = defaultDateForNewTransaction(
        year: 2030,
        month: 12,
        transactions: const [],
        now: now,
      );
      expect(result, DateTime(2030, 12, 1));
    });
  });
}
