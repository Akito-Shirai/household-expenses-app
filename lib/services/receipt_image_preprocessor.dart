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

  /// 処理後の画像幅（ピクセル、取得できない場合は null）
  final int? width;

  /// 処理後の画像高さ（ピクセル、取得できない場合は null）
  final int? height;

  const PreprocessResult({
    required this.bytes,
    required this.format,
    this.converted = false,
    this.appliedSteps = const [],
    this.width,
    this.height,
  });

  /// dimensions の文字列表現（ログ用）
  String get dimensionsString =>
      width != null && height != null ? '${width}x$height' : 'unknown';
}

/// JPEG/PNG/HEIC のヘッダーから画像サイズを取得するユーティリティ
///
/// 画像全体のデコード不要。ヘッダーのみパースする軽量実装。
/// 対応フォーマット: JPEG (SOF0/SOF2), PNG (IHDR), HEIC/HEIF (ispe ボックス)
/// 取得できない場合は null を返す。
({int width, int height})? parseImageDimensions(Uint8List bytes) {
  if (bytes.length < 4) return null;

  // JPEG: SOF0 (0xFF 0xC0) or SOF2 (0xFF 0xC2) マーカーを探す
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return _parseJpegDimensions(bytes);
  }

  // PNG: IHDR チャンクから取得
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes.length >= 24) {
    final width = (bytes[16] << 24) |
        (bytes[17] << 16) |
        (bytes[18] << 8) |
        bytes[19];
    final height = (bytes[20] << 24) |
        (bytes[21] << 16) |
        (bytes[22] << 8) |
        bytes[23];
    return (width: width, height: height);
  }

  // HEIC/HEIF: ftyp ボックス検出 → ispe ボックスから取得
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 && // 'f'
      bytes[5] == 0x74 && // 't'
      bytes[6] == 0x79 && // 'y'
      bytes[7] == 0x70) { // 'p'
    return _parseHeicDimensions(bytes);
  }

  return null;
}

/// JPEG の SOF マーカーからサイズを取得
({int width, int height})? _parseJpegDimensions(Uint8List bytes) {
  int offset = 2; // SOI (0xFF 0xD8) の後から探索
  while (offset < bytes.length - 1) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    // SOF0 (0xC0) または SOF2 (0xC2) = フレームヘッダー
    if (marker == 0xC0 || marker == 0xC2) {
      if (offset + 9 < bytes.length) {
        // SOF 構造: FF C0 [length 2B] [precision 1B] [height 2B] [width 2B]
        final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
        final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        return (width: width, height: height);
      }
      return null;
    }
    // それ以外のマーカー → length フィールドでスキップ
    if (offset + 3 < bytes.length) {
      final segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
      offset += 2 + segmentLength;
    } else {
      break;
    }
  }
  return null;
}

/// HEIC/HEIF (ISOBMFF) の ispe ボックスからサイズを取得
///
/// ISOBMFF 構造: ftyp → meta → iprp → ipco → ispe
/// ispe ボックス: [size 4B][type 4B='ispe'][version 1B][flags 3B][width 4B][height 4B]
/// 軽量パース: バイト列全体を走査して全 'ispe' を収集し、最大面積のものを返す。
/// HEIC はサムネイルと本体で複数の ispe を持つため、先頭固定だとサムネイル寸法になりうる。
({int width, int height})? _parseHeicDimensions(Uint8List bytes) {
  // 'ispe' = 0x69 0x73 0x70 0x65
  // ispe ボックスの最小サイズ: 4(size) + 4(type) + 4(ver+flags) + 4(w) + 4(h) = 20
  int bestWidth = 0;
  int bestHeight = 0;
  int bestArea = 0;

  for (int i = 0; i <= bytes.length - 20; i++) {
    if (bytes[i + 4] == 0x69 && // 'i'
        bytes[i + 5] == 0x73 && // 's'
        bytes[i + 6] == 0x70 && // 'p'
        bytes[i + 7] == 0x65) { // 'e'
      // ボックスサイズの妥当性チェック
      final boxSize = (bytes[i] << 24) |
          (bytes[i + 1] << 16) |
          (bytes[i + 2] << 8) |
          bytes[i + 3];
      if (boxSize < 20 || boxSize > 100) continue; // ispe は通常 20 バイト

      final width = (bytes[i + 12] << 24) |
          (bytes[i + 13] << 16) |
          (bytes[i + 14] << 8) |
          bytes[i + 15];
      final height = (bytes[i + 16] << 24) |
          (bytes[i + 17] << 16) |
          (bytes[i + 18] << 8) |
          bytes[i + 19];

      // 妥当性チェック（0 や異常値を除外）
      if (width > 0 && width <= 65535 && height > 0 && height <= 65535) {
        final area = width * height;
        if (area > bestArea) {
          bestWidth = width;
          bestHeight = height;
          bestArea = area;
        }
      }
    }
  }

  if (bestArea > 0) {
    return (width: bestWidth, height: bestHeight);
  }
  return null;
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
