import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import '../../models/ocr_token.dart';
import 'ocr_engine.dart';

// ─── tesseract.js v5 JS interop 定義 ───

/// tesseract.js v5 の createWorker
///
/// 第1引数: 言語コード（例: 'jpn'）
/// 第2引数: OEM（OCR Engine Mode）— 省略時は LSTM (1) がデフォルト
@JS('Tesseract.createWorker')
external JSPromise<_TesseractWorker> _createTesseractWorker(JSString lang);

extension type _TesseractWorker._(JSObject _) implements JSObject {
  external JSPromise<_RecognizeResult> recognize(JSAny image);
  external JSPromise terminate();
}

extension type _RecognizeResult._(JSObject _) implements JSObject {
  external _RecognizeData get data;
}

extension type _RecognizeData._(JSObject _) implements JSObject {
  external JSString get text;
  external JSArray<_RecognizeLine> get lines;
}

extension type _RecognizeLine._(JSObject _) implements JSObject {
  external JSString get text;
  external _BBox get bbox;
  external JSNumber get confidence;
}

extension type _BBox._(JSObject _) implements JSObject {
  external JSNumber get x0;
  external JSNumber get y0;
  external JSNumber get x1;
  external JSNumber get y1;
}

/// Blobコンストラクタ（Uint8Array → Blob 変換用）
@JS('Blob')
extension type _JSBlob._(JSObject _) implements JSObject {
  external _JSBlob(JSArray<JSAny> blobParts);
}

// ─── Web OCR エンジン ───

/// tesseract.js を使用したWeb向けOCRエンジン
///
/// ブラウザ内で完結し、画像データを外部に送信しない。
/// 初回利用時に日本語言語データをダウンロードする（約15MB）。
class WebOcrEngine implements OcrEngine {
  _TesseractWorker? _worker;

  /// ワーカーを初期化（遅延・キャッシュ）
  ///
  /// OEM はデフォルト（LSTM=1）を使用。
  /// 初回呼び出し時に日本語言語データをダウンロードする。
  Future<_TesseractWorker> _getWorker() async {
    if (_worker != null) return _worker!;
    _worker = await _createTesseractWorker('jpn'.toJS).toDart;
    return _worker!;
  }

  @override
  Future<List<OcrToken>> recognizeFromBytes(Uint8List imageBytes) async {
    try {
      final worker = await _getWorker();

      // Uint8List → Blob に変換（tesseract.js はブラウザ環境で Blob を受け付ける）
      final jsBytes = imageBytes.toJS;
      final blob = _JSBlob(<JSAny>[jsBytes].toJS);

      final result = await worker.recognize(blob).toDart;
      final lines = result.data.lines;

      final tokens = <OcrToken>[];
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final text = line.text.toDart.trim();
        if (text.isEmpty) continue;

        final bbox = line.bbox;
        final x0 = bbox.x0.toDartDouble;
        final y0 = bbox.y0.toDartDouble;
        final x1 = bbox.x1.toDartDouble;
        final y1 = bbox.y1.toDartDouble;
        // tesseract.js は信頼度を 0〜100 で返す
        final confidence = line.confidence.toDartDouble / 100.0;

        tokens.add(OcrToken(
          text: text,
          bbox: OcrBoundingBox(
            x: x0,
            y: y0,
            width: x1 - x0,
            height: y1 - y0,
          ),
          confidence: confidence.clamp(0.0, 1.0),
        ));
      }
      return tokens;
    } catch (e) {
      debugPrint('WebOcrEngine: 認識エラー: $e');
      return [];
    }
  }

  @override
  bool get isAvailable => true;

  @override
  void dispose() {
    if (_worker != null) {
      _worker!.terminate();
      _worker = null;
    }
  }
}

OcrEngine createOcrEngine() => WebOcrEngine();
