import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../receipt_ocr_service.dart';

export 'image_pick_adapter_factory.dart';

/// プラットフォーム非依存の画像取得アダプタ抽象クラス
///
/// Mobile: ImagePicker + 権限チェック、Web: ファイル形式/サイズ検証付き で実装される。
/// 失敗時は [PickImageResult] で種別を返し、UIでの分岐を可能にする。
abstract class ImagePickAdapter {
  /// 画像を取得する
  ///
  /// [source] はカメラまたはギャラリー。Webではギャラリーのみサポート。
  Future<PickImageResult> pickImage(ImageSource source);

  /// リソースの解放
  void dispose();
}

// ─── 共通ヘルパー（テスト可能な純粋関数） ───

/// ファイルサイズ上限（10MB）
const int maxPickFileSizeBytes = 10 * 1024 * 1024;

/// ファイル選択時の例外を [PickImageStatus] に変換
///
/// Web/Mobile 共通で使用。テスト可能な純粋関数。
PickImageResult classifyPickException(Object error, {bool isWeb = false}) {
  if (error is PlatformException) {
    if (error.code == 'camera_access_denied' ||
        error.code == 'photo_access_denied') {
      return const PickImageResult(PickImageStatus.permissionDenied);
    }
    if (isWeb) {
      return PickImageResult(
        PickImageStatus.browserBlocked,
        errorDetail: PickImageStatus.browserBlocked.defaultMessage,
      );
    }
  }
  if (isWeb) {
    return PickImageResult(
      PickImageStatus.browserBlocked,
      errorDetail: PickImageStatus.browserBlocked.defaultMessage,
    );
  }
  return PickImageResult(
    PickImageStatus.unknown,
    errorDetail: PickImageStatus.unknown.defaultMessage,
  );
}

/// バイト列を検証し、問題があれば失敗 [PickImageResult] を返す
///
/// 正常時は null を返す。テスト可能な純粋関数。
PickImageResult? validateImageBytes(Uint8List bytes) {
  // サイズチェック
  if (bytes.length > maxPickFileSizeBytes) {
    final sizeMB = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
    return PickImageResult(
      PickImageStatus.fileTooLarge,
      errorDetail: '画像サイズが大きすぎます（${sizeMB}MB）。10MB以下の画像を選択してください。',
    );
  }
  // 形式チェック（先頭バイト）
  if (!isValidImageFormat(bytes)) {
    return PickImageResult(
      PickImageStatus.unsupportedFormat,
      errorDetail: PickImageStatus.unsupportedFormat.defaultMessage,
    );
  }
  return null;
}

/// 先頭バイト（magic bytes）で JPEG/PNG を判定
bool isValidImageFormat(Uint8List bytes) {
  if (bytes.length < 4) return false;
  // JPEG: 0xFF 0xD8
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
  // PNG: 0x89 0x50 0x4E 0x47
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  return false;
}
