import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/ocr_token.dart';
import '../models/receipt_ocr_result.dart';
import 'ocr_engine/ocr_engine.dart';

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

/// 画像取得の結果（プラットフォーム非依存: Uint8List）
class PickImageResult {
  final PickImageStatus status;
  final Uint8List? imageBytes;
  const PickImageResult(this.status, [this.imageBytes]);
}

/// レシートOCRサービス（オンデバイス処理、画像非送信）
///
/// 3層構成:
///   - OcrEngine（インフラ層）: プラットフォーム別のOCR処理
///   - 抽出ロジック（純粋関数）: テキスト/トークンからの情報抽出
///   - ReceiptOcrService（オーケストレーション）: 画像取得→OCR→抽出の統合
class ReceiptOcrService {
  const ReceiptOcrService._();

  /// 画像長辺の上限（リサイズ用）
  static const int _maxImageDimension = 2048;

  /// OCR処理のタイムアウト（秒）
  static const int timeoutSeconds = 12;

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

  /// 和暦日付パターン（令和/平成 + 数字）
  static final RegExp _warekiPattern =
      RegExp(r'(令和|平成|昭和)\s*\d{1,2}年');

  /// 連番パターン（10桁以上の数字列 → レシート番号等）
  static final RegExp _serialNumberPattern = RegExp(r'\d{10,}');

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
      // プラットフォーム非依存: XFile からバイト列を読み取る
      final bytes = await xFile.readAsBytes();
      return PickImageResult(PickImageStatus.success, bytes);
    } on PlatformException catch (e) {
      debugPrint('ReceiptOcrService: 画像取得エラー: $e');
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

  // ─── OCR実行（Engine経由） ───

  /// 画像バイト列からOCRを実行し結果を抽出
  ///
  /// [engine] はプラットフォーム別の OcrEngine 実装。
  /// 一時ファイルの管理は Engine 側で行う。
  static Future<ReceiptOcrResult?> processImageBytes(
    Uint8List imageBytes,
    OcrEngine engine,
  ) async {
    _incrementCount();
    try {
      final tokens = await engine
          .recognizeFromBytes(imageBytes)
          .timeout(Duration(seconds: timeoutSeconds));

      if (tokens.isEmpty) {
        debugPrint('ReceiptOcrService: OCRトークン空');
        return null;
      }

      // トークンからテキストを結合して抽出（bbox版は Step13-D で追加）
      return extractFromTokens(tokens);
    } catch (e) {
      debugPrint('ReceiptOcrService: OCR処理エラー: $e');
      return null;
    }
  }

  // ─── 抽出ロジック（純粋関数、テスト可能） ───

  /// OcrToken リストから店名・合計金額を抽出
  ///
  /// bbox データがある場合は位置・サイズ情報を活用して精度を向上。
  /// bbox がない場合はテキストベースのフォールバックを使用。
  @visibleForTesting
  static ReceiptOcrResult extractFromTokens(List<OcrToken> tokens) {
    final lines = tokens
        .map((t) => t.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const ReceiptOcrResult(confidence: 0.0);
    }

    // bbox が利用可能か判定
    final hasBbox = tokens.any((t) => t.bbox != null);

    final ScoredResult<String>? merchantResult;
    final ScoredResult<int>? totalResult;

    if (hasBbox) {
      merchantResult = extractMerchantFromTokens(tokens);
      totalResult = extractTotalFromTokens(tokens);
    } else {
      merchantResult = extractMerchant(lines);
      totalResult = extractTotal(lines);
    }

    final confidence = calculateConfidence(merchantResult, totalResult);

    return ReceiptOcrResult(
      merchantName: merchantResult?.value,
      totalAmount: totalResult?.value,
      confidence: confidence,
    );
  }

  /// OCRテキストから店名・合計金額を抽出（後方互換）
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

      // 日付行はスキップ（金額との誤認防止）
      if (_datePattern.hasMatch(line) &&
          !totalPriorityKeywords.any((kw) => line.contains(kw))) {
        continue;
      }

      // 和暦日付行はスキップ
      if (_warekiPattern.hasMatch(line) &&
          !totalPriorityKeywords.any((kw) => line.contains(kw))) {
        continue;
      }

      // 連番（10桁以上）のみの行はスキップ（レシート番号等）
      if (_serialNumberPattern.hasMatch(line) &&
          !line.contains('¥') &&
          !line.contains('￥') &&
          !line.contains('円')) {
        // 金額記号がなく連番が含まれる → 注文番号等の可能性
        final serialMatch = _serialNumberPattern.firstMatch(line);
        if (serialMatch != null &&
            serialMatch.group(0)!.length == line.replaceAll(RegExp(r'\s'), '').length) {
          continue;
        }
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

  // ─── bbox版 店名抽出 ───

  /// bbox 情報を活用した店名抽出
  ///
  /// - 上位25%の位置にあるトークンを対象
  /// - bbox.height（フォントサイズ代理）が大きいトークンを優先
  @visibleForTesting
  static ScoredResult<String>? extractMerchantFromTokens(List<OcrToken> tokens) {
    final validTokens = tokens
        .where((t) => t.text.trim().isNotEmpty && t.bbox != null)
        .toList();
    if (validTokens.isEmpty) return null;

    // 画像全体の高さを推定（最下部トークンの y + height）
    double maxY = 0;
    for (final t in validTokens) {
      final bottom = t.bbox!.y + t.bbox!.height;
      if (bottom > maxY) {
        maxY = bottom;
      }
    }
    if (maxY <= 0) return null;

    // 上位25%のトークンのみ対象
    final upperThreshold = maxY * 0.25;
    final upperTokens = validTokens
        .where((t) => t.bbox!.y < upperThreshold)
        .toList();
    if (upperTokens.isEmpty) return null;

    // 最大フォントサイズ（bbox.height）を取得
    double maxHeight = 0;
    for (final t in upperTokens) {
      if (t.bbox!.height > maxHeight) {
        maxHeight = t.bbox!.height;
      }
    }

    double bestScore = 0;
    String? bestCandidate;

    for (final token in upperTokens) {
      final text = token.text.trim();

      // 基本フィルタ
      if (text.length < 2 || text.length > 30) continue;
      if (merchantExcludeKeywords.any((kw) => text.contains(kw))) continue;

      final symbolCount =
          text.runes.where((r) => !_isJapaneseOrAlphanumeric(r)).length;
      if (symbolCount > text.runes.length / 2) continue;

      double score = 0;

      // 位置スコア: 上にあるほど高い
      score += (1.0 - token.bbox!.y / upperThreshold).clamp(0.0, 1.0);

      // フォントサイズスコア: 大きいほど高い（店名は大きい文字で書かれることが多い）
      if (maxHeight > 0) {
        score += (token.bbox!.height / maxHeight) * 0.5;
      }

      // 日本語ボーナス
      if (text.runes.any((r) => _isJapanese(r))) {
        score += 0.3;
      }

      // 店舗系キーワードボーナス
      if (RegExp(r'(店|ストア|マート|スーパー|コンビニ|薬局|ドラッグ)')
          .hasMatch(text)) {
        score += 0.2;
      }

      if (score > bestScore) {
        bestScore = score;
        bestCandidate = text;
      }
    }

    if (bestCandidate == null) return null;
    return ScoredResult(bestCandidate, bestScore);
  }

  // ─── bbox版 合計金額抽出 ───

  /// bbox 情報を活用した合計金額抽出
  ///
  /// - 優先キーワードと同一行（近い Y 座標）の金額を最優先
  /// - 右側近傍の金額を第2優先
  @visibleForTesting
  static ScoredResult<int>? extractTotalFromTokens(List<OcrToken> tokens) {
    final amountRegex =
        RegExp(r'[¥￥]\s*([0-9,]+)|([0-9,]+)\s*円|([0-9,]{3,})');

    // Y座標の近さで「同一行」を判定するための閾値
    // 各トークンの高さの平均を基準にする
    final bboxTokens = tokens.where((t) => t.bbox != null).toList();
    if (bboxTokens.isEmpty) {
      // bbox なし → テキストベースにフォールバック
      final lines = tokens.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();
      return extractTotal(lines);
    }

    double avgHeight = 0;
    for (final t in bboxTokens) {
      avgHeight += t.bbox!.height;
    }
    avgHeight /= bboxTokens.length;
    // 同一行判定: Y座標の差が平均高さの1.5倍以内
    final sameLineThreshold = avgHeight * 1.5;

    // 優先キーワードを含むトークンを検索
    final keywordTokens = bboxTokens.where((t) =>
        totalPriorityKeywords.any((kw) => t.text.contains(kw)) &&
        !totalExcludeKeywords.any((kw) => t.text.contains(kw))).toList();

    double bestScore = -1;
    int? bestAmount;

    for (final token in bboxTokens) {
      final text = token.text.trim();

      // 除外チェック
      if (totalExcludeKeywords.any((kw) => text.contains(kw))) continue;
      if (_datePattern.hasMatch(text) &&
          !totalPriorityKeywords.any((kw) => text.contains(kw))) {
        continue;
      }
      if (_warekiPattern.hasMatch(text)) continue;
      if (_serialNumberPattern.hasMatch(text) &&
          !text.contains('¥') && !text.contains('￥') && !text.contains('円')) {
        final serialMatch = _serialNumberPattern.firstMatch(text);
        if (serialMatch != null &&
            serialMatch.group(0)!.length == text.replaceAll(RegExp(r'\s'), '').length) {
          continue;
        }
      }

      // 金額を抽出
      final matches = amountRegex.allMatches(text);
      for (final match in matches) {
        final amountStr =
            (match.group(1) ?? match.group(2) ?? match.group(3))
                ?.replaceAll(',', '');
        if (amountStr == null || amountStr.isEmpty) continue;

        final amount = int.tryParse(amountStr);
        if (amount == null || amount <= 0 || amount > 1000000) continue;

        double score = 0;

        // 同一テキスト内に優先キーワードがある場合
        if (totalPriorityKeywords.any((kw) => text.contains(kw))) {
          score += 2.0;
        }

        // 近傍の優先キーワードトークンとの位置関係
        if (token.bbox != null) {
          for (final kwToken in keywordTokens) {
            final yDiff = (token.bbox!.y - kwToken.bbox!.y).abs();
            if (yDiff < sameLineThreshold) {
              // 同一行のキーワード近傍
              score += 1.5;
              // キーワードの右側にある金額をさらに優先
              if (token.bbox!.x > kwToken.bbox!.x) {
                score += 0.3;
              }
              break;
            }
          }
        }

        // 文書下部ボーナス
        final tokenIndex = bboxTokens.indexOf(token);
        score += tokenIndex / bboxTokens.length * 0.5;

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
