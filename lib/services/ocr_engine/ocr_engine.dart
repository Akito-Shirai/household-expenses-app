import 'dart:typed_data';

import '../../models/ocr_token.dart';

export 'ocr_engine_factory.dart';

/// プラットフォーム非依存のOCRエンジン抽象クラス
///
/// Mobile: ML Kit、Web: tesseract.js で実装される。
/// 画像は [Uint8List] で受け渡し、プラットフォーム間でI/Fを統一する。
abstract class OcrEngine {
  /// 画像バイト列からテキストを認識し、[OcrToken] のリストを返す
  ///
  /// 認識失敗時は空リストを返す（例外は投げない）。
  Future<List<OcrToken>> recognizeFromBytes(Uint8List imageBytes);

  /// エンジンが利用可能かどうか
  bool get isAvailable;

  /// リソースの解放
  void dispose();
}
