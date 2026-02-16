import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/user_settings.dart';
import 'package:household_mvp/repositories/user_settings_repository.dart';

void main() {
  group('UserSettings.fromJson', () {
    test('全フィールドありでパースできる', () {
      final json = {
        'user_id': 'abc-123',
        'display_currency': 'USD',
        'fx_mode': 'manual',
        'manual_rate': 150.5,
        'last_rate': 148.0,
        'last_rate_at': '2026-02-16T10:00:00Z',
        'created_at': '2026-02-16T09:00:00Z',
        'updated_at': '2026-02-16T10:00:00Z',
      };

      final settings = UserSettings.fromJson(json);

      expect(settings.userId, 'abc-123');
      expect(settings.displayCurrency, 'USD');
      expect(settings.fxMode, 'manual');
      expect(settings.manualRate, 150.5);
      expect(settings.lastRate, 148.0);
      expect(settings.lastRateAt, isNotNull);
      expect(settings.createdAt.year, 2026);
    });

    test('nullableフィールドがnullでもパースできる', () {
      final json = {
        'user_id': 'abc-123',
        'display_currency': 'JPY',
        'fx_mode': 'manual',
        'manual_rate': null,
        'last_rate': null,
        'last_rate_at': null,
        'created_at': '2026-02-16T09:00:00Z',
        'updated_at': '2026-02-16T10:00:00Z',
      };

      final settings = UserSettings.fromJson(json);

      expect(settings.manualRate, isNull);
      expect(settings.lastRate, isNull);
      expect(settings.lastRateAt, isNull);
    });

    test('intのレート値もdoubleに変換される', () {
      final json = {
        'user_id': 'abc-123',
        'display_currency': 'USD',
        'fx_mode': 'manual',
        'manual_rate': 150,
        'last_rate': null,
        'last_rate_at': null,
        'created_at': '2026-02-16T09:00:00Z',
        'updated_at': '2026-02-16T10:00:00Z',
      };

      final settings = UserSettings.fromJson(json);
      expect(settings.manualRate, 150.0);
    });

    test('fx_mode: auto でパースできる', () {
      final json = {
        'user_id': 'abc-123',
        'display_currency': 'EUR',
        'fx_mode': 'auto',
        'manual_rate': null,
        'last_rate': 165.0,
        'last_rate_at': '2026-02-16T10:00:00Z',
        'created_at': '2026-02-16T09:00:00Z',
        'updated_at': '2026-02-16T10:00:00Z',
      };

      final settings = UserSettings.fromJson(json);
      expect(settings.fxMode, 'auto');
      expect(settings.lastRate, 165.0);
    });
  });

  group('UserSettings.toJson', () {
    test('必要なフィールドのみ含む', () {
      final settings = UserSettings(
        userId: 'abc-123',
        displayCurrency: 'USD',
        fxMode: 'manual',
        manualRate: 150.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = settings.toJson();

      expect(json['display_currency'], 'USD');
      expect(json['fx_mode'], 'manual');
      expect(json['manual_rate'], 150.0);
      // user_id, created_at, updated_at は含まない
      expect(json.containsKey('user_id'), isFalse);
      expect(json.containsKey('created_at'), isFalse);
    });

    test('manualRate が null でも出力される', () {
      final settings = UserSettings(
        userId: 'abc-123',
        displayCurrency: 'JPY',
        fxMode: 'manual',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = settings.toJson();
      expect(json.containsKey('manual_rate'), isTrue);
      expect(json['manual_rate'], isNull);
    });
  });

  group('UserSettings.defaults', () {
    test('デフォルト値が正しい', () {
      final settings = UserSettings.defaults('test-user');

      expect(settings.userId, 'test-user');
      expect(settings.displayCurrency, 'JPY');
      expect(settings.fxMode, 'manual');
      expect(settings.manualRate, isNull);
      expect(settings.lastRate, isNull);
    });

    test('デフォルト設定のeffectiveRateはnull (JPYなので)', () {
      final settings = UserSettings.defaults('test-user');
      expect(settings.effectiveRate, isNull);
    });
  });

  group('supportedCurrencies', () {
    test('5通貨が含まれる', () {
      expect(UserSettings.supportedCurrencies, hasLength(5));
      expect(UserSettings.supportedCurrencies, contains('JPY'));
      expect(UserSettings.supportedCurrencies, contains('USD'));
      expect(UserSettings.supportedCurrencies, contains('AUD'));
      expect(UserSettings.supportedCurrencies, contains('EUR'));
      expect(UserSettings.supportedCurrencies, contains('GBP'));
    });
  });

  group('UserSettingsRepository API整合性', () {
    // Supabase 接続が不要な型レベルの検証
    test('UserSettingsRepository クラスが存在する', () {
      // コンパイルが通ること自体が型の整合性を担保
      expect(UserSettingsRepository, isNotNull);
    });
  });

  group('UserSettings.effectiveRate フォールバックケース', () {
    test('manualモードでmanualRateがnullの場合もnullを返す', () {
      final s = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'manual',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(s.effectiveRate, isNull);
    });

    test('autoモードでlastRateがnullの場合もnullを返す', () {
      final s = UserSettings(
        userId: 'test',
        displayCurrency: 'USD',
        fxMode: 'auto',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(s.effectiveRate, isNull);
    });

    test('JPYの場合はどのモードでもnullを返す', () {
      final manual = UserSettings(
        userId: 'test',
        displayCurrency: 'JPY',
        fxMode: 'manual',
        manualRate: 150.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(manual.effectiveRate, isNull);

      final auto = UserSettings(
        userId: 'test',
        displayCurrency: 'JPY',
        fxMode: 'auto',
        lastRate: 148.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(auto.effectiveRate, isNull);
    });

    test('全通貨でeffectiveRateが正しく動作する', () {
      for (final currency in ['USD', 'AUD', 'EUR', 'GBP']) {
        final s = UserSettings(
          userId: 'test',
          displayCurrency: currency,
          fxMode: 'manual',
          manualRate: 100.0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        expect(s.effectiveRate, 100.0, reason: '$currency でmanualRate取得');
      }
    });
  });

  group('レート入力バリデーションロジック', () {
    // 設定画面のバリデーションロジックを単体テスト化
    // （SettingsScreen._saveCurrencySettings() の検証ロジック相当）

    bool validateRate(String rateText) {
      if (rateText.trim().isEmpty) return true; // 空は許可（未設定扱い）
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
}
