import 'package:flutter/foundation.dart';

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

  /// ブラウザ制約でファイル選択を開始できない
  ///
  /// 主な原因:
  /// - user activation 制約: ファイル選択がユーザー操作と同一イベントループ内でない
  /// - PlatformException（権限以外）: ブラウザ固有のファイル入力制約
  /// - その他 Web 固有の例外
  browserBlocked,

  /// 画像の読み込み失敗（ファイル破損等）
  fileReadError,

  /// 非対応の画像形式（JPEG/PNG以外）
  unsupportedFormat,

  /// ファイルサイズ超過
  fileTooLarge,

  /// 未分類のエラー
  unknown,
}

/// 画像取得の結果（プラットフォーム非依存: Uint8List）
class PickImageResult {
  final PickImageStatus status;
  final Uint8List? imageBytes;

  /// UI向け補足メッセージ（失敗時の詳細説明）
  final String? errorDetail;

  const PickImageResult(this.status, {this.imageBytes, this.errorDetail});

  /// UI表示用メッセージ（errorDetail 優先、なければデフォルト文言）
  ///
  /// success / canceled には null を返す（通知不要のため）。
  String? get displayMessage {
    if (status == PickImageStatus.success ||
        status == PickImageStatus.canceled) {
      return null;
    }
    return errorDetail ?? status.defaultMessage;
  }

  /// 「再試行」導線を表示すべきか
  bool get shouldShowRetry =>
      status != PickImageStatus.success &&
      status != PickImageStatus.canceled &&
      status != PickImageStatus.permissionDenied;
}

/// PickImageStatus のデフォルトUI文言
extension PickImageStatusMessage on PickImageStatus {
  /// 各種別のデフォルト表示メッセージ
  String get defaultMessage => switch (this) {
        PickImageStatus.success => '',
        PickImageStatus.canceled => '',
        PickImageStatus.permissionDenied => 'カメラ/写真ライブラリへのアクセスが必要です。',
        PickImageStatus.browserBlocked =>
          'ブラウザの制約でファイル選択を開始できませんでした。'
          'もう一度押すか、別のブラウザで試してください。手入力でも続けられます。',
        PickImageStatus.fileReadError =>
          '画像の読み込みに失敗しました。別の画像で再試行してください。',
        PickImageStatus.unsupportedFormat =>
          '対応していない画像形式です。JPEG/PNG画像を選択してください。',
        PickImageStatus.fileTooLarge =>
          '画像サイズが大きすぎます。10MB以下の画像を選択してください。',
        PickImageStatus.unknown =>
          '画像取得に失敗しました。再試行または手入力で続けてください。',
      };
}

/// レシートOCRサービス（オンデバイス処理、画像非送信）
///
/// 3層構成:
///   - OcrEngine（インフラ層）: プラットフォーム別のOCR処理
///   - 抽出ロジック（純粋関数）: テキスト/トークンからの情報抽出
///   - ReceiptOcrService（オーケストレーション）: 画像取得→OCR→抽出の統合
class ReceiptOcrService {
  const ReceiptOcrService._();

  /// OCR処理のタイムアウト（秒）
  static const int timeoutSeconds = 12;

  /// 店名候補の検索対象行数（上部N行）
  static const int _merchantSearchLines = 5;

  /// 1日あたりのOCR実行上限（ソフトリミット）
  static const int dailyLimit = 30;

  /// 今日の実行回数（アプリ再起動でリセット）
  static int _todayCount = 0;
  static DateTime _lastResetDate = DateTime.now();

  /// 画像取得の失敗種別カウンタ（匿名メトリクス、PII なし）
  static final Map<PickImageStatus, int> _pickFailureCounts = {};

  /// 画像取得失敗をカウントし、種別をログ出力する
  static void recordPickFailure(PickImageStatus status) {
    if (status == PickImageStatus.success ||
        status == PickImageStatus.canceled) {
      return;
    }
    _pickFailureCounts[status] = (_pickFailureCounts[status] ?? 0) + 1;
    debugPrint(
      'ReceiptOcrService: 画像取得失敗 [${status.name}] '
      '累計: ${_pickFailureCounts[status]}',
    );
  }

  /// 現在の失敗種別カウンタを取得（テスト・デバッグ用）
  @visibleForTesting
  static Map<PickImageStatus, int> get pickFailureCounts =>
      Map.unmodifiable(_pickFailureCounts);

  /// 失敗種別カウンタをリセット（テスト用）
  @visibleForTesting
  static void resetPickFailureCounts() => _pickFailureCounts.clear();

  /// 店名の除外キーワード
  static const List<String> merchantExcludeKeywords = [
    '〒', 'TEL', 'tel', 'Tel', 'FAX', 'fax',
    '東京都', '大阪府', '北海道', '京都府',
    '市', '区', '町', '村', '番地', '号',
    '担当', 'No.', 'NO.', 'レジ', '会員',
    '領収', '明細', '税', 'http', 'www',
  ];

  /// 合計金額の優先キーワード
  ///
  /// 「税込」は単独では商品行（例: 「お茶 税込 108」）に誤マッチするため除外。
  /// 「税込合計」「合計(税込)」は「合計」でマッチする。
  static const List<String> totalPriorityKeywords = [
    '合計', 'ご請求', 'お会計',
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

  // ─── 金額候補の OCR 誤認正規化 ───

  /// 金額候補文字列の軽微な OCR 誤認を補正する
  ///
  /// ラベル文字列には適用しない（金額候補のみ）。
  @visibleForTesting
  static String normalizeAmountText(String text) {
    return text
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('I', '1')
        .replaceAll('l', '1')
        .replaceAll(' ', '')
        .replaceAll(',,', ',');
  }

  /// 金額正規表現（正規化済み文字列に適用）
  static final RegExp _amountRegex =
      RegExp(r'[¥￥]\s*([0-9,]+)|([0-9,]+)\s*円|([0-9,]{3,})');

  /// 文字列から金額候補を抽出（OCR 誤認正規化付き）
  ///
  /// 返り値は `(金額, 文字列内での出現位置)` のリスト。
  @visibleForTesting
  static List<(int amount, int position)> extractAmountCandidates(
    String text,
  ) {
    final normalized = normalizeAmountText(text);
    final results = <(int, int)>[];
    for (final match in _amountRegex.allMatches(normalized)) {
      final amountStr =
          (match.group(1) ?? match.group(2) ?? match.group(3))
              ?.replaceAll(',', '');
      if (amountStr == null || amountStr.isEmpty) continue;
      final amount = int.tryParse(amountStr);
      if (amount == null || amount <= 0 || amount > 1000000) continue;
      results.add((amount, match.start));
    }
    return results;
  }

  /// ラベルキーワード直後の最も近い金額候補を選ぶ
  ///
  /// [candidates] は `extractAmountCandidates()` の結果。
  /// [normalizedText] は `normalizeAmountText()` 適用済みの行テキスト。
  /// ラベル末尾位置以降で最も近い金額を優先し、なければ全候補から最近を返す。
  static (int amount, int position) _pickClosestToLabel(
    List<(int amount, int position)> candidates,
    String normalizedText,
  ) {
    // ラベルキーワードの末尾位置を特定
    int labelEnd = 0;
    for (final kw in totalPriorityKeywords) {
      final idx = normalizedText.indexOf(kw);
      if (idx >= 0) {
        final end = idx + kw.length;
        if (end > labelEnd) labelEnd = end;
      }
    }

    // ラベル直後の最も近い金額を優先
    final afterLabel = candidates.where((c) => c.$2 >= labelEnd).toList();
    if (afterLabel.isNotEmpty) {
      return afterLabel.reduce((a, b) => a.$2 < b.$2 ? a : b);
    }
    // ラベル後にない場合は全候補から最もラベルに近いものを選ぶ
    return candidates.reduce(
      (a, b) =>
          (a.$2 - labelEnd).abs() < (b.$2 - labelEnd).abs() ? a : b,
    );
  }

  // ─── 合計金額抽出（テキスト行ベース） ───

  /// 合計ラベル起点で金額を抽出（bbox なし経路）
  ///
  /// 1. 合計ラベルを含む行の行末金額を最優先
  /// 2. ラベル行が見つからない場合のみ、全行から補助的に候補を探す
  @visibleForTesting
  static ScoredResult<int>? extractTotal(List<String> lines) {
    // ── Phase 1: 合計ラベル行の行末金額を探す ──
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 除外キーワードのみの行はスキップ
      if (totalExcludeKeywords.any((kw) => line.contains(kw)) &&
          !totalPriorityKeywords.any((kw) => line.contains(kw))) {
        continue;
      }

      // 合計ラベルがあるか
      if (!totalPriorityKeywords.any((kw) => line.contains(kw))) continue;

      // この行から金額候補を抽出
      final candidates = extractAmountCandidates(line);
      if (candidates.isEmpty) continue;

      // ラベル直後の最も近い金額を優先
      final normalizedLine = normalizeAmountText(line);
      final best = _pickClosestToLabel(candidates, normalizedLine);
      // ラベル行の金額は高スコア（2.0 基準）
      return ScoredResult(best.$1, 2.0);
    }

    // ── Phase 2: フォールバック（ラベル行なし → 補助的候補探索） ──
    double bestScore = -1;
    int? bestAmount;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 除外行チェック
      if (totalExcludeKeywords.any((kw) => line.contains(kw))) continue;
      if (_datePattern.hasMatch(line)) continue;
      if (_warekiPattern.hasMatch(line)) continue;
      if (_serialNumberPattern.hasMatch(line) &&
          !line.contains('¥') &&
          !line.contains('￥') &&
          !line.contains('円')) {
        final serialMatch = _serialNumberPattern.firstMatch(line);
        if (serialMatch != null &&
            serialMatch.group(0)!.length ==
                line.replaceAll(RegExp(r'\s'), '').length) {
          continue;
        }
      }

      final candidates = extractAmountCandidates(line);
      for (final (amount, _) in candidates) {
        // フォールバックは低スコア（文書下部 + 金額規模のみ）
        double score = 0;
        score += i / lines.length * 0.3;
        score += (amount / 100000).clamp(0, 0.2);

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

  /// token を Y 座標で擬似行にグルーピングする
  ///
  /// Y 座標の差が [threshold] 以内のトークンを同一行とみなす。
  /// 各行内のトークンは X 座標昇順でソートされる。
  @visibleForTesting
  static List<List<OcrToken>> groupTokensIntoLines(
    List<OcrToken> tokens,
    double threshold,
  ) {
    if (tokens.isEmpty) return [];

    // Y 座標でソート
    final sorted = List<OcrToken>.from(tokens)
      ..sort((a, b) => a.bbox!.y.compareTo(b.bbox!.y));

    final lines = <List<OcrToken>>[];
    var currentLine = <OcrToken>[sorted.first];
    double currentY = sorted.first.bbox!.y;

    for (int i = 1; i < sorted.length; i++) {
      final token = sorted[i];
      if ((token.bbox!.y - currentY).abs() <= threshold) {
        currentLine.add(token);
      } else {
        // X 座標でソートして行を確定
        currentLine.sort((a, b) => a.bbox!.x.compareTo(b.bbox!.x));
        lines.add(currentLine);
        currentLine = [token];
        currentY = token.bbox!.y;
      }
    }
    // 最後の行を追加
    currentLine.sort((a, b) => a.bbox!.x.compareTo(b.bbox!.x));
    lines.add(currentLine);

    return lines;
  }

  /// bbox 情報を活用した合計金額抽出（ラベル起点ペア探索）
  ///
  /// 1. token を擬似行にグルーピング
  /// 2. 各行で合計ラベルを探し、同一行右側の金額を最優先で採用
  /// 3. ラベル行が見つからない場合は補助的フォールバック
  @visibleForTesting
  static ScoredResult<int>? extractTotalFromTokens(List<OcrToken> tokens) {
    final bboxTokens = tokens.where((t) => t.bbox != null).toList();
    if (bboxTokens.isEmpty) {
      // bbox なし → テキストベースにフォールバック
      final lines =
          tokens.map((t) => t.text.trim()).where((t) => t.isNotEmpty).toList();
      return extractTotal(lines);
    }

    // 平均トークン高さを算出（行グルーピング閾値の基準）
    double avgHeight = 0;
    for (final t in bboxTokens) {
      avgHeight += t.bbox!.height;
    }
    avgHeight /= bboxTokens.length;
    final sameLineThreshold = avgHeight * 1.5;

    // token を擬似行にグルーピング
    final pseudoLines = groupTokensIntoLines(bboxTokens, sameLineThreshold);

    // ── Phase 1: 合計ラベル行の右側金額を探す ──
    ScoredResult<int>? bestLabelResult;
    double bestLabelScore = -1;

    for (final line in pseudoLines) {
      // 行内テキストを結合して除外チェック
      final lineText = line.map((t) => t.text.trim()).join(' ');

      // 除外キーワードのみの行はスキップ
      if (totalExcludeKeywords.any((kw) => lineText.contains(kw)) &&
          !totalPriorityKeywords.any((kw) => lineText.contains(kw))) {
        continue;
      }

      // 合計ラベルを含むトークンを検索
      OcrToken? labelToken;
      for (final token in line) {
        final text = token.text.trim();
        if (totalPriorityKeywords.any((kw) => text.contains(kw))) {
          labelToken = token;
          break;
        }
      }
      if (labelToken == null) continue;

      // ラベルトークン自体に金額が含まれるケース（例: 「合計 ¥334」）
      final labelCandidates = extractAmountCandidates(labelToken.text);
      if (labelCandidates.isNotEmpty) {
        // ラベル直後の最も近い金額を優先
        final normalizedLabel = normalizeAmountText(labelToken.text);
        final best = _pickClosestToLabel(labelCandidates, normalizedLabel);
        const score = 3.0; // ラベル内金額は最高スコア
        if (score > bestLabelScore) {
          bestLabelScore = score;
          bestLabelResult = ScoredResult(best.$1, score);
        }
      }

      // ラベルの右側にある金額トークンを探す
      for (final token in line) {
        if (token.bbox!.x <= labelToken.bbox!.x) continue;
        final text = token.text.trim();
        if (totalExcludeKeywords.any((kw) => text.contains(kw))) continue;

        final candidates = extractAmountCandidates(text);
        for (final (amount, _) in candidates) {
          // スコア: 同一行右側（2.5）+ ラベルとの近さ
          final xDist = token.bbox!.x - labelToken.bbox!.x;
          final proximityBonus =
              (1.0 / (1.0 + xDist / 100.0)).clamp(0.0, 0.5);
          final score = 2.5 + proximityBonus;
          if (score > bestLabelScore) {
            bestLabelScore = score;
            bestLabelResult = ScoredResult(amount, score);
          }
        }
      }
    }

    if (bestLabelResult != null) return bestLabelResult;

    // ── Phase 2: フォールバック（ラベル行なし → 全行から補助的候補） ──
    double bestScore = -1;
    int? bestAmount;

    for (int lineIdx = 0; lineIdx < pseudoLines.length; lineIdx++) {
      final line = pseudoLines[lineIdx];
      final lineText = line.map((t) => t.text.trim()).join(' ');

      if (totalExcludeKeywords.any((kw) => lineText.contains(kw))) continue;
      if (_datePattern.hasMatch(lineText)) continue;
      if (_warekiPattern.hasMatch(lineText)) continue;

      for (final token in line) {
        final candidates = extractAmountCandidates(token.text);
        for (final (amount, _) in candidates) {
          double score = 0;
          score += lineIdx / pseudoLines.length * 0.3;
          score += (amount / 100000).clamp(0, 0.2);
          if (score > bestScore) {
            bestScore = score;
            bestAmount = amount;
          }
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
