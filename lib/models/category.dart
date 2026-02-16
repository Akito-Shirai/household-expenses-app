/// カテゴリモデル（収入/支出の分類）
class Category {
  final String id;
  final String userId;
  final String name;
  final String type; // 'expense' or 'income'
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  Category({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Supabaseレスポンスからモデルを生成
  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      sortOrder: json['sort_order'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// INSERT用JSON（id, user_id, created_at, updated_at はDB側で生成）
  Map<String, dynamic> toInsertJson() {
    return {'name': name, 'type': type, 'sort_order': sortOrder};
  }

  /// UPDATE用JSON
  Map<String, dynamic> toUpdateJson() {
    return {'name': name, 'type': type, 'sort_order': sortOrder};
  }
}
