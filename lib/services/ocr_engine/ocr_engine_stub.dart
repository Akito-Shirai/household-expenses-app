import 'dart:typed_data';

import '../../models/ocr_token.dart';
import 'ocr_engine.dart';

/// スタブ実装（サポート外プラットフォーム向け）
///
/// 条件付きインポートでMobile/Webどちらにも該当しない場合に使用される。
class StubOcrEngine implements OcrEngine {
  @override
  Future<List<OcrToken>> recognizeFromBytes(Uint8List imageBytes) async => [];

  @override
  bool get isAvailable => false;

  @override
  void dispose() {}
}

OcrEngine createOcrEngine() => StubOcrEngine();
