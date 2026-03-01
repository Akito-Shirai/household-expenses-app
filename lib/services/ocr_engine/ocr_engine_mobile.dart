import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../models/ocr_token.dart';
import 'ocr_engine.dart';

/// ML Kit を使用したモバイル向けOCRエンジン
class MobileOcrEngine implements OcrEngine {
  TextRecognizer? _recognizer;

  TextRecognizer get _textRecognizer {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.japanese);
    return _recognizer!;
  }

  @override
  Future<List<OcrToken>> recognizeFromBytes(Uint8List imageBytes) async {
    File? tempFile;
    try {
      // ML Kit は File パスを要求するため一時ファイルに書き出す
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      tempFile = File('${Directory.systemTemp.path}/ocr_$timestamp.jpg');
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFile(tempFile);
      final recognized = await _textRecognizer.processImage(inputImage);

      final tokens = <OcrToken>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final rect = line.boundingBox;
          tokens.add(OcrToken(
            text: line.text,
            bbox: OcrBoundingBox(
              x: rect.left,
              y: rect.top,
              width: rect.width,
              height: rect.height,
            ),
            confidence: line.confidence,
          ));
        }
      }
      return tokens;
    } catch (e) {
      debugPrint('MobileOcrEngine: 認識エラー: $e');
      return [];
    } finally {
      // 一時ファイルを削除（プライバシー保護）
      try {
        if (tempFile != null && tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      } catch (_) {}
    }
  }

  @override
  bool get isAvailable {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}

OcrEngine createOcrEngine() => MobileOcrEngine();
