import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../receipt_ocr_service.dart';
import 'image_pick_adapter.dart';

/// 画像長辺の上限（リサイズ用）
const int _maxImageDimension = 2048;

/// Mobile向け画像取得アダプタ（ImagePicker + 権限チェック）
class MobileImagePickAdapter implements ImagePickAdapter {
  @override
  Future<PickImageResult> pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: source,
        maxWidth: _maxImageDimension.toDouble(),
        maxHeight: _maxImageDimension.toDouble(),
        imageQuality: 85,
      );
      if (xFile == null) {
        return const PickImageResult(PickImageStatus.canceled);
      }
      // プラットフォーム非依存: XFile からバイト列を読み取る
      final bytes = await xFile.readAsBytes();
      return PickImageResult(PickImageStatus.success, imageBytes: bytes);
    } on PlatformException catch (e) {
      debugPrint('MobileImagePickAdapter: 画像取得エラー: $e');
      if (e.code == 'camera_access_denied' ||
          e.code == 'photo_access_denied') {
        return const PickImageResult(PickImageStatus.permissionDenied);
      }
      return const PickImageResult(PickImageStatus.unknown,
          errorDetail: '画像取得に失敗しました。再試行または手入力で続けてください。');
    } catch (e) {
      debugPrint('MobileImagePickAdapter: 画像取得エラー: $e');
      return const PickImageResult(PickImageStatus.unknown,
          errorDetail: '画像取得に失敗しました。再試行または手入力で続けてください。');
    }
  }

  @override
  void dispose() {}
}

ImagePickAdapter createImagePickAdapter() => MobileImagePickAdapter();
