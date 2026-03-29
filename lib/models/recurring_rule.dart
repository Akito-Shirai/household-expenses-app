/// 定期支出ルールモデル
class RecurringRule {
  final String id;
  final String userId;
  final String categoryId;
  final int amount;
  final String? memo;
  final String frequencyUnit; // 'week' | 'month' | 'year'
  final int frequencyInterval;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// JOINで取得する読み取り専用フィールド
  final String? categoryName;

  RecurringRule({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.amount,
    this.memo,
    required this.frequencyUnit,
    required this.frequencyInterval,
    required this.startDate,
    this.endDate,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.categoryName,
  });

  /// Supabaseレスポンス（JOIN含む）からモデルを生成
  factory RecurringRule.fromJson(Map<String, dynamic> json) {
    final categories = json['categories'] as Map<String, dynamic>?;
    return RecurringRule(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      categoryId: json['category_id'] as String,
      amount: (json['amount'] as num).toInt(),
      memo: json['memo'] as String?,
      frequencyUnit: json['frequency_unit'] as String,
      frequencyInterval: (json['frequency_interval'] as num).toInt(),
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      categoryName: categories?['name'] as String?,
    );
  }

  /// INSERT用JSON（id, user_id, created_at, updated_at はDB側で生成）
  Map<String, dynamic> toInsertJson() {
    return {
      'category_id': categoryId,
      'amount': amount,
      'memo': memo,
      'frequency_unit': frequencyUnit,
      'frequency_interval': frequencyInterval,
      'start_date': _dateString(startDate),
      'end_date': endDate != null ? _dateString(endDate!) : null,
    };
  }

  /// UPDATE用JSON
  Map<String, dynamic> toUpdateJson() {
    return {
      'category_id': categoryId,
      'amount': amount,
      'memo': memo,
      'frequency_unit': frequencyUnit,
      'frequency_interval': frequencyInterval,
      'start_date': _dateString(startDate),
      'end_date': endDate != null ? _dateString(endDate!) : null,
      'is_active': isActive,
    };
  }

  /// UI表示用の頻度ラベル
  String get frequencyLabel {
    final unit = switch (frequencyUnit) {
      'week' => '週',
      'month' => '月',
      'year' => '年',
      _ => frequencyUnit,
    };
    return frequencyInterval == 1 ? '毎$unit' : '$frequencyInterval$unitごと';
  }

  /// 日付をISO 8601の日付部分のみに変換
  static String _dateString(DateTime d) =>
      d.toIso8601String().substring(0, 10);
}
