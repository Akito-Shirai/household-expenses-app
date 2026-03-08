import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import 'receipt_image_preprocessor.dart';

/// モバイル向け画像前処理
///
/// HEIC/HEIF → JPEG 変換、EXIF 向き補正、長辺リサイズ、品質正規化、
/// 簡易レシート領域 crop を行う。
class MobileImagePreprocessor implements ReceiptImagePreprocessor {
  /// OCR 用の長辺最大ピクセル数
  static const int maxLongSide = 2048;

  /// JPEG 出力品質（0-100）
  static const int jpegQuality = 85;

  /// crop 後の再エンコード品質（1回多くエンコードするため少し高め）
  static const int cropJpegQuality = 90;

  /// crop で残す最小面積比率（元画像に対して）
  ///
  /// これを下回る crop 結果はフォールバック（元画像を使用）する。
  static const double minCropAreaRatio = 0.15;

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
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxLongSide,
        minHeight: maxLongSide,
        quality: jpegQuality,
        format: CompressFormat.jpeg,
        autoCorrectionAngle: true,
        keepExif: false,
      );

      appliedSteps.add('format:$inputFormat→jpeg');
      appliedSteps.add('resize:max${maxLongSide}px');
      appliedSteps.add('quality:$jpegQuality');
      appliedSteps.add('exif:auto');

      // 簡易レシート領域 crop
      final cropResult = _autoCropReceipt(Uint8List.fromList(compressed));
      final Uint8List outputBytes;
      if (cropResult != null) {
        outputBytes = cropResult;
        appliedSteps.add('crop:auto');
      } else {
        outputBytes = Uint8List.fromList(compressed);
        appliedSteps.add('crop:skipped');
      }

      // dimensions を取得
      final dims = parseImageDimensions(outputBytes);

      debugPrint(
        'MobileImagePreprocessor: 前処理完了 '
        '${bytes.length}→${outputBytes.length} bytes '
        '${dims != null ? "${dims.width}x${dims.height}" : "unknown"} '
        '(${appliedSteps.join(", ")})',
      );

      return PreprocessResult(
        bytes: outputBytes,
        format: 'jpeg',
        converted: true,
        appliedSteps: appliedSteps,
        width: dims?.width,
        height: dims?.height,
      );
    } catch (e) {
      // 前処理失敗時は元のバイト列をそのまま返す（OCR は試行）
      debugPrint('MobileImagePreprocessor: 前処理失敗、元画像で続行: $e');
      final dims = parseImageDimensions(bytes);
      return PreprocessResult(
        bytes: bytes,
        format: inputFormat,
        converted: false,
        appliedSteps: ['error:$e'],
        width: dims?.width,
        height: dims?.height,
      );
    }
  }

  /// 簡易レシート領域 crop
  ///
  /// レシート（白い紙）の領域を検出し、背景を除去する。
  /// 1. JPEG をデコードしグレースケール化
  /// 2. 各行/列の平均輝度からコンテンツ領域を特定
  /// 3. 領域が元画像の [minCropAreaRatio] 未満なら crop しない（フォールバック）
  ///
  /// 失敗時は null を返す。
  Uint8List? _autoCropReceipt(Uint8List jpegBytes) {
    try {
      final decoded = img.decodeJpg(jpegBytes);
      if (decoded == null) return null;

      final width = decoded.width;
      final height = decoded.height;

      // 各行の平均輝度を計算
      final rowBrightness = List<double>.filled(height, 0);
      for (int y = 0; y < height; y++) {
        double sum = 0;
        for (int x = 0; x < width; x++) {
          final pixel = decoded.getPixel(x, y);
          sum += img.getLuminance(pixel);
        }
        rowBrightness[y] = sum / width;
      }

      // 各列の平均輝度を計算
      final colBrightness = List<double>.filled(width, 0);
      for (int x = 0; x < width; x++) {
        double sum = 0;
        for (int y = 0; y < height; y++) {
          final pixel = decoded.getPixel(x, y);
          sum += img.getLuminance(pixel);
        }
        colBrightness[x] = sum / height;
      }

      // コンテンツ領域を検出（輝度が閾値を超える行/列）
      // レシート = 白い紙 → 高輝度。背景 = 暗い面 → 低輝度
      const contentThreshold = 100.0; // 0-255 のグレースケール閾値
      const margin = 10; // crop 後のマージン（ピクセル）

      int top = 0;
      int bottom = height - 1;
      int left = 0;
      int right = width - 1;

      // 上端: 最初の高輝度行を探す
      for (int y = 0; y < height; y++) {
        if (rowBrightness[y] > contentThreshold) {
          top = y;
          break;
        }
      }

      // 下端: 最後の高輝度行を探す
      for (int y = height - 1; y >= 0; y--) {
        if (rowBrightness[y] > contentThreshold) {
          bottom = y;
          break;
        }
      }

      // 左端: 最初の高輝度列を探す
      for (int x = 0; x < width; x++) {
        if (colBrightness[x] > contentThreshold) {
          left = x;
          break;
        }
      }

      // 右端: 最後の高輝度列を探す
      for (int x = width - 1; x >= 0; x--) {
        if (colBrightness[x] > contentThreshold) {
          right = x;
          break;
        }
      }

      // マージンを適用
      top = (top - margin).clamp(0, height - 1);
      bottom = (bottom + margin).clamp(0, height - 1);
      left = (left - margin).clamp(0, width - 1);
      right = (right + margin).clamp(0, width - 1);

      final cropWidth = right - left + 1;
      final cropHeight = bottom - top + 1;

      // crop が元画像の最小面積比率未満ならスキップ
      final areaRatio = (cropWidth * cropHeight) / (width * height);
      if (areaRatio < minCropAreaRatio) {
        debugPrint(
          'MobileImagePreprocessor: crop スキップ '
          '(面積比率 ${(areaRatio * 100).toStringAsFixed(1)}% < '
          '${(minCropAreaRatio * 100).toStringAsFixed(0)}%)',
        );
        return null;
      }

      // ほぼ全体なら crop 不要
      if (areaRatio > 0.95) {
        return null;
      }

      // crop 実行
      final cropped = img.copyCrop(
        decoded,
        x: left,
        y: top,
        width: cropWidth,
        height: cropHeight,
      );

      debugPrint(
        'MobileImagePreprocessor: crop ${width}x$height → '
        '${cropped.width}x${cropped.height} '
        '(面積比率 ${(areaRatio * 100).toStringAsFixed(1)}%)',
      );

      return Uint8List.fromList(
        img.encodeJpg(cropped, quality: cropJpegQuality),
      );
    } catch (e) {
      debugPrint('MobileImagePreprocessor: crop 失敗: $e');
      return null;
    }
  }

  @override
  void dispose() {}
}

ReceiptImagePreprocessor createImagePreprocessor() =>
    MobileImagePreprocessor();
