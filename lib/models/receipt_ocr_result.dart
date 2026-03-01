/// OCR抽出結果のデータクラス
class ReceiptOcrResult {
  /// 店名候補（null = 抽出失敗）
  final String? merchantName;

  /// 合計金額候補（null = 抽出失敗）
  final int? totalAmount;

  /// 信頼度（0.0 ~ 1.0）
  final double confidence;

  const ReceiptOcrResult({
    this.merchantName,
    this.totalAmount,
    required this.confidence,
  });

  /// 信頼度レベル（UI表示用）
  ConfidenceLevel get confidenceLevel {
    if (confidence >= 0.8) return ConfidenceLevel.high;
    if (confidence >= 0.5) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }

  /// 何も抽出できなかったか
  bool get isEmpty => merchantName == null && totalAmount == null;
}

/// 信頼度レベル
enum ConfidenceLevel {
  high,
  medium,
  low;

  /// 日本語ラベル
  String get label {
    switch (this) {
      case ConfidenceLevel.high:
        return '高';
      case ConfidenceLevel.medium:
        return '中';
      case ConfidenceLevel.low:
        return '低';
    }
  }
}
