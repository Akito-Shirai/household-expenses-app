/// 取引モデル（収入/支出の記録）
class Transaction {
  final String id;
  final String userId;
  final String categoryId;
  final DateTime date;
  final int amount;
  final int? unitPrice; // 支出時の単価（収入時はnull）
  final int quantity; // 個数（デフォルト1）
  final String? memo;
  final String type; // 'expense' or 'income'
  final String sourceType; // 'manual' or 'recurring'
  final String? recurringRuleId; // 定期支出ルールID（自動生成時のみ）
  final DateTime? scheduledFor; // 定期支出の発生予定日（自動生成時のみ）
  final DateTime? expiredAt; // データ保持ポリシーによる期限切れ日時
  final DateTime createdAt;
  final DateTime updatedAt;

  /// JOINで取得する読み取り専用フィールド
  final String? categoryName;

  Transaction({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.date,
    required this.amount,
    this.unitPrice,
    this.quantity = 1,
    this.memo,
    required this.type,
    this.sourceType = 'manual',
    this.recurringRuleId,
    this.scheduledFor,
    this.expiredAt,
    required this.createdAt,
    required this.updatedAt,
    this.categoryName,
  });

  /// Supabaseレスポンス（JOIN含む）からモデルを生成
  factory Transaction.fromJson(Map<String, dynamic> json) {
    // categoriesリレーションからカテゴリ名を取得
    final categories = json['categories'] as Map<String, dynamic>?;
    return Transaction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      categoryId: json['category_id'] as String,
      date: DateTime.parse(json['date'] as String),
      amount: (json['amount'] as num).toInt(),
      unitPrice: json['unit_price'] != null
          ? (json['unit_price'] as num).toInt()
          : null,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      memo: json['memo'] as String?,
      type: json['type'] as String,
      sourceType: json['source_type'] as String? ?? 'manual',
      recurringRuleId: json['recurring_rule_id'] as String?,
      scheduledFor: json['scheduled_for'] != null
          ? DateTime.parse(json['scheduled_for'] as String)
          : null,
      expiredAt: json['expired_at'] != null
          ? DateTime.parse(json['expired_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      categoryName: categories?['name'] as String?,
    );
  }

  /// INSERT用JSON（id, user_id, created_at, updated_at はDB側で生成）
  Map<String, dynamic> toInsertJson() {
    return {
      'category_id': categoryId,
      'date': date.toIso8601String().substring(0, 10),
      'amount': amount,
      'unit_price': unitPrice,
      'quantity': quantity,
      'memo': memo,
      'type': type,
    };
  }

  /// UPDATE用JSON
  /// （source_type / recurring_rule_id / scheduled_for はDB/RPCが管理するため含めない）
  Map<String, dynamic> toUpdateJson() {
    return {
      'category_id': categoryId,
      'date': date.toIso8601String().substring(0, 10),
      'amount': amount,
      'unit_price': unitPrice,
      'quantity': quantity,
      'memo': memo,
      'type': type,
    };
  }

  /// 定期支出から自動生成された取引かどうか
  bool get isRecurring => sourceType == 'recurring';
}
