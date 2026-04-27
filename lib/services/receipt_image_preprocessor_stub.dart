import 'package:flutter/foundation.dart';

import 'receipt_image_preprocessor.dart';

/// スタブ/Web 向けパススルー実装
///
/// Web では JPEG/PNG のみ受付のため画像変換は行わず、
/// 抽出側の誤採用ガード（伝票番号・電話番号フィルタ等）に依存する。
/// 条件付きインポートで Mobile 以外はこちらが使われる。
///
/// Step21: パススルー時も `pass_through` を appliedSteps に記録し、
/// ログから「Web 経路で前処理が未適用である」ことを識別できるようにする。
class StubImagePreprocessor implements ReceiptImagePreprocessor {
  @override
  Future<PreprocessResult> preprocess(
    Uint8List bytes, {
    String? mimeType,
  }) async {
    // パススルー: 変換なしでそのまま返す
    final format = detectImageFormat(bytes, mimeType: mimeType);
    final dims = parseImageDimensions(bytes);
    if (kDebugMode) {
      debugPrint(
        'StubImagePreprocessor: pass-through '
        'format=$format bytes=${bytes.length} '
        'dims=${dims != null ? "${dims.width}x${dims.height}" : "unknown"} '
        'note=guard_via_extractor',
      );
    }
    return PreprocessResult(
      bytes: bytes,
      format: format,
      converted: false,
      appliedSteps: const ['pass_through'],
      width: dims?.width,
      height: dims?.height,
    );
  }

  @override
  void dispose() {}
}

ReceiptImagePreprocessor createImagePreprocessor() => StubImagePreprocessor();
