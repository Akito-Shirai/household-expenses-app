import 'ocr_engine.dart';

import 'ocr_engine_stub.dart'
    if (dart.library.io) 'ocr_engine_mobile.dart'
    if (dart.library.js_interop) 'ocr_engine_web.dart' as platform;

/// プラットフォーム別にOCRエンジンを生成するファクトリ
OcrEngine createOcrEngine() => platform.createOcrEngine();
