import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/user_settings.dart';
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
}
