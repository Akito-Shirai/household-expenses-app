import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../receipt_ocr_service.dart';
import 'image_pick_adapter.dart';

/// 画像長辺の上限（リサイズ用）
const int _maxImageDimension = 2048;

/// Web向け画像取得アダプタ（形式/サイズ検証付き）
///
/// ブラウザの file input 経由で画像を取得し、以下を検証する:
/// - ファイルサイズ: 10MB 以下（readAsBytes 前に XFile.length で事前チェック）
/// - ファイル形式: JPEG/PNG のみ（先頭バイトで判定）
class WebImagePickAdapter implements ImagePickAdapter {
  @override
  Future<PickImageResult> pickImage(ImageSource source) async {
    // ファイル選択
    XFile? xFile;
    try {
      final picker = ImagePicker();
      xFile = await picker.pickImage(
        source: ImageSource.gallery, // Webではギャラリーのみ
        maxWidth: _maxImageDimension.toDouble(),
        maxHeight: _maxImageDimension.toDouble(),
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('WebImagePickAdapter: ファイル選択エラー: $e');
      return classifyPickException(e, isWeb: true);
    }

    if (xFile == null) {
      return const PickImageResult(PickImageStatus.canceled);
    }

    // ファイルサイズ事前チェック（readAsBytes 前にメモリ負荷を回避）
    try {
      final fileLength = await xFile.length();
      if (fileLength > maxPickFileSizeBytes) {
        final sizeMB = (fileLength / (1024 * 1024)).toStringAsFixed(1);
        return PickImageResult(
          PickImageStatus.fileTooLarge,
          errorDetail: '画像サイズが大きすぎます（${sizeMB}MB）。10MB以下の画像を選択してください。',
        );
      }
    } catch (_) {
      // length() 未対応の場合は readAsBytes 後にチェック
    }

    // バイト列を読み取り
    final Uint8List bytes;
    try {
      bytes = await xFile.readAsBytes();
    } catch (e) {
      debugPrint('WebImagePickAdapter: ファイル読み込みエラー: $e');
      return PickImageResult(
        PickImageStatus.fileReadError,
        errorDetail: PickImageStatus.fileReadError.defaultMessage,
      );
    }

    // バイト列検証（サイズ + 形式）
    final validation = validateImageBytes(bytes);
    if (validation != null) return validation;

    return PickImageResult(PickImageStatus.success, imageBytes: bytes);
  }

  @override
  void dispose() {}
}

ImagePickAdapter createImagePickAdapter() => WebImagePickAdapter();
