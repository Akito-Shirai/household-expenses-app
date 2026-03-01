import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../models/receipt_ocr_result.dart';

/// スコア付き抽出結果（内部使用）
class ScoredResult<T> {
  final T value;
  final double score;
  const ScoredResult(this.value, this.score);
}

/// 画像取得結果の種別
enum PickImageStatus {
  /// 画像取得成功
  success,

  /// ユーザーがキャンセル
  canceled,

  /// 権限拒否（カメラ/フォトライブラリ）
  permissionDenied,

  /// その他のエラー
  failed,
}

/// 画像取得の結果
class PickImageResult {
  final PickImageStatus status;
  final File? file;
  const PickImageResult(this.status, [this.file]);
}

/// レシートOCRサービス（オンデバイス処理、画像非送信）
class ReceiptOcrService {
  const ReceiptOcrService._();

  /// 画像長辺の上限（リサイズ用）
  static const int _maxImageDimension = 2048;

  /// OCR処理のタイムアウト（秒）
  static const int _timeoutSeconds = 10;

  /// 店名候補の検索対象行数（上部N行）
  static const int _merchantSearchLines = 5;

  /// 1日あたりのOCR実行上限（ソフトリミット）
  static const int dailyLimit = 30;

  /// 今日の実行回数（アプリ再起動でリセット）
  static int _todayCount = 0;
  static DateTime _lastResetDate = DateTime.now();

  /// 店名の除外キーワード
  static const List<String> merchantExcludeKeywords = [
    '〒', 'TEL', 'tel', 'Tel', 'FAX', 'fax',
    '東京都', '大阪府', '北海道', '京都府',
    '市', '区', '町', '村', '番地', '号',
    '担当', 'No.', 'NO.', 'レジ', '会員',
    '領収', '明細', '税', 'http', 'www',
  ];

  /// 合計金額の優先キーワード
  static const List<String> totalPriorityKeywords = [
    '合計', 'ご請求', 'お会計', '税込',
    '請求額', '決済額', '利用金額', 'TOTAL', 'Total',
  ];

  /// 合計金額の除外キーワード
  static const List<String> totalExcludeKeywords = [
    '小計', 'お釣り', 'おつり', '預り', 'お預り',
    'お支払', 'ポイント', '手数料', '値引', '割引', '返品',
    '内税', '外税', '消費税', '税額',
  ];

  /// 日付パターン（金額誤認防止）
  static final RegExp _datePattern =
      RegExp(r'\d{4}[/\-\.]\d{1,2}[/\-\.]\d{1,2}');

  // ─── 1日上限チェック ───

  /// 1日上限に達しているか
  static bool get isDailyLimitReached {
    _resetCountIfNewDay();
    return _todayCount >= dailyLimit;
  }

  static void _resetCountIfNewDay() {
    final now = DateTime.now();
    if (now.day != _lastResetDate.day ||
        now.month != _lastResetDate.month ||
        now.year != _lastResetDate.year) {
      _todayCount = 0;
      _lastResetDate = now;
    }
  }

  static void _incrementCount() {
    _resetCountIfNewDay();
    _todayCount++;
  }

  // ─── 画像取得 ───

  /// カメラまたはライブラリから画像を選択（結果型で理由を返す）
  static Future<PickImageResult> pickImage(ImageSource source) async {
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
      return PickImageResult(PickImageStatus.success, File(xFile.path));
    } on PlatformException catch (e) {
      debugPrint('ReceiptOcrService: 画像取得エラー: $e');
      // image_picker は権限拒否時に PlatformException を投げる
      if (e.code == 'camera_access_denied' ||
          e.code == 'photo_access_denied') {
        return const PickImageResult(PickImageStatus.permissionDenied);
      }
      return const PickImageResult(PickImageStatus.failed);
    } catch (e) {
      debugPrint('ReceiptOcrService: 画像取得エラー: $e');
      return const PickImageResult(PickImageStatus.failed);
    }
  }

  // ─── OCR実行 ───

  /// 画像ファイルからテキストを認識しOCR結果を抽出
  /// 処理完了後、一時画像ファイルを削除する
  static Future<ReceiptOcrResult?> processImage(File imageFile) async {
    _incrementCount();
    final textRecognizer = TextRecognizer(
      script: TextRecognitionScript.japanese,
    );
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await textRecognizer
          .processImage(inputImage)
          .timeout(Duration(seconds: _timeoutSeconds));

      if (recognizedText.text.isEmpty) {
        debugPrint('ReceiptOcrService: OCRテキスト空');
        return null;
      }

      return extractFromText(recognizedText.text);
    } catch (e) {
      debugPrint('ReceiptOcrService: OCR処理エラー: $e');
      return null;
    } finally {
      textRecognizer.close();
      // H-3: 一時画像を削除（プライバシー保護）
      _deleteTempImage(imageFile);
    }
  }

  /// 一時画像ファイルを安全に削除
  static void _deleteTempImage(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
        debugPrint('ReceiptOcrService: 一時画像を削除しました');
      }
    } catch (e) {
      debugPrint('ReceiptOcrService: 一時画像削除エラー: $e');
    }
  }

  // ─── 抽出ロジック（純粋関数、テスト可能） ───

  /// OCRテキストから店名・合計金額を抽出
  @visibleForTesting
  static ReceiptOcrResult extractFromText(String ocrText) {
    final lines = ocrText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const ReceiptOcrResult(confidence: 0.0);
    }

    final merchantResult = extractMerchant(lines);
    final totalResult = extractTotal(lines);

    final confidence = calculateConfidence(merchantResult, totalResult);

    return ReceiptOcrResult(
      merchantName: merchantResult?.value,
      totalAmount: totalResult?.value,
      confidence: confidence,
    );
  }

  // ─── 店名抽出 ───

  /// 上位行からスコアリングで店名を抽出
  @visibleForTesting
  static ScoredResult<String>? extractMerchant(List<String> lines) {
    final searchLines = lines.take(_merchantSearchLines).toList();
    double bestScore = 0;
    String? bestCandidate;

    for (int i = 0; i < searchLines.length; i++) {
      final line = searchLines[i];

      // 文字長チェック（2〜30文字）
      if (line.length < 2 || line.length > 30) continue;

      // 除外語チェック
      if (merchantExcludeKeywords.any((kw) => line.contains(kw))) continue;

      // 記号過多チェック（半分以上が非日本語・非英数字なら除外）
      final symbolCount =
          line.runes.where((r) => !_isJapaneseOrAlphanumeric(r)).length;
      if (symbolCount > line.runes.length / 2) continue;

      double score = 0;

      // 上位行ほどスコア加算
      score += (searchLines.length - i) / searchLines.length;

      // 日本語を含む行を優先
      if (line.runes.any((r) => _isJapanese(r))) {
        score += 0.3;
      }

      // 店舗系キーワードを含む行を優先
      if (RegExp(r'(店|ストア|マート|スーパー|コンビニ|薬局|ドラッグ)')
          .hasMatch(line)) {
        score += 0.2;
      }

      if (score > bestScore) {
        bestScore = score;
        bestCandidate = line;
      }
    }

    if (bestCandidate == null) return null;
    return ScoredResult(bestCandidate, bestScore);
  }

  // ─── 合計金額抽出 ───

  /// キーワード＋正規表現で合計金額を抽出
  @visibleForTesting
  static ScoredResult<int>? extractTotal(List<String> lines) {
    final amountRegex = RegExp(r'[¥￥]\s*([0-9,]+)|([0-9,]+)\s*円|([0-9,]{3,})');

    double bestScore = -1;
    int? bestAmount;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 除外キーワードを含む行はスキップ
      if (totalExcludeKeywords.any((kw) => line.contains(kw))) continue;

      // 日付のみの行はスキップ（金額との誤認防止）
      if (_datePattern.hasMatch(line) &&
          !totalPriorityKeywords.any((kw) => line.contains(kw))) {
        continue;
      }

      // 優先キーワードの有無
      final hasPriorityKeyword =
          totalPriorityKeywords.any((kw) => line.contains(kw));

      // 金額を抽出
      final matches = amountRegex.allMatches(line);
      for (final match in matches) {
        final amountStr =
            (match.group(1) ?? match.group(2) ?? match.group(3))
                ?.replaceAll(',', '');
        if (amountStr == null || amountStr.isEmpty) continue;

        final amount = int.tryParse(amountStr);
        if (amount == null || amount <= 0) continue;
        if (amount > 1000000) continue;

        double score = 0;

        // 優先キーワード近傍
        if (hasPriorityKeyword) score += 1.0;

        // 文書下部ほどスコア加算
        score += i / lines.length * 0.5;

        // 金額規模ボーナス
        score += (amount / 100000).clamp(0, 0.3);

        if (score > bestScore) {
          bestScore = score;
          bestAmount = amount;
        }
      }
    }

    if (bestAmount == null) return null;
    return ScoredResult(bestAmount, bestScore);
  }

  // ─── 信頼度計算 ───

  /// 店名・合計の抽出スコアから信頼度を算出
  @visibleForTesting
  static double calculateConfidence(
    ScoredResult<String>? merchant,
    ScoredResult<int>? total,
  ) {
    double confidence = 0;

    if (merchant != null) {
      confidence += merchant.score.clamp(0, 1) * 0.4;
    }
    if (total != null) {
      confidence += (total.score.clamp(0, 2) / 2) * 0.6;
    }

    return confidence.clamp(0, 1).toDouble();
  }

  // ─── ユーティリティ ───

  static bool _isJapanese(int rune) {
    return (rune >= 0x3040 && rune <= 0x309F) || // ひらがな
        (rune >= 0x30A0 && rune <= 0x30FF) || // カタカナ
        (rune >= 0x4E00 && rune <= 0x9FFF); // CJK漢字
  }

  static bool _isJapaneseOrAlphanumeric(int rune) {
    return _isJapanese(rune) ||
        (rune >= 0x30 && rune <= 0x39) || // 数字
        (rune >= 0x41 && rune <= 0x5A) || // 大文字
        (rune >= 0x61 && rune <= 0x7A) || // 小文字
        (rune >= 0xFF10 && rune <= 0xFF19) || // 全角数字
        (rune >= 0xFF21 && rune <= 0xFF3A) || // 全角大文字
        (rune >= 0xFF41 && rune <= 0xFF5A) || // 全角小文字
        rune == 0x20; // スペース
  }
}
