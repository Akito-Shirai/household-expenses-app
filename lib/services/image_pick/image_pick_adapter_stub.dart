import 'package:image_picker/image_picker.dart';

import '../receipt_ocr_service.dart';
import 'image_pick_adapter.dart';

/// スタブ実装（サポート外プラットフォーム向け）
///
/// 条件付きインポートでMobile/Webどちらにも該当しない場合に使用される。
class StubImagePickAdapter implements ImagePickAdapter {
  @override
  Future<PickImageResult> pickImage(ImageSource source) async {
    return const PickImageResult(PickImageStatus.unknown,
        errorDetail: 'このプラットフォームでは画像取得がサポートされていません');
  }

  @override
  void dispose() {}
}

ImagePickAdapter createImagePickAdapter() => StubImagePickAdapter();
