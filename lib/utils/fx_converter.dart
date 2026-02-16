import 'package:intl/intl.dart';

import '../models/user_settings.dart';

/// JPY基準の金額を表示通貨に換算するユーティリティ
class FxConverter {
  const FxConverter._();

  /// JPY金額を表示通貨に換算
  /// - JPYの場合はそのまま返す
  /// - レート未設定またはゼロ以下の場合はnullを返す（呼び出し元でフォールバック判断）
  static double? convert(int jpyAmount, double? rate, String currency) {
    if (currency == 'JPY') return jpyAmount.toDouble();
    if (rate == null || rate <= 0) return null;
    return jpyAmount / rate;
  }
}

/// 通貨フォーマッタ（intl の NumberFormat.currency を使用）
class MoneyFormatter {
  const MoneyFormatter._();

  /// 通貨コードに対応するNumberFormatを取得
  static NumberFormat _getFormat(String currency) {
    switch (currency) {
      case 'JPY':
        return NumberFormat.currency(locale: 'ja_JP', symbol: '¥', decimalDigits: 0);
      case 'USD':
        return NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
      case 'AUD':
        return NumberFormat.currency(locale: 'en_AU', symbol: 'A\$', decimalDigits: 2);
      case 'EUR':
        return NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
      case 'GBP':
        return NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2);
      default:
        return NumberFormat.currency(locale: 'ja_JP', symbol: '¥', decimalDigits: 0);
    }
  }

  /// 通貨記号を取得
  static String symbol(String currency) {
    switch (currency) {
      case 'JPY': return '¥';
      case 'USD': return '\$';
      case 'AUD': return 'A\$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      default: return '¥';
    }
  }

  /// JPY金額をUserSettingsに基づいてフォーマット
  /// - 換算失敗時はJPYにフォールバック
  static String format(int jpyAmount, UserSettings settings) {
    final currency = settings.displayCurrency;
    final rate = settings.effectiveRate;

    final converted = FxConverter.convert(jpyAmount, rate, currency);

    if (converted == null) {
      // フォールバック: JPYで表示
      final fmt = _getFormat('JPY');
      return fmt.format(jpyAmount);
    }

    final fmt = _getFormat(currency);
    return fmt.format(converted);
  }

  /// 符号付きフォーマット（サマリー表示用）
  /// - マイナスの場合は負符号を先頭に付与
  static String formatSigned(int jpyAmount, UserSettings settings) {
    final absFormatted = format(jpyAmount.abs(), settings);
    return jpyAmount < 0 ? '-$absFormatted' : absFormatted;
  }

  /// 符号付きフォーマット（取引リスト表示用: +/- 付き）
  static String formatWithSign(int jpyAmount, UserSettings settings, {required bool isExpense}) {
    final absFormatted = format(jpyAmount.abs(), settings);
    return isExpense ? '-$absFormatted' : '+$absFormatted';
  }
}
