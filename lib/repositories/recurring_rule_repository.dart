import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/recurring_rule.dart';

/// 定期支出ルールのCRUD + catch-up RPC呼び出し
class RecurringRuleRepository {
  final SupabaseClient _client;
  RecurringRuleRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  /// 全ルールを取得（active優先、作成日降順）
  Future<List<RecurringRule>> listAll() async {
    final data = await _client
        .from('recurring_rules')
        .select('*, categories(name)')
        .order('is_active', ascending: false)
        .order('created_at', ascending: false);
    return data.map((json) => RecurringRule.fromJson(json)).toList();
  }

  /// 新規ルール作成
  Future<RecurringRule> create({
    required String categoryId,
    required int amount,
    String? memo,
    String frequencyUnit = 'month',
    int frequencyInterval = 1,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final data = await _client
        .from('recurring_rules')
        .insert({
          'category_id': categoryId,
          'amount': amount,
          'memo': memo,
          'frequency_unit': frequencyUnit,
          'frequency_interval': frequencyInterval,
          'start_date': startDate.toIso8601String().substring(0, 10),
          'end_date': endDate?.toIso8601String().substring(0, 10),
        })
        .select('*, categories(name)')
        .single();
    return RecurringRule.fromJson(data);
  }

  /// ルール更新
  Future<RecurringRule> update({
    required String id,
    required String categoryId,
    required int amount,
    String? memo,
    required String frequencyUnit,
    required int frequencyInterval,
    required DateTime startDate,
    DateTime? endDate,
    required bool isActive,
  }) async {
    final data = await _client
        .from('recurring_rules')
        .update({
          'category_id': categoryId,
          'amount': amount,
          'memo': memo,
          'frequency_unit': frequencyUnit,
          'frequency_interval': frequencyInterval,
          'start_date': startDate.toIso8601String().substring(0, 10),
          'end_date': endDate?.toIso8601String().substring(0, 10),
          'is_active': isActive,
        })
        .eq('id', id)
        .eq('user_id', _userId)
        .select('*, categories(name)')
        .single();
    return RecurringRule.fromJson(data);
  }

  /// ルール無効化（v1では物理削除しない）
  Future<void> deactivate(String id) async {
    await _client
        .from('recurring_rules')
        .update({'is_active': false})
        .eq('id', id)
        .eq('user_id', _userId);
  }

  /// ルール有効化
  Future<void> activate(String id) async {
    await _client
        .from('recurring_rules')
        .update({'is_active': true})
        .eq('id', id)
        .eq('user_id', _userId);
  }

  /// catch-up RPC のパラメータを構築する（テスト可能な純粋関数）
  static Map<String, dynamic> buildCatchupParams({DateTime? asOfDate}) {
    if (asOfDate == null) return <String, dynamic>{};
    return {'p_as_of_date': asOfDate.toIso8601String().substring(0, 10)};
  }

  /// catch-up RPC実行（未生成分の定期取引を一括起票）
  /// [asOfDate] を渡すことでクライアントのローカル日付基準で起票する。
  /// 省略時はDB側の CURRENT_DATE（UTC）が使われる。
  Future<int> runCatchup({DateTime? asOfDate}) async {
    final params = buildCatchupParams(asOfDate: asOfDate);
    final result = await _client.rpc('recurring_catchup', params: params);
    return (result as int?) ?? 0;
  }

  /// 定期支出ルール削除 RPC 名（テストで参照するための定数）
  static const String deleteRuleRpcName = 'delete_recurring_rule';

  /// 定期支出ルール削除 RPC のパラメータを構築する（テスト可能な純粋関数）
  static Map<String, dynamic> buildDeleteRuleParams(String id) {
    return {'p_rule_id': id};
  }

  /// 定期支出ルール削除（RPC経由）
  /// 戻り値は通常取引化（detach）した既存生成済み取引の件数。
  ///
  /// 単純な物理削除ではなく、対象ルール由来の transactions を通常取引化
  /// (`source_type='manual'`, `recurring_rule_id=null`, `scheduled_for=null`)
  /// した後、recurring_rule_exceptions を削除し、ルール本体を削除する。
  /// すべて 1 トランザクションで実行されるため中途半端な状態にならない。
  Future<int> deleteRule(String id) async {
    final result = await _client.rpc(
      deleteRuleRpcName,
      params: buildDeleteRuleParams(id),
    );
    return (result as int?) ?? 0;
  }
}
