import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'receipt_image_preprocessor.dart';

/// モバイル向け画像前処理
///
/// HEIC/HEIF → JPEG 変換、EXIF 向き補正、長辺リサイズ、品質正規化を行う。
class MobileImagePreprocessor implements ReceiptImagePreprocessor {
  /// OCR 用の長辺最大ピクセル数
  static const int maxLongSide = 2048;

  /// JPEG 出力品質（0-100）
  static const int jpegQuality = 85;

  @override
  Future<PreprocessResult> preprocess(
    Uint8List bytes, {
    String? mimeType,
  }) async {
    final appliedSteps = <String>[];
    final inputFormat = detectImageFormat(bytes, mimeType: mimeType);

    try {
      // flutter_image_compress は以下を自動処理:
      // - HEIC/HEIF → JPEG 変換
      // - EXIF orientation 補正
      // - リサイズ（指定サイズ以下に）
      // - 品質正規化
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxLongSide,
        minHeight: maxLongSide,
        quality: jpegQuality,
        format: CompressFormat.jpeg,
        // EXIF 向き補正は自動適用
        autoCorrectionAngle: true,
        keepExif: false,
      );

      appliedSteps.add('format:$inputFormat→jpeg');
      appliedSteps.add('resize:max${maxLongSide}px');
      appliedSteps.add('quality:$jpegQuality');
      appliedSteps.add('exif:auto');

      debugPrint(
        'MobileImagePreprocessor: 前処理完了 '
        '${bytes.length}→${result.length} bytes '
        '(${appliedSteps.join(", ")})',
      );

      return PreprocessResult(
        bytes: Uint8List.fromList(result),
        format: 'jpeg',
        converted: true,
        appliedSteps: appliedSteps,
      );
    } catch (e) {
      // 前処理失敗時は元のバイト列をそのまま返す（OCR は試行）
      debugPrint('MobileImagePreprocessor: 前処理失敗、元画像で続行: $e');
      return PreprocessResult(
        bytes: bytes,
        format: inputFormat,
        converted: false,
        appliedSteps: ['error:$e'],
      );
    }
  }

  @override
  void dispose() {}
}

ReceiptImagePreprocessor createImagePreprocessor() =>
    MobileImagePreprocessor();
