/// OCRトークンのバウンディングボックス（位置・サイズ情報）
class OcrBoundingBox {
  /// 左上X座標
  final double x;

  /// 左上Y座標
  final double y;

  /// 幅
  final double width;

  /// 高さ（フォントサイズの代理指標として使用）
  final double height;

  const OcrBoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// プラットフォーム共通のOCRトークン
///
/// ML Kit / tesseract.js の出力を正規化した共通形式。
/// 抽出ロジックはこのモデルのみに依存し、エンジン固有の型を参照しない。
class OcrToken {
  /// 認識されたテキスト
  final String text;

  /// バウンディングボックス（利用不可の場合は null）
  final OcrBoundingBox? bbox;

  /// 認識信頼度（0.0〜1.0、取得できない場合は null）
  final double? confidence;

  const OcrToken({
    required this.text,
    this.bbox,
    this.confidence,
  });
}
