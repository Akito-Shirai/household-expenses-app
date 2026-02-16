import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/category.dart';

/// カテゴリのCRUD操作を提供するリポジトリ
class CategoryRepository {
  final SupabaseClient _client;

  CategoryRepository(this._client);

  /// 指定種別のカテゴリ一覧を取得（sort_order昇順）
  Future<List<Category>> list(String type) async {
    final data = await _client
        .from('categories')
        .select()
        .eq('type', type)
        .order('sort_order');
    return data.map((json) => Category.fromJson(json)).toList();
  }

  /// 全カテゴリ一覧を取得（sort_order昇順）
  Future<List<Category>> listAll() async {
    final data = await _client.from('categories').select().order('sort_order');
    return data.map((json) => Category.fromJson(json)).toList();
  }

  String get _userId => _client.auth.currentUser!.id;

  /// カテゴリを作成（user_id はDB側 default auth.uid() で設定）
  Future<Category> create({
    required String name,
    required String type,
    required int sortOrder,
  }) async {
    final data = await _client
        .from('categories')
        .insert({'name': name, 'type': type, 'sort_order': sortOrder})
        .select()
        .single();
    return Category.fromJson(data);
  }

  /// カテゴリを更新（user_id条件でRLS+アプリ層の二重防御）
  Future<Category> update({
    required String id,
    required String name,
    required int sortOrder,
  }) async {
    final data = await _client
        .from('categories')
        .update({'name': name, 'sort_order': sortOrder})
        .eq('id', id)
        .eq('user_id', _userId)
        .select()
        .single();
    return Category.fromJson(data);
  }

  /// カテゴリを削除（user_id条件付き、FK制約エラーの場合は例外をスロー）
  Future<void> delete(String id) async {
    await _client
        .from('categories')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId);
  }
}
