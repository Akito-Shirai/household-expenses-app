import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/user_settings.dart';
import 'package:household_mvp/utils/fx_converter.dart';

void main() {
  group('FxConverter', () {
    test('JPYの場合はそのまま返す', () {
      expect(FxConverter.convert(1000, null, 'JPY'), 1000.0);
    });

    test('JPYの場合はレート無視', () {
      expect(FxConverter.convert(1000, 150.0, 'JPY'), 1000.0);
    });

    test('USDに換算（レート150）', () {
      final result = FxConverter.convert(15000, 150.0, 'USD');
      expect(result, closeTo(100.0, 0.001));
    });

    test('レート未設定の場合はnullを返す', () {
      expect(FxConverter.convert(1000, null, 'USD'), isNull);
    });

    test('レートがゼロの場合はnullを返す', () {
      expect(FxConverter.convert(1000, 0.0, 'USD'), isNull);
    });

    test('レートが負の場合はnullを返す', () {
      expect(FxConverter.convert(1000, -1.0, 'USD'), isNull);
    });

    test('ゼロ金額の換算', () {
      expect(FxConverter.convert(0, 150.0, 'USD'), 0.0);
    });

    test('大きい金額の換算', () {
      final result = FxConverter.convert(1500000, 150.0, 'USD');
      expect(result, closeTo(10000.0, 0.001));
    });
  });

  group('MoneyFormatter', () {
    final jpySettings = UserSettings(
      userId: 'test',
      displayCurrency: 'JPY',
      fxMode: 'manual',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final usdSettings = UserSettings(
      userId: 'test',
      displayCurrency: 'USD',
      fxMode: 'manual',
      manualRate: 150.0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final usdNoRateSettings = UserSettings(
      userId: 'test',
      displayCurrency: 'USD',
      fxMode: 'manual',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('JPYフォーマット - 基本', () {
      final result = MoneyFormatter.format(1000, jpySettings);
      expect(result, contains('1,000'));
      expect(result, contains('¥'));
    });

    test('JPYフォーマット - ゼロ', () {
      final result = MoneyFormatter.format(0, jpySettings);
      expect(result, contains('0'));
    });

    test('JPYフォーマット - 大きい金額', () {
      final result = MoneyFormatter.format(1234567, jpySettings);
      expect(result, contains('1,234,567'));
    });

    test('USDフォーマット - レートあり', () {
      // 15000 JPY / 150 = 100.00 USD
      final result = MoneyFormatter.format(15000, usdSettings);
      expect(result, contains('100.00'));
      expect(result, contains('\$'));
    });

    test('USDフォーマット - レート未設定時はJPYフォールバック', () {
      final result = MoneyFormatter.format(15000, usdNoRateSettings);
      expect(result, contains('¥'));
      expect(result, contains('15,000'));
    });

    test('符号付きフォーマット - マイナス', () {
      final result = MoneyFormatter.formatSigned(-1000, jpySettings);
      expect(result, contains('-'));
      expect(result, contains('1,000'));
    });

    test('符号付きフォーマット - プラス', () {
      final result = MoneyFormatter.formatSigned(1000, jpySettings);
      expect(result.startsWith('-'), isFalse);
      expect(result, contains('1,000'));
    });

    test('取引リスト表示 - 支出', () {
      final result = MoneyFormatter.formatWithSign(1000, jpySettings, isExpense: true);
      expect(result, startsWith('-'));
    });

    test('取引リスト表示 - 収入', () {
      final result = MoneyFormatter.formatWithSign(1000, jpySettings, isExpense: false);
      expect(result, startsWith('+'));
    });

    test('通貨記号', () {
      expect(MoneyFormatter.symbol('JPY'), '¥');
      expect(MoneyFormatter.symbol('USD'), '\$');
      expect(MoneyFormatter.symbol('AUD'), 'A\$');
      expect(MoneyFormatter.symbol('EUR'), '€');
      expect(MoneyFormatter.symbol('GBP'), '£');
    });
  });

  group('UserSettings.effectiveRate', () {
    test('JPYの場合はnull', () {
      final s = UserSettings(
        userId: 'test',
        displayCurrency: 'JPY',
        fxMode: 'manual',
        manualRate: 150.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(s.effectiveRate, isNull);
    });

    test('manualモードではmanualRateを返す', () {
      final s = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'manual',
        manualRate: 150.0,
        lastRate: 148.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(s.effectiveRate, 150.0);
    });

    test('autoモードではlastRateを返す', () {
      final s = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'auto',
        manualRate: 150.0,
        lastRate: 148.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(s.effectiveRate, 148.0);
    });
  });
}
