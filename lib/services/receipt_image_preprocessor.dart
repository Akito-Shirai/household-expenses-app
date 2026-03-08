import 'dart:typed_data';

export 'receipt_image_preprocessor_factory.dart';

/// 画像前処理の結果
class PreprocessResult {
  /// 処理済み画像バイト列
  final Uint8List bytes;

  /// 変換後のフォーマット（例: 'jpeg', 'png'）
  final String format;

  /// 変換が行われたか（false = パススルー）
  final bool converted;

  /// 適用された補正内容（デバッグ用）
  final List<String> appliedSteps;

  const PreprocessResult({
    required this.bytes,
    required this.format,
    this.converted = false,
    this.appliedSteps = const [],
  });
}

/// マジックバイトから画像フォーマットを判定する共通ユーティリティ
///
/// mimeType ヒントがある場合はフォールバックとして使用する。
/// HEIC/HEIF の判定は ftyp ボックス（offset 4-7）で行う。
String detectImageFormat(Uint8List bytes, {String? mimeType}) {
  // JPEG: 0xFF 0xD8
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'jpeg';
  }
  // PNG: 0x89 0x50 0x4E 0x47
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'png';
  }
  // HEIC/HEIF: ftyp ボックス（offset 4-7 が 'ftyp'）
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 && // 'f'
      bytes[5] == 0x74 && // 't'
      bytes[6] == 0x79 && // 'y'
      bytes[7] == 0x70) { // 'p'
    return 'heic';
  }
  // mimeType ヒント
  if (mimeType != null) {
    if (mimeType.contains('heic') || mimeType.contains('heif')) {
      return 'heic';
    }
    if (mimeType.contains('jpeg') || mimeType.contains('jpg')) {
      return 'jpeg';
    }
    if (mimeType.contains('png')) {
      return 'png';
    }
  }
  return 'unknown';
}

/// レシート画像前処理の抽象クラス
///
/// Mobile: HEIC/HEIF → JPEG 変換、向き補正、リサイズ
/// Web: パススルー（JPEG/PNG のみ受付のため不要）
abstract class ReceiptImagePreprocessor {
  /// 画像バイト列を OCR 向けに前処理する
  ///
  /// [mimeType] が分かる場合は渡す（不明時は null）。
  /// 前処理不要/非対応の場合は元のバイト列をそのまま返す。
  Future<PreprocessResult> preprocess(
    Uint8List bytes, {
    String? mimeType,
  });

  /// リソースの解放
  void dispose() {}
}
