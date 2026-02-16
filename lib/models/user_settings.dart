/// ユーザー設定モデル（表示通貨・為替レート）
class UserSettings {
  final String userId;
  final String displayCurrency;
  final String fxMode;
  final double? manualRate;
  final double? lastRate;
  final DateTime? lastRateAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserSettings({
    required this.userId,
    required this.displayCurrency,
    required this.fxMode,
    this.manualRate,
    this.lastRate,
    this.lastRateAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// デフォルト値（JPY・手動・レート未設定）
  factory UserSettings.defaults(String userId) {
    final now = DateTime.now();
    return UserSettings(
      userId: userId,
      displayCurrency: 'JPY',
      fxMode: 'manual',
      createdAt: now,
      updatedAt: now,
    );
  }

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      userId: json['user_id'] as String,
      displayCurrency: json['display_currency'] as String,
      fxMode: json['fx_mode'] as String,
      manualRate: (json['manual_rate'] as num?)?.toDouble(),
      lastRate: (json['last_rate'] as num?)?.toDouble(),
      lastRateAt: json['last_rate_at'] != null
          ? DateTime.parse(json['last_rate_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'display_currency': displayCurrency,
      'fx_mode': fxMode,
      'manual_rate': manualRate,
    };
  }

  /// 有効なレートを返す（manualモードではmanualRate、autoではlastRate）
  double? get effectiveRate {
    if (displayCurrency == 'JPY') return null;
    return fxMode == 'manual' ? manualRate : lastRate;
  }

  /// サポート通貨一覧
  static const supportedCurrencies = ['JPY', 'USD', 'AUD', 'EUR', 'GBP'];
}
