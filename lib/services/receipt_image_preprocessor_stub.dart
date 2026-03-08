import 'dart:typed_data';

import 'receipt_image_preprocessor.dart';

/// スタブ/Web 向けパススルー実装
///
/// Web では JPEG/PNG のみ受付のため前処理不要。
/// 条件付きインポートで Mobile 以外はこちらが使われる。
class StubImagePreprocessor implements ReceiptImagePreprocessor {
  @override
  Future<PreprocessResult> preprocess(
    Uint8List bytes, {
    String? mimeType,
  }) async {
    // パススルー: 変換なしでそのまま返す
    final format = detectImageFormat(bytes, mimeType: mimeType);
    final dims = parseImageDimensions(bytes);
    return PreprocessResult(
      bytes: bytes,
      format: format,
      converted: false,
      appliedSteps: const [],
      width: dims?.width,
      height: dims?.height,
    );
  }

  @override
  void dispose() {}
}

ReceiptImagePreprocessor createImagePreprocessor() => StubImagePreprocessor();
