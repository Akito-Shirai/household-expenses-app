import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_settings.dart';

/// ユーザー設定の取得・更新リポジトリ
class UserSettingsRepository {
  final SupabaseClient _client;

  UserSettingsRepository(this._client);

  /// 設定を取得。未作成ならデフォルト値で作成して返す
  Future<UserSettings> getOrCreate() async {
    final userId = _client.auth.currentUser!.id;

    // まず取得を試みる
    final response = await _client
        .from('user_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response != null) {
      return UserSettings.fromJson(response);
    }

    // 未作成の場合はデフォルト値でINSERT
    final inserted = await _client
        .from('user_settings')
        .insert({'display_currency': 'JPY', 'fx_mode': 'manual'})
        .select()
        .single();
    return UserSettings.fromJson(inserted);
  }

  /// 表示通貨を更新
  Future<UserSettings> updateDisplayCurrency(String currency) async {
    final userId = _client.auth.currentUser!.id;
    final updated = await _client
        .from('user_settings')
        .update({'display_currency': currency})
        .eq('user_id', userId)
        .select()
        .single();
    return UserSettings.fromJson(updated);
  }

  /// 手動レートを更新
  Future<UserSettings> updateManualRate(double? rate) async {
    final userId = _client.auth.currentUser!.id;
    final updated = await _client
        .from('user_settings')
        .update({'manual_rate': rate})
        .eq('user_id', userId)
        .select()
        .single();
    return UserSettings.fromJson(updated);
  }

  /// FXモードを更新
  Future<UserSettings> updateFxMode(String mode) async {
    final userId = _client.auth.currentUser!.id;
    final updated = await _client
        .from('user_settings')
        .update({'fx_mode': mode})
        .eq('user_id', userId)
        .select()
        .single();
    return UserSettings.fromJson(updated);
  }

  /// 自動取得レートを更新（last_rate / last_rate_at）
  Future<UserSettings> updateLastRate(double rate) async {
    final userId = _client.auth.currentUser!.id;
    final updated = await _client
        .from('user_settings')
        .update({
          'last_rate': rate,
          'last_rate_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', userId)
        .select()
        .single();
    return UserSettings.fromJson(updated);
  }

  /// 表示通貨・レート・モードをまとめて更新
  Future<UserSettings> updateCurrencySettings({
    required String currency,
    double? manualRate,
    String fxMode = 'manual',
  }) async {
    final userId = _client.auth.currentUser!.id;
    final updated = await _client
        .from('user_settings')
        .update({
          'display_currency': currency,
          'manual_rate': manualRate,
          'fx_mode': fxMode,
        })
        .eq('user_id', userId)
        .select()
        .single();
    return UserSettings.fromJson(updated);
  }
}
