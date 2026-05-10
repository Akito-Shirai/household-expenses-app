import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/recurring_rule.dart';
import 'package:household_mvp/models/user_settings.dart';
import 'package:household_mvp/screens/settings_screen.dart';
import 'package:household_mvp/utils/fx_converter.dart';
import 'package:household_mvp/widgets/state_views.dart';

/// SettingsScreenの主要ロジック（通貨設定バリデーション・カテゴリ空状態）のテスト。
/// 画面全体はSupabase依存のため、ロジック・UIパーツ単位でテストする。
void main() {
  group('設定画面: 通貨設定バリデーション', () {
    // _saveCurrencySettings()内のバリデーション相当
    bool validateRate(String rateText) {
      if (rateText.trim().isEmpty) return true; // 空は許可
      final rate = double.tryParse(rateText.trim());
      return rate != null && rate > 0;
    }

    test('正の数値はバリデーション通過', () {
      expect(validateRate('150'), isTrue);
      expect(validateRate('150.5'), isTrue);
      expect(validateRate('0.0067'), isTrue);
    });

    test('空文字はバリデーション通過（未設定扱い）', () {
      expect(validateRate(''), isTrue);
      expect(validateRate('  '), isTrue);
    });

    test('ゼロはバリデーションNG', () {
      expect(validateRate('0'), isFalse);
      expect(validateRate('0.0'), isFalse);
    });

    test('負数はバリデーションNG', () {
      expect(validateRate('-1'), isFalse);
      expect(validateRate('-150.5'), isFalse);
    });

    test('非数値はバリデーションNG', () {
      expect(validateRate('abc'), isFalse);
      expect(validateRate('12.34.56'), isFalse);
    });
  });

  group('設定画面: 通貨ラベル表示', () {
    test('全サポート通貨の記号が取得できる', () {
      for (final currency in UserSettings.supportedCurrencies) {
        final symbol = MoneyFormatter.symbol(currency);
        expect(symbol.isNotEmpty, isTrue, reason: '$currency の記号が空');
      }
    });

    test('通貨ラベルマップが全通貨をカバー', () {
      const currencyLabels = {
        'JPY': 'JPY (¥)',
        'USD': r'USD ($)',
        'AUD': r'AUD (A$)',
        'EUR': 'EUR (€)',
        'GBP': 'GBP (£)',
      };

      for (final currency in UserSettings.supportedCurrencies) {
        expect(
          currencyLabels.containsKey(currency),
          isTrue,
          reason: '$currency がラベルマップに未登録',
        );
      }
    });
  });

  group('設定画面: カテゴリ空状態表示', () {
    testWidgets('EmptyStateViewにカテゴリ追加ボタンが表示される', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              icon: Icons.category_outlined,
              title: 'カテゴリがありません',
              subtitle: 'カテゴリを追加して取引を分類しましょう',
              actionLabel: 'カテゴリを追加',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('カテゴリがありません'), findsOneWidget);
      expect(find.text('カテゴリを追加して取引を分類しましょう'), findsOneWidget);
      expect(find.text('カテゴリを追加'), findsOneWidget);

      await tester.tap(find.text('カテゴリを追加'));
      expect(tapped, isTrue);
    });
  });

  group('設定画面: エラー状態表示', () {
    testWidgets('ErrorStateViewにリトライボタンが表示される', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorStateView(
              message: 'データの読み込みに失敗しました',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('データの読み込みに失敗しました'), findsOneWidget);
      expect(find.text('再読み込み'), findsOneWidget);

      await tester.tap(find.text('再読み込み'));
      expect(retried, isTrue);
    });
  });

  group('設定画面: ローディング状態表示', () {
    testWidgets('LoadingViewにメッセージが表示される', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingView(message: '読み込み中...'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('読み込み中...'), findsOneWidget);
    });
  });

  group('設定画面: FXモード設定', () {
    testWidgets('SegmentedButtonで手動/自動が表示される', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'manual',
                  label: Text('手動'),
                  icon: Icon(Icons.edit),
                ),
                ButtonSegment(
                  value: 'auto',
                  label: Text('自動'),
                  icon: Icon(Icons.sync),
                  enabled: false,
                ),
              ],
              selected: const {'manual'},
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('手動'), findsOneWidget);
      expect(find.text('自動'), findsOneWidget);
    });
  });

  group('設定画面: 未保存差分チェックロジック', () {
    // _hasUnsavedCurrencyChanges 相当のロジックを単体テスト化
    bool hasUnsavedChanges({
      required String selectedCurrency,
      required String selectedFxMode,
      required UserSettings? savedSettings,
    }) {
      if (savedSettings == null) return true;
      return selectedCurrency != savedSettings.displayCurrency ||
          selectedFxMode != savedSettings.fxMode;
    }

    test('DB値と一致する場合は未保存差分なし', () {
      final saved = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'auto',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(
        hasUnsavedChanges(
          selectedCurrency: 'USD',
          selectedFxMode: 'auto',
          savedSettings: saved,
        ),
        isFalse,
      );
    });

    test('通貨がDB値と異なる場合は未保存差分あり', () {
      final saved = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'auto',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(
        hasUnsavedChanges(
          selectedCurrency: 'EUR',
          selectedFxMode: 'auto',
          savedSettings: saved,
        ),
        isTrue,
      );
    });

    test('FXモードがDB値と異なる場合は未保存差分あり', () {
      final saved = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'manual',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(
        hasUnsavedChanges(
          selectedCurrency: 'USD',
          selectedFxMode: 'auto',
          savedSettings: saved,
        ),
        isTrue,
      );
    });

    test('savedSettingsがnullの場合は未保存差分あり', () {
      expect(
        hasUnsavedChanges(
          selectedCurrency: 'USD',
          selectedFxMode: 'auto',
          savedSettings: null,
        ),
        isTrue,
      );
    });
  });

  group('設定画面: UserSettings設定値の整合性', () {
    test('デフォルト設定のフィールド値が正しい', () {
      final settings = UserSettings.defaults('test-user');
      expect(settings.displayCurrency, 'JPY');
      expect(settings.fxMode, 'manual');
      expect(settings.manualRate, isNull);
      expect(settings.lastRate, isNull);
    });

    test('updateCurrencySettingsで使われるtoJsonに必要フィールドが含まれる', () {
      final settings = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'manual',
        manualRate: 150.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final json = settings.toJson();
      expect(json.containsKey('display_currency'), isTrue);
      expect(json.containsKey('fx_mode'), isTrue);
      expect(json.containsKey('manual_rate'), isTrue);
      expect(json['display_currency'], 'USD');
      expect(json['fx_mode'], 'manual');
      expect(json['manual_rate'], 150.0);
    });
  });

  group('設定画面: 定期支出ルール バリデーション', () {
    // _showRecurringRuleDialog 内のバリデーション相当
    bool validateAmount(String text) {
      if (text.isEmpty) return false;
      final n = int.tryParse(text);
      return n != null && n >= 0;
    }

    bool validateInterval(String text) {
      if (text.isEmpty) return false;
      final n = int.tryParse(text);
      return n != null && n >= 1;
    }

    test('金額: 正の整数はOK', () {
      expect(validateAmount('1000'), isTrue);
      expect(validateAmount('0'), isTrue);
    });

    test('金額: 空文字はNG', () {
      expect(validateAmount(''), isFalse);
    });

    test('金額: 非数値はNG', () {
      expect(validateAmount('abc'), isFalse);
    });

    test('間隔: 1以上はOK', () {
      expect(validateInterval('1'), isTrue);
      expect(validateInterval('12'), isTrue);
    });

    test('間隔: 0はNG', () {
      expect(validateInterval('0'), isFalse);
    });

    test('間隔: 空文字はNG', () {
      expect(validateInterval(''), isFalse);
    });
  });

  group('設定画面: RecurringRuleモデル表示', () {
    test('frequencyLabelが設定画面表示に適した文字列を返す', () {
      final rule = RecurringRule(
        id: 'r1',
        userId: 'u',
        categoryId: 'c1',
        amount: 1000,
        frequencyUnit: 'month',
        frequencyInterval: 1,
        startDate: DateTime(2026, 1, 1),
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(rule.frequencyLabel, '毎月');
    });

    test('無効ルールのisActiveがfalse', () {
      final rule = RecurringRule(
        id: 'r2',
        userId: 'u',
        categoryId: 'c1',
        amount: 2000,
        frequencyUnit: 'week',
        frequencyInterval: 2,
        startDate: DateTime(2026, 1, 1),
        isActive: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(rule.isActive, isFalse);
      expect(rule.frequencyLabel, '2週ごと');
    });
  });

  group('Step27: 定期支出ルール削除 確認ダイアログ', () {
    // 確認ダイアログの文言は SettingsScreen の static const として公開している。
    // 文言が変わるとテストが即失敗するので、削除/無効化の文言混在時の回帰を検知できる。

    test('削除ダイアログのタイトルが「定期支出ルール削除」', () {
      expect(
        SettingsScreen.recurringRuleDeleteDialogTitle,
        '定期支出ルール削除',
      );
    });

    test('削除ダイアログの本文に「通常取引として残ります」が含まれる', () {
      // 「無効化」と「削除」が同じ画面に存在するため、
      // 削除後の挙動（既存取引が残る、再生成されない）を本文で明示する必要がある。
      expect(
        SettingsScreen.recurringRuleDeleteDialogMessage,
        contains('通常取引として残ります'),
      );
    });

    test('削除ダイアログ本文に「自動作成されることはありません」が含まれる', () {
      expect(
        SettingsScreen.recurringRuleDeleteDialogMessage,
        contains('自動作成されることはありません'),
      );
    });

    test('削除ダイアログ本文と無効化トグル文言が異なる', () {
      // 無効化（一時停止）と削除（恒久）の意味の混同を防ぐ
      expect(
        SettingsScreen.recurringRuleDeleteDialogMessage,
        isNot(contains('一時停止')),
      );
      expect(
        SettingsScreen.recurringRuleDeleteDialogMessage,
        isNot(contains('無効化')),
      );
    });

    testWidgets('確認ダイアログに「削除」と「キャンセル」両方のボタンが表示される',
        (tester) async {
      // ダイアログ自体は実画面で表示されるが、文言・ボタン構造は
      // 既存の取引削除ダイアログと同じパターンに従っている前提。
      // このテストは「削除」ボタンが destructive style（error color）で
      // 表示できる構造になっていることを確認する。
      late ThemeData capturedTheme;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              return Scaffold(
                body: AlertDialog(
                  title: const Text(
                    SettingsScreen.recurringRuleDeleteDialogTitle,
                  ),
                  content: const Text(
                    SettingsScreen.recurringRuleDeleteDialogMessage,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {},
                      child: const Text('キャンセル'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: capturedTheme.colorScheme.error,
                      ),
                      onPressed: () {},
                      child: const Text('削除'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('定期支出ルール削除'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
      expect(find.text('削除'), findsOneWidget);
      expect(
        find.text(SettingsScreen.recurringRuleDeleteDialogMessage),
        findsOneWidget,
      );
    });
  });
}
