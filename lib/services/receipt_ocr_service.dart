import 'package:flutter/foundation.dart';

import '../models/ocr_token.dart';
import '../models/receipt_ocr_result.dart';
import 'ocr_engine/ocr_engine.dart';
import 'receipt_image_preprocessor.dart';

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

/// 合計ラベルの重み付きルール
///
/// 複数ラベル一致時に weight が大きい方を優先する。
class TotalLabelRule {
  /// マッチ対象の文字列パターン
  final String pattern;

  /// ラベルの優先度（1.0 が最高）
  final double weight;

  const TotalLabelRule(this.pattern, this.weight);
}

/// チェーン店名の正規化ルール
///
/// チェーン名の確定方針（Step21 Round52 改修）:
/// 1. [excludePatterns] のいずれかが上部領域に含まれる場合は確定しない
///    （例: `セブン銀行`, `セブンティーン`, `セブンプレミアム`）。
/// 2. [exactPatterns] のいずれかが含まれる場合は単独でチェーン確定。
/// 3. それ以外は [requiredFragmentGroups] を満たす場合のみ確定。
///    各グループは「同じ意味的構成要素を表す断片の集合」で、
///    同一グループ内の重複ヒットは 1 件として扱う（過剰マッチ防止）。
class MerchantChainRule {
  /// 正規化後のチェーン名
  final String canonicalName;

  /// 完全一致パターン（単独でヒットすれば確定）
  ///
  /// 大文字小文字・空白を吸収して比較する（小文字化＋空白除去）。
  final List<String> exactPatterns;

  /// 必須断片グループ
  ///
  /// 各グループは「seven 系」「eleven 系」のような構成要素単位で定義し、
  /// 全グループから 1 件以上のヒットが必要。
  /// 同一グループ内の `セブン` と `セブ` は重複ヒットとして
  /// 1 件にカウントするため、`セブン` 単独では確定しない。
  final List<List<String>> requiredFragmentGroups;

  /// 除外パターン（上部領域に出現したら確定しない）
  ///
  /// `セブン銀行`, `セブンティーン` など、チェーン名と紛らわしいが
  /// 別ブランドの語を含む場合に確定を抑止する。
  final List<String> excludePatterns;

  const MerchantChainRule({
    required this.canonicalName,
    this.exactPatterns = const [],
    this.requiredFragmentGroups = const [],
    this.excludePatterns = const [],
  });
}

/// 合計ラベルの原文上のマッチ位置情報
///
/// fuzzy 一致でも原文末尾位置を保持することで、ラベル直後の金額抽出を
/// fallback ではなくラベル起点で行えるようにする（Step21 Round52）。
class _LabelMatch {
  /// マッチしたラベルルール（weight 等）
  final TotalLabelRule rule;

  /// 原文上で実際に出現するラベル文字列（例: `合 言十`）
  final String matchedText;

  /// 原文上の開始 index（不明な場合は -1）
  final int startInOriginal;

  /// 原文上の末尾 index（exclusive）
  final int endInOriginal;

  const _LabelMatch({
    required this.rule,
    required this.matchedText,
    required this.startInOriginal,
    required this.endInOriginal,
  });
}

/// fuzzy 合計ラベルの原文上のマッチ位置
class _FuzzyLabelHit {
  final String matchedText;
  final int startInOriginal;
  final int endInOriginal;

  const _FuzzyLabelHit({
    required this.matchedText,
    required this.startInOriginal,
    required this.endInOriginal,
  });
}

/// Step23: bbox 経路で検出した合計ラベル候補のコンテキスト
///
/// Phase 1 通常ペアリング（同一行・直下行）で金額を取れなかった場合に、
/// 上下複数行の近傍探索を実行するために使う。
class _LabelCandidate {
  final int lineIdx;
  final OcrToken labelToken;
  final TotalLabelRule rule;

  const _LabelCandidate({
    required this.lineIdx,
    required this.labelToken,
    required this.rule,
  });
}

/// Step22 監査 N-2: チェーン正規化の判定経路を区別する内部結果
///
/// - `exact`: exactPatterns ヒット
/// - `fragments`: 異なる OCR トークンにまたがる断片共起
/// - `segmented_fragments`: 1 OCR トークン内のセグメント分割で成立
class _ChainMatchResult {
  final String canonicalName;
  final String source;
  const _ChainMatchResult(this.canonicalName, this.source);
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

  // ─── Step21: 採用/棄却理由のデバッグ観測 ───
  //
  // 候補本文を含むため debug build / テスト限定で蓄積する。
  // assert() を介して release ビルドでは実行コストがゼロになる。
  // PII 観点: 候補文字列を残すが永続保存はせず、メモリ上のリストのみ。
  static final List<String> _candidateTrace = [];

  /// 直近抽出の採用/棄却理由ログ（テスト・デバッグ用）
  ///
  /// `extractFromTokens` / `extractFromText` を呼ぶ毎にクリアされる。
  @visibleForTesting
  static List<String> get lastCandidateTrace =>
      List.unmodifiable(_candidateTrace);

  /// トレースをリセット（テスト用）
  @visibleForTesting
  static void resetCandidateTrace() => _candidateTrace.clear();

  static void _trace(String message) {
    // assert ブロックは release で除去される。
    assert(() {
      _candidateTrace.add(message);
      return true;
    }());
    if (kDebugMode) {
      debugPrint('ReceiptOcrService.candidate: $message');
    }
  }

  /// 店名の除外キーワード
  static const List<String> merchantExcludeKeywords = [
    '〒', 'TEL', 'tel', 'Tel', 'FAX', 'fax',
    '東京都', '大阪府', '北海道', '京都府',
    '市', '区', '町', '村', '番地', '号',
    '担当', 'No.', 'NO.', 'レジ', '会員',
    '領収', '明細', '税', 'http', 'www',
  ];

  /// 合計金額の重み付きラベルルール
  ///
  /// 複数ラベル一致時は weight が大きいルールを優先する。
  /// 「税込」は単独では商品行に誤マッチするため含めない。
  /// 「税込合計」「合計(税込)」は「合計」でマッチする。
  static const List<TotalLabelRule> totalLabelRules = [
    // weight 1.0: 「合計」を含むラベル（最優先）
    TotalLabelRule('合計', 1.0),
    // weight 0.8: 請求系ラベル
    TotalLabelRule('ご請求', 0.8),
    TotalLabelRule('請求額', 0.8),
    TotalLabelRule('お会計', 0.8),
    TotalLabelRule('TOTAL', 0.8),
    TotalLabelRule('Total', 0.8),
    // weight 0.6: その他の合計系ラベル
    TotalLabelRule('利用金額', 0.6),
    TotalLabelRule('決済額', 0.6),
  ];

  /// 後方互換: ラベルパターン一覧（内部でルール参照が必要な箇所向け）
  static List<String> get totalPriorityKeywords =>
      totalLabelRules.map((r) => r.pattern).toList();

  /// 合計金額の除外キーワード
  ///
  /// Step21: 伝票番号・会員コード系は別途 [amountUnsafeContextKeywords] /
  /// [isUnsafeAmountContext] で扱うため、ここには含めない（reject 理由を分離する）。
  static const List<String> totalExcludeKeywords = [
    '小計', 'お釣り', 'おつり', '預り', 'お預り',
    'お支払', 'ポイント', '手数料', '値引', '割引', '返品',
    '内税', '外税', '消費税', '税額',
    // Step19: 支払手段・税率行の誤検出防止
    '支払', 'PayPay', '税率', '対象',
    '内消費税', '電子マネー', 'カード', '現金',
  ];

  /// Step21: 金額として採用してはいけない文脈ワード
  ///
  /// 行内に出現した時点で fallback 候補から外す。
  static const List<String> amountUnsafeContextKeywords = [
    '伝票', '伝票番号', '取引番号', '管理番号', 'バーコード',
    '会員', '会員番号', '会員コード',
    '店番', '担当', 'レジ', 'No.', 'NO.',
    'TEL', 'Tel', 'tel', '電話',
  ];

  /// Step22: 合計金額 fallback 専用の除外キーワード（明細・商品行系）
  ///
  /// `totalExcludeKeywords` は Phase 1 / Phase 2 共通で参照されるが、
  /// `商品代金 ¥651` のような商品明細行は、ラベル付き経路では誤抽出しない一方、
  /// fallback では「通貨記号付き金額」として採用されてしまう。
  /// fallback 限定で除外することで、店舗名や商品名と被る副作用を避ける。
  static const List<String> totalFallbackExcludeKeywords = [
    '商品代金', '商品', '単価', '点数', '数量', '対象商品',
  ];

  /// 日付パターン（金額誤認防止）
  static final RegExp _datePattern =
      RegExp(r'\d{4}[/\-\.]\d{1,2}[/\-\.]\d{1,2}');

  /// 和暦日付パターン（令和/平成 + 数字）
  static final RegExp _warekiPattern =
      RegExp(r'(令和|平成|昭和)\s*\d{1,2}年');

  /// 連番パターン（10桁以上の数字列 → レシート番号等）
  static final RegExp _serialNumberPattern = RegExp(r'\d{10,}');

  /// Step21: ハッシュ伝票番号 `#1234...`
  static final RegExp _hashSerialPattern = RegExp(r'#\s*\d{4,}');

  /// Step21: 電話番号風 `03-1234-5678`, `260-228-215-0268`
  static final RegExp _phoneLikePattern =
      RegExp(r'\d{2,4}\s*[-－]\s*\d{2,4}\s*[-－]\s*\d{2,4}');

  /// Step21: 単独数字ノイズ（6桁以上の素の連続数字）
  ///
  /// 通貨記号や `円` を伴わない 6 桁以上の数字は伝票番号系である可能性が高い。
  static final RegExp _bareLongDigitsPattern = RegExp(r'^\s*\d{6,}\s*$');

  /// Step21: 既知チェーン店名の正規化ルール
  ///
  /// `exactPatterns` 単独ヒット、または各 `requiredFragmentGroups` から
  /// 1 件以上のヒットが揃った場合に確定する。
  /// `セブン` 単独（= seven グループのみヒット）では確定しない構造。
  static const List<MerchantChainRule> chainRules = [
    MerchantChainRule(
      canonicalName: 'セブンイレブン',
      exactPatterns: [
        'セブンイレブン',
        'セブン-イレブン',
        'セブン イレブン',
        '7-ELEVEN',
        '7-Eleven',
        '7-eleven',
        '7eleven',
        'SEVEN ELEVEN',
        'Seven Eleven',
        'seven-eleven',
        'seveneleven',
      ],
      requiredFragmentGroups: [
        // group A: seven 系（前半要素）
        // Step24: `セフン` は `セブン` の OCR 揺れ（`ブ`→`フ`）として追加。
        // 2 文字以上のまとまりとして group A 認定するため、`フン` 単独は含めない。
        ['セブン', 'セブ', 'セフン', 'seven'],
        // group B: eleven 系（後半要素）
        // `ブン` は OCR 崩れで `イ ルレ ル ブン` のように分断された場合の
        // 末尾断片として残るため、最小ヒット用に含める。
        // Step24: `ルブン` は `ル ブン` 連結時の補助断片。
        // 単独ヒットによる誤補正は `excludePatterns` で抑止する。
        ['イレブン', 'レブン', 'イレブ', 'ルブン', 'ブン', 'eleven'],
      ],
      excludePatterns: [
        'セブン銀行', 'セブン&アイ', 'セブンアンドアイ',
        'セブンティーン', 'セブンプレミアム', 'セブンアイス',
        'セブンカフェ', 'セブンミール',
      ],
    ),
  ];

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
  /// [preprocessor] が渡された場合、OCR 前に画像前処理を適用する。
  /// 一時ファイルの管理は Engine 側で行う。
  static Future<ReceiptOcrResult?> processImageBytes(
    Uint8List imageBytes,
    OcrEngine engine, {
    ReceiptImagePreprocessor? preprocessor,
  }) async {
    _incrementCount();
    try {
      // ── 観測点: pick 直後 ──
      final inputFormat = detectImageFormat(imageBytes);
      final inputDims = parseImageDimensions(imageBytes);
      debugPrint(
        'ReceiptOcrService: pick後 '
        'format=$inputFormat bytes=${imageBytes.length} '
        'dims=${inputDims != null ? "${inputDims.width}x${inputDims.height}" : "unknown"}',
      );

      // 前処理（HEIC→JPEG 変換、向き補正、リサイズ等）
      Uint8List ocrInput = imageBytes;
      if (preprocessor != null) {
        final preprocessed = await preprocessor.preprocess(imageBytes);
        ocrInput = preprocessed.bytes;
        // ── 観測点: preprocess 後 ──
        debugPrint(
          'ReceiptOcrService: preprocess後 '
          'format=${preprocessed.format} '
          'bytes=${ocrInput.length} '
          'dims=${preprocessed.dimensionsString} '
          'converted=${preprocessed.converted} '
          'steps=[${preprocessed.appliedSteps.join(", ")}]',
        );
      }

      final tokens = await engine
          .recognizeFromBytes(ocrInput)
          .timeout(Duration(seconds: timeoutSeconds));

      // ── 観測点: OCR 後 ──
      debugPrint(
        'ReceiptOcrService: OCR後 tokenCount=${tokens.length}',
      );

      if (tokens.isEmpty) {
        debugPrint('ReceiptOcrService: OCRトークン空');
        return null;
      }

      // トークンからテキストを結合して抽出（bbox版は Step13-D で追加）
      final result = extractFromTokens(tokens);

      // ── 観測点: 抽出結果 ──
      debugPrint(
        'ReceiptOcrService: 抽出結果 '
        'merchant=${result.merchantName} '
        'total=${result.totalAmount} '
        'confidence=${result.confidence.toStringAsFixed(2)}',
      );

      return result;
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
    resetCandidateTrace();
    final lines = tokens
        .map((t) => t.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const ReceiptOcrResult(confidence: 0.0);
    }

    // bbox が利用可能か判定
    final hasBbox = tokens.any((t) => t.bbox != null);

    ScoredResult<String>? merchantResult;
    final ScoredResult<int>? totalResult;

    if (hasBbox) {
      merchantResult = extractMerchantFromTokens(tokens);
      totalResult = extractTotalFromTokens(tokens);
    } else {
      merchantResult = extractMerchant(lines);
      totalResult = extractTotal(lines);
    }

    // Step21: 既知チェーン名の優先採用
    //
    // 上部領域のトークンを集めて断片の共起から正規化名を導出する。
    // ロゴ崩れトークンが採用された場合でも、ここで正規化名へ置換する。
    // Step22 N-2: source（exact / fragments / segmented_fragments）も trace。
    final chainMatch =
        _detectChainNameWithSource(tokens, lines, hasBbox: hasBbox);
    if (chainMatch != null) {
      _trace(
        'merchantCandidate normalized '
        'chain=${chainMatch.canonicalName} source=${chainMatch.source}',
      );
      merchantResult = ScoredResult(chainMatch.canonicalName, 1.5);
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
    resetCandidateTrace();
    final lines = ocrText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const ReceiptOcrResult(confidence: 0.0);
    }

    ScoredResult<String>? merchantResult = extractMerchant(lines);
    final totalResult = extractTotal(lines);

    // Step21: 既知チェーン名の優先採用（上部行から検出）
    // Step22 N-2: source（exact / fragments / segmented_fragments）を区別。
    final chainMatch = _detectChainNameWithSourceFromLines(lines);
    if (chainMatch != null) {
      _trace(
        'merchantCandidate normalized '
        'chain=${chainMatch.canonicalName} source=${chainMatch.source}',
      );
      merchantResult = ScoredResult(chainMatch.canonicalName, 1.5);
    }

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

  /// ラベル検出用にテキストを正規化する
  ///
  /// OCR で `合 計` のように空白分断されたラベルを `合計` として
  /// 検出できるよう、ASCII / 全角空白を除去する。
  /// 金額候補の正規化（normalizeAmountText）とは別の関数。
  @visibleForTesting
  static String normalizeLabelText(String text) {
    return text
        .replaceAll(' ', '') // ASCII 空白
        .replaceAll('\u3000', '') // 全角空白
        .replaceAll('\t', ''); // タブ
  }

  /// 空白分断されたラベルの末尾位置を原文から探す
  ///
  /// 正規化でマッチしたが原文には空白が挟まるケース
  /// （例: `合 計` + pattern `合計`）で、ラベル末尾の原文位置を返す。
  static int _findLabelEndInOriginal(String original, String pattern) {
    int searchFrom = 0;
    for (int i = 0; i < pattern.length; i++) {
      final charIdx = original.indexOf(pattern[i], searchFrom);
      if (charIdx < 0) return original.length;
      searchFrom = charIdx + 1;
    }
    return searchFrom;
  }

  /// 行テキストから最高 weight のラベルマッチを探す
  ///
  /// 戻り値は [_LabelMatch] で、原文上で実際に出現したラベル文字列を保持する。
  /// `extractTotal` 側で `line.indexOf(match.matchedText)` を行い、
  /// fuzzy ラベル（`合 言十`, `谷 計` 等）でも原文上のラベル末尾を正確に特定できる。
  ///
  /// Step21 Round52: fuzzy 一致時は `_findFuzzyTotalLabelInOriginal` で
  /// 原文上の出現箇所と長さを返し、ラベル起点でその右側金額を抽出可能にする。
  static _LabelMatch? _findBestLabelMatch(String text) {
    final normalized = normalizeLabelText(text);
    _LabelMatch? best;
    for (final rule in totalLabelRules) {
      if (text.contains(rule.pattern)) {
        // 原文に直接マッチ
        if (best == null || rule.weight > best.rule.weight) {
          best = _LabelMatch(
            rule: rule,
            matchedText: rule.pattern,
            startInOriginal: text.indexOf(rule.pattern),
            endInOriginal: text.indexOf(rule.pattern) + rule.pattern.length,
          );
        }
      } else if (normalized.contains(rule.pattern)) {
        // 正規化経由でマッチ（例: `合 計` → `合計`）
        // 原文上のラベル末尾を _findLabelEndInOriginal で特定する
        if (best == null || rule.weight > best.rule.weight) {
          final end = _findLabelEndInOriginal(text, rule.pattern);
          best = _LabelMatch(
            rule: rule,
            matchedText: rule.pattern,
            startInOriginal: -1,
            endInOriginal: end,
          );
        }
      }
    }
    if (best != null) return best;

    // Step21: 合計ラベル限定の fuzzy マッチ
    if (_hasTotalNegativeContext(text)) return null;
    final fuzzyHit = _findFuzzyTotalLabelInOriginal(text, normalized);
    if (fuzzyHit != null) {
      return _LabelMatch(
        rule: _fuzzyTotalRule,
        matchedText: fuzzyHit.matchedText,
        startInOriginal: fuzzyHit.startInOriginal,
        endInOriginal: fuzzyHit.endInOriginal,
      );
    }
    return null;
  }

  /// 原文上で fuzzy 合計ラベルの出現位置を返す
  ///
  /// 監査 Round52 H-2 対応: fuzzy ラベルが fallback ではなくラベル起点で
  /// 抽出されるよう、原文上の `合 言十`, `合言十`, `谷 計`, `台 計` などの
  /// 出現位置と長さを特定する。
  /// 戻り値が null の場合は fuzzy 合計ラベルとして扱わない。
  static _FuzzyLabelHit? _findFuzzyTotalLabelInOriginal(
    String original,
    String normalized,
  ) {
    // まず正規化テキストで `合計` 相当が現れるかを判定する
    final fuzzed = _fuzzyTotalLabelText(normalized);
    if (!fuzzed.contains('合計')) return null;

    // 原文上で実際に出現する fuzzy ラベルパターンを優先順に探す。
    // 長いパターンから探すことで、`合言十` を `合言` + `十` に分解しないようにする。
    const patterns = [
      // 空白なし
      '合言十',
      '谷計', '台計',
      // 空白あり（半角）
      '合 言十', '谷 計', '台 計',
      // 全角空白
      '合\u3000言十', '谷\u3000計', '台\u3000計',
      // 言+十 の途中空白（`合 言 十` のような分断）
      '合 言 十', '合\u3000言\u3000十',
    ];
    for (final p in patterns) {
      final idx = original.indexOf(p);
      if (idx >= 0) {
        return _FuzzyLabelHit(
          matchedText: p,
          startInOriginal: idx,
          endInOriginal: idx + p.length,
        );
      }
    }

    // パターン未一致 → 正規化経由の末尾位置にフォールバック
    // （`合計` 文字列を構成するキー文字 `合` または `谷`/`台` のいずれかと
    //   `計` または `言`+`十` を順に走査して末尾位置を求める）
    final end = _findFuzzyLabelEndByScan(original);
    if (end < 0) return null;
    return _FuzzyLabelHit(
      matchedText: original.substring(0, end),
      startInOriginal: 0,
      endInOriginal: end,
    );
  }

  /// 原文を順走査して fuzzy 合計ラベルの末尾位置を返す
  ///
  /// 走査ルール:
  /// 1. 先頭文字が `合` / `谷` / `台` のいずれかを探す
  /// 2. その後ろに `計`、または `言` + `十` の順で出現する位置を返す
  /// 見つからない場合は -1 を返す。
  static int _findFuzzyLabelEndByScan(String original) {
    int? headIdx;
    const heads = ['合', '谷', '台'];
    for (int i = 0; i < original.length; i++) {
      if (heads.contains(original[i])) {
        headIdx = i;
        break;
      }
    }
    if (headIdx == null) return -1;
    // 残り文字から `計` または `言`+`十` を探す
    int i = headIdx + 1;
    while (i < original.length) {
      if (original[i] == '計') {
        return i + 1;
      }
      if (original[i] == '言') {
        // 続けて `十` を空白を許容して探す
        int j = i + 1;
        while (j < original.length && (original[j] == ' ' ||
            original[j] == '\u3000' || original[j] == '\t')) {
          j++;
        }
        if (j < original.length && original[j] == '十') {
          return j + 1;
        }
      }
      i++;
    }
    return -1;
  }

  /// Step21: 合計ラベル限定の fuzzy 正規化
  ///
  /// `合計` 系のロゴ・部品分解誤認を吸収する（他ラベルは対象外）。
  /// - `言十` → `計` （「計」が偏旁に分解された場合）
  /// - `谷` → `合` （フォントによる類似誤認、合計の文脈でのみ）
  /// - `台` → `合` （同上）
  /// 入力は normalizeLabelText 済みの空白除去文字列を期待する。
  static String _fuzzyTotalLabelText(String normalized) {
    return normalized
        .replaceAll('言十', '計')
        .replaceAll('谷計', '合計')
        .replaceAll('台計', '合計');
  }

  /// fuzzy 合計ラベル候補にネガティブな文脈（小計・税率など）が混在しているか
  static bool _hasTotalNegativeContext(String text) {
    const negative = ['小計', '税率', '対象', '内税', '消費税', 'お釣り', 'お預り'];
    for (final w in negative) {
      if (text.contains(w)) return true;
    }
    return false;
  }

  /// fuzzy ヒット用の弱い `合計` ルール
  static const TotalLabelRule _fuzzyTotalRule = TotalLabelRule('合計', 0.7);

  /// fuzzy 一致時のラベル候補の最大長（原文長として）
  ///
  /// `合 言 十` のように空白を挟んだ場合でも 5 文字以内に収まる想定。
  /// 走査がレシート全体をなめるのを防ぐためのガード値。
  // ignore: unused_field
  static const int _fuzzyLabelMaxOriginalLength = 8;

  /// Step21: 文字列が金額として安全でない文脈か判定する
  ///
  /// 伝票番号・取引番号・電話番号・会員コード等を含む、または
  /// ハッシュ伝票番号・電話番号風の桁構成を含む場合に true を返す。
  @visibleForTesting
  static bool isUnsafeAmountContext(String text) {
    if (_hashSerialPattern.hasMatch(text)) return true;
    if (_phoneLikePattern.hasMatch(text)) return true;
    for (final kw in amountUnsafeContextKeywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  /// Step21: 通貨記号を伴うか判定
  static bool _hasCurrencyMark(String text) {
    return text.contains('¥') || text.contains('￥') || text.contains('円');
  }

  /// Step21: 候補金額が fallback 経路で採用するに十分な信頼があるか
  ///
  /// 通貨記号付き候補のみを安全とみなす。素の数字（特に 6 桁以上）は
  /// 伝票番号・電話番号断片の可能性があるため fallback では除外する。
  static bool _isFallbackSafeAmount(String contextText, int amount) {
    if (_hasCurrencyMark(contextText)) return true;
    // 通貨記号がない場合は短い数字のみ許容（999 円以下は短桁として弱く許容）
    if (amount <= 999) return true;
    return false;
  }

  // ─── 合計金額抽出（テキスト行ベース） ───

  /// 合計ラベル起点で金額を抽出（bbox なし経路）
  ///
  /// 1. 全行をスキャンし、最高 weight のラベル行から金額を抽出
  ///    Step22 改修: 同 weight 内では下部行優先（bottom-up）。
  /// 2. ラベル行が見つからない場合のみ、全行から補助的に候補を探す
  ///    Step22 改修: ラベル候補が文書内に1つでも存在する場合 fallback 抑制。
  @visibleForTesting
  static ScoredResult<int>? extractTotal(List<String> lines) {
    // ── Phase 1: 全行から最高 weight のラベル行を探す（下から上へ走査） ──
    double bestWeight = -1;
    ScoredResult<int>? bestLabelResult;
    // Step22: ラベル候補が文書内に1つでも存在したか（金額ペアリング不能でも true）
    bool anyLabelMatched = false;

    // 下から上へ走査することで、同 weight 内では最下部の行を優先する。
    // （レシートでは最終合計が下部に出ることが多い）
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i];

      // この行の最高 weight ラベルマッチを探す（正規化 + fuzzy 対応）
      final labelMatch = _findBestLabelMatch(line);

      // 除外キーワードのみの行はスキップ（ラベルがあれば除外しない）
      if (totalExcludeKeywords.any((kw) => line.contains(kw)) &&
          labelMatch == null) {
        continue;
      }
      if (labelMatch == null) continue;

      // ラベル候補は存在した（金額が取れなくても fallback 抑制対象）
      anyLabelMatched = true;

      // 現在のベストより低い weight ならスキップ
      if (labelMatch.rule.weight < bestWeight) continue;

      // ラベル直後の部分文字列から金額候補を抽出
      // 行全体を normalizeAmountText すると l→1 + 空白除去で
      // ラベル末尾と金額が結合する問題を回避する（例: Total 200 → T0ta1200）
      final afterLabelIdx = labelMatch.endInOriginal;
      if (afterLabelIdx < 0 || afterLabelIdx > line.length) continue;
      final afterLabel = line.substring(afterLabelIdx);
      final candidates = extractAmountCandidates(afterLabel);
      if (candidates.isEmpty) continue;

      // ラベル直後の最も近い金額候補を選ぶ
      final best = candidates.reduce(
        (a, b) => a.$2 < b.$2 ? a : b,
      );
      // 同 weight の場合は最初に見つかった値（最下部）を保持し、
      // より上の同 weight 行で上書きしない。
      if (labelMatch.rule.weight > bestWeight) {
        bestWeight = labelMatch.rule.weight;
        // ラベル行の金額は高スコア（2.0 基準）
        bestLabelResult = ScoredResult(best.$1, 2.0);

        // PII 観点: 原文行は出さず、ラベル種別・weight・amount のみ。
        _trace(
          'totalCandidate accepted reason=total_label_text '
          'amount=${best.$1} weight=${labelMatch.rule.weight} '
          'label="${labelMatch.rule.pattern}" line_idx=$i',
        );
      }
    }

    if (bestLabelResult != null) return bestLabelResult;

    // Step22: ラベル候補があったが金額ペアリング不能だった場合、
    // fallback で誤った金額を返すより null を返す（誤入力より未取得を優先）
    if (anyLabelMatched) {
      _trace('totalCandidate rejected '
          'reason=fallback_suppressed_due_to_label_candidate');
      return null;
    }

    // ── Phase 2: フォールバック（ラベル行なし → 補助的候補探索） ──
    double bestScore = -1;
    int? bestAmount;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Step21: 伝票番号・電話番号・会員コード文脈は最優先でスキップ
      // （reject 理由を一意に保つため、他の除外条件より先にチェックする）
      if (isUnsafeAmountContext(line)) {
        _trace('totalCandidate rejected reason=unsafe_context line_idx=$i');
        continue;
      }
      // Step22: 商品明細行（商品代金/単価/対象商品 等）を fallback から除外
      if (totalFallbackExcludeKeywords.any((kw) => line.contains(kw))) {
        _trace('totalCandidate rejected reason=product_line_fallback '
            'line_idx=$i');
        continue;
      }
      // 除外行チェック（小計・お釣り・支払行・税率行など）
      if (totalExcludeKeywords.any((kw) => line.contains(kw))) continue;
      if (_datePattern.hasMatch(line)) continue;
      if (_warekiPattern.hasMatch(line)) continue;
      // 既存の 10 桁以上連番のみの行スキップ
      if (_serialNumberPattern.hasMatch(line) &&
          !_hasCurrencyMark(line)) {
        final serialMatch = _serialNumberPattern.firstMatch(line);
        if (serialMatch != null &&
            serialMatch.group(0)!.length ==
                line.replaceAll(RegExp(r'\s'), '').length) {
          _trace('totalCandidate rejected reason=serial_only line_idx=$i');
          continue;
        }
      }
      // Step21: 6 桁以上の素の数字のみの行は伝票番号系として除外
      if (_bareLongDigitsPattern.hasMatch(line)) {
        _trace('totalCandidate rejected reason=bare_long_digits line_idx=$i');
        continue;
      }

      final candidates = extractAmountCandidates(line);
      for (final (amount, _) in candidates) {
        // Step21: 通貨記号なしの大きい数字は fallback では弾く
        if (!_isFallbackSafeAmount(line, amount)) {
          _trace(
            'totalCandidate rejected reason=no_currency_mark amount=$amount line_idx=$i',
          );
          continue;
        }
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
    _trace(
      'totalCandidate accepted reason=fallback_currency amount=$bestAmount',
    );
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
  ///    Step22 改修: pseudoLines を下から上へ走査し、同 weight 内では最下部優先。
  /// 3. ラベル行が見つからない場合は補助的フォールバック
  ///    Step22 改修: ラベル候補が文書内に1つでも存在する場合 fallback 抑制。
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

    // Step24 r56: 画像幅から動的な列整列許容幅を計算（最低 40px）
    // 2160px / 4284px の差分でも相対位置で判定できるようにする
    final estimatedImageWidth = _estimateImageWidth(pseudoLines);
    final alignmentTolerance =
        (estimatedImageWidth * 0.03).clamp(40.0, double.infinity);

    // ── Phase 1: 下から上へ走査し、最高 weight のラベル行から右側金額を採用 ──
    ScoredResult<int>? bestLabelResult;
    double bestLabelWeight = -1;
    double bestLabelScore = -1;
    // Step22: ラベル候補が文書内に1つでも存在したか（金額ペアリング不能でも true）
    bool anyLabelMatched = false;
    // Step23: 検出した合計ラベル候補（Phase 1 通常ペアリング失敗時の近傍探索用）
    final labelCandidates = <_LabelCandidate>[];

    for (int lineIdx = pseudoLines.length - 1; lineIdx >= 0; lineIdx--) {
      final line = pseudoLines[lineIdx];
      // 行内テキストを結合して除外チェック
      final lineText = line.map((t) => t.text.trim()).join(' ');

      // この行で最高 weight のラベルマッチを検索（正規化 + fuzzy 対応）
      OcrToken? labelToken;
      _LabelMatch? lineMatch;

      // 1. 個別トークンからラベルを探す
      for (final token in line) {
        final text = token.text.trim();
        final match = _findBestLabelMatch(text);
        if (match != null &&
            (lineMatch == null || match.rule.weight > lineMatch.rule.weight)) {
          lineMatch = match;
          labelToken = token;
        }
      }

      // 2. 個別トークンで見つからない場合、行結合テキストから探す
      //    （例: `合` + `計` が別トークンのケース）
      if (lineMatch == null) {
        final joinedMatch = _findBestLabelMatch(lineText);
        if (joinedMatch != null) {
          lineMatch = joinedMatch;
          // ラベルパターンの末尾文字を含む最後のトークンを labelToken とする
          // 例: pattern=`合計` → `計` を含むトークンがラベル末尾
          final lastChar =
              joinedMatch.rule.pattern[joinedMatch.rule.pattern.length - 1];
          for (final t in line) {
            if (t.text.contains(lastChar)) {
              labelToken = t;
            }
          }
          labelToken ??= line.first;
        }
      }

      // 除外キーワードのみの行はスキップ（ラベルがあれば除外しない）
      if (totalExcludeKeywords.any((kw) => lineText.contains(kw)) &&
          lineMatch == null) {
        continue;
      }
      if (labelToken == null || lineMatch == null) continue;
      final lineRule = lineMatch.rule;

      // ラベル候補は存在した（金額が取れなくても fallback 抑制対象）
      anyLabelMatched = true;
      // Step23: 近傍探索用にラベル候補を保持し、PII 非保存 trace を出す
      labelCandidates.add(_LabelCandidate(
        lineIdx: lineIdx,
        labelToken: labelToken,
        rule: lineRule,
      ));
      _trace(
        'totalCandidate label_candidate_found '
        'label=${lineRule.pattern} weight=${lineRule.weight} '
        'line_idx=$lineIdx',
      );

      // 現在のベストより低い weight ならスキップ
      if (lineRule.weight < bestLabelWeight) continue;
      // Step22: 同 weight で既にベストが確定している場合、bottom-up で下から
      // 先に確定したものを保持する（下から走査しているため上の行はスキップ）。
      if (lineRule.weight == bestLabelWeight && bestLabelResult != null) {
        continue;
      }

      // ラベルトークン自体に金額が含まれるケース（例: 「合計 ¥334」）
      // ラベル直後の部分文字列から金額を抽出（l→1+空白除去の結合問題を回避）
      final labelText = labelToken.text.trim();
      // トークン内のラベル末尾位置を、トークン単体に対する _findBestLabelMatch で求める
      final tokenMatch = _findBestLabelMatch(labelText);
      final int afterTokenLabelIdx = tokenMatch?.endInOriginal ?? -1;
      if (afterTokenLabelIdx > 0 && afterTokenLabelIdx < labelText.length) {
        final afterTokenLabel = labelText.substring(afterTokenLabelIdx);
        final labelCandidates = extractAmountCandidates(afterTokenLabel);
        if (labelCandidates.isNotEmpty) {
          final best = labelCandidates.reduce(
            (a, b) => a.$2 < b.$2 ? a : b,
          );
          const score = 3.0; // ラベル内金額は最高スコア
          if (lineRule.weight > bestLabelWeight || score > bestLabelScore) {
            bestLabelWeight = lineRule.weight;
            bestLabelScore = score;
            bestLabelResult = ScoredResult(best.$1, score);
          }
        }
      }

      // ラベルの右側にある金額トークンを探す
      bool sameLinePaired = false;
      // Step21: 行グルーピングがゆるい（avgHeight が大きい上部ロゴに引っ張られる）
      // ケースで、税率行の金額が「合計」と同一行扱いされる事故を防ぐ。
      // ラベルトークンとのY中心差が大きいトークンは右側候補から除外する。
      final labelMiddle = labelToken.bbox!.y + labelToken.bbox!.height / 2;
      for (final token in line) {
        if (token.bbox!.x <= labelToken.bbox!.x) continue;
        final text = token.text.trim();
        if (totalExcludeKeywords.any((kw) => text.contains(kw))) continue;
        // Step21: 番号系コンテキストは候補から除外
        if (isUnsafeAmountContext(text)) continue;
        // Step21: Y中心差がトークン高さの 0.6 倍以上 → 別行と判断
        final tokenMiddle = token.bbox!.y + token.bbox!.height / 2;
        final maxH = labelToken.bbox!.height > token.bbox!.height
            ? labelToken.bbox!.height
            : token.bbox!.height;
        if ((tokenMiddle - labelMiddle).abs() > maxH * 0.6) {
          continue;
        }

        final candidates = extractAmountCandidates(text);
        for (final (amount, _) in candidates) {
          // スコア: 同一行右側（2.5）+ ラベルとの近さ
          final xDist = token.bbox!.x - labelToken.bbox!.x;
          final proximityBonus =
              (1.0 / (1.0 + xDist / 100.0)).clamp(0.0, 0.5);
          final score = 2.5 + proximityBonus;
          sameLinePaired = true;
          if (lineRule.weight > bestLabelWeight || score > bestLabelScore) {
            bestLabelWeight = lineRule.weight;
            bestLabelScore = score;
            bestLabelResult = ScoredResult(amount, score);
            _trace(
              'totalCandidate accepted reason=total_label_same_line '
              'amount=$amount weight=${lineRule.weight}',
            );
          }
        }
      }

      // Step21: 同一行に右側金額が見つからない場合、直下行も探索する
      // （湾曲・斜めレシートで合計ラベルと金額が別行に分かれるケース）
      if (!sameLinePaired && lineIdx + 1 < pseudoLines.length) {
        final nextLine = pseudoLines[lineIdx + 1];
        final nextLineText = nextLine.map((t) => t.text.trim()).join(' ');
        // 直下行が支払/税率行などの場合は弾く
        // Step23: 商品代金/単価/数量 等の明細行も直下ペアリング対象から除外する
        // （直下に `商品代金 ¥651` が来た場合に 651 を合計として誤採用しない）
        if (!totalExcludeKeywords.any((kw) => nextLineText.contains(kw)) &&
            !totalFallbackExcludeKeywords
                .any((kw) => nextLineText.contains(kw)) &&
            !isUnsafeAmountContext(nextLineText)) {
          for (final token in nextLine) {
            // ラベルトークンより右、または同等の x 位置にあるトークン
            if (token.bbox!.x < labelToken.bbox!.x - 20) continue;
            final text = token.text.trim();
            if (totalExcludeKeywords.any((kw) => text.contains(kw))) continue;
            final candidates = extractAmountCandidates(text);
            for (final (amount, _) in candidates) {
              // Step24 r56: 直下行ペアリングにも弱小額ガードを適用。
              // 通貨記号なし `amount <= 999` は強い列整列または非除外文脈が
              // 必須。これにより `合計` 直下に孤立した `148` を
              // `total_label_below_line` として誤採用するのを防ぐ。
              final hasCurrency = _hasCurrencyMark(text);
              if (!_passesWeakSmallAmountGuard(
                pseudoLines: pseudoLines,
                token: token,
                amount: amount,
                hasCurrency: hasCurrency,
                delta: 1,
                labelLineIdx: lineIdx,
                isSameLineRight: false,
                alignmentTolerance: alignmentTolerance,
                acceptedReason: 'total_label_below_line',
              )) {
                continue;
              }
              // 直下行は弱めスコア（2.0）
              const score = 2.0;
              if (lineRule.weight > bestLabelWeight ||
                  score > bestLabelScore) {
                bestLabelWeight = lineRule.weight;
                bestLabelScore = score;
                bestLabelResult = ScoredResult(amount, score);
                _trace(
                  'totalCandidate accepted reason=total_label_below_line '
                  'amount=$amount weight=${lineRule.weight}',
                );
              }
            }
          }
        }
      }
    }

    if (bestLabelResult != null) return bestLabelResult;

    // Step23: ラベル候補があり Phase 1 通常ペアリング失敗 → 近傍探索を試みる
    if (labelCandidates.isNotEmpty) {
      final nearbyResult = _searchNearbyTotalAmounts(
        pseudoLines,
        labelCandidates,
        alignmentTolerance,
      );
      if (nearbyResult != null) return nearbyResult;
    }

    // Step22: ラベル候補があったが金額ペアリング不能だった場合、
    // fallback で誤った金額を返すより null を返す（誤入力より未取得を優先）
    if (anyLabelMatched) {
      // Step25 T25-02 / T25-03: ラベル候補あり×total=null のときだけ
      // 近傍スキャンと文書全体の金額候補 inventory trace を出す
      // （観測専用、PII 非保存）。成功ケースでは scan_* / amount_inventory_* は
      // 出さない。
      _emitNearbyScanTrace(pseudoLines, labelCandidates, alignmentTolerance);
      _emitAmountInventoryTrace(
        pseudoLines,
        labelCandidates,
        alignmentTolerance,
      );
      _trace('totalCandidate rejected '
          'reason=fallback_suppressed_due_to_label_candidate');
      return null;
    }

    // ── Phase 2: フォールバック（ラベル行なし → 全行から補助的候補） ──
    double bestScore = -1;
    int? bestAmount;

    for (int lineIdx = 0; lineIdx < pseudoLines.length; lineIdx++) {
      final line = pseudoLines[lineIdx];
      final lineText = line.map((t) => t.text.trim()).join(' ');

      // Step21: 伝票番号・電話番号・会員コード文脈は最優先でスキップ
      if (isUnsafeAmountContext(lineText)) {
        _trace(
          'totalCandidate rejected reason=unsafe_context_bbox '
          'line_idx=$lineIdx',
        );
        continue;
      }
      // Step22: 商品明細行（商品代金/単価/対象商品 等）を fallback から除外
      if (totalFallbackExcludeKeywords.any((kw) => lineText.contains(kw))) {
        _trace(
          'totalCandidate rejected reason=product_line_fallback '
          'line_idx=$lineIdx',
        );
        continue;
      }
      if (totalExcludeKeywords.any((kw) => lineText.contains(kw))) continue;
      if (_datePattern.hasMatch(lineText)) continue;
      if (_warekiPattern.hasMatch(lineText)) continue;
      // Step21: 10 桁以上連番のみの行はスキップ
      if (_serialNumberPattern.hasMatch(lineText) &&
          !_hasCurrencyMark(lineText)) {
        _trace(
          'totalCandidate rejected reason=serial_or_receipt_number '
          'line_idx=$lineIdx',
        );
        continue;
      }
      // Step21: 6 桁以上の素の数字のみの行は伝票番号系として除外
      if (_bareLongDigitsPattern.hasMatch(lineText.replaceAll(' ', ''))) {
        _trace(
          'totalCandidate rejected reason=bare_long_digits_bbox '
          'line_idx=$lineIdx',
        );
        continue;
      }

      for (final token in line) {
        final tokenText = token.text;
        if (isUnsafeAmountContext(tokenText)) continue;
        final candidates = extractAmountCandidates(tokenText);
        for (final (amount, _) in candidates) {
          // Step21: 通貨記号なしの大きい数字は fallback では弾く
          if (!_isFallbackSafeAmount(lineText, amount)) {
            _trace(
              'totalCandidate rejected reason=no_currency_mark_bbox '
              'amount=$amount line_idx=$lineIdx',
            );
            continue;
          }
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
    _trace(
      'totalCandidate accepted reason=fallback_currency_bbox '
      'amount=$bestAmount',
    );
    return ScoredResult(bestAmount, bestScore);
  }

  /// Step23: 検出済み合計ラベル候補の近傍（上下 2 行）から金額を探す
  ///
  /// Phase 1 通常ペアリング（同一行・直下行）で失敗した場合に呼ばれる。
  /// 商品代金 / 支払 / 税率 / 小計 / 釣銭 / 伝票番号など、合計として
  /// 採用すべきでない文脈は除外し、PII 非保存 trace で reject 理由を残す。
  static ScoredResult<int>? _searchNearbyTotalAmounts(
    List<List<OcrToken>> pseudoLines,
    List<_LabelCandidate> labelCandidates,
    double alignmentTolerance,
  ) {
    // 近傍探索専用の除外語（行内に1つでも含まれたら採用不可）
    // 既存の totalExcludeKeywords / totalFallbackExcludeKeywords を再利用しつつ、
    // 釣銭系を行レベルで弾く。
    bool isExcludedLine(String lineText) {
      if (isUnsafeAmountContext(lineText)) return true;
      if (totalExcludeKeywords.any((kw) => lineText.contains(kw))) return true;
      if (totalFallbackExcludeKeywords.any((kw) => lineText.contains(kw))) {
        return true;
      }
      return false;
    }

    double bestScore = -1;
    int? bestAmount;
    double bestWeight = -1;
    const double scoreThreshold = 1.5;

    for (final cand in labelCandidates) {
      final labelMiddleY = cand.labelToken.bbox!.y +
          cand.labelToken.bbox!.height / 2;
      final labelLeftX = cand.labelToken.bbox!.x;

      // 上下 2 行範囲を走査（同一行はラベル token より右側のみ）
      final fromIdx = (cand.lineIdx - 2).clamp(0, pseudoLines.length - 1);
      final toIdx = (cand.lineIdx + 2).clamp(0, pseudoLines.length - 1);

      for (int idx = fromIdx; idx <= toIdx; idx++) {
        final line = pseudoLines[idx];
        final lineText = line.map((t) => t.text.trim()).join(' ');

        // 行レベルで除外文脈を判定（商品代金 / PayPay / 税率 / 小計 / 伝票番号 等）
        if (isExcludedLine(lineText)) {
          _trace(
            'totalCandidate nearby_amount_rejected '
            'reason=excluded_context line_idx=$idx '
            'label_line_idx=${cand.lineIdx}',
          );
          continue;
        }

        // 位置スコア: 同一行 2.5 / 直下 2.2 / 直上 1.8 / 2 行差 1.4
        final delta = idx - cand.lineIdx;
        double posScore;
        switch (delta) {
          case 0:
            posScore = 2.5;
            break;
          case 1:
            posScore = 2.2;
            break;
          case -1:
            posScore = 1.8;
            break;
          default:
            posScore = 1.4;
        }

        for (final token in line) {
          final text = token.text.trim();
          // トークン単位でも安全文脈を確認
          if (isUnsafeAmountContext(text)) {
            _trace(
              'totalCandidate nearby_amount_rejected '
              'reason=unsafe_context line_idx=$idx',
            );
            continue;
          }
          // 同一行の場合は labelToken 自身および左側を弾く
          if (delta == 0 && token.bbox!.x <= labelLeftX) continue;

          final candidates = extractAmountCandidates(text);
          for (final (amount, _) in candidates) {
            // 通貨記号なし大数字の弱フィルタ（伝票番号断片対策）
            if (!_isFallbackSafeAmount(text, amount)) {
              _trace(
                'totalCandidate nearby_amount_rejected '
                'reason=no_currency_mark line_idx=$idx amount=$amount',
              );
              continue;
            }

            final hasCurrency = _hasCurrencyMark(text);
            final tokenLeftX = token.bbox!.x;
            final isSameLineRight = (delta == 0 && tokenLeftX > labelLeftX);

            // Step24 r56: 通貨記号なし弱小額ガードを共通ヘルパー化。
            // 同一行/直下行/近傍探索のどの経路でも同じ条件で reject する。
            if (!_passesWeakSmallAmountGuard(
              pseudoLines: pseudoLines,
              token: token,
              amount: amount,
              hasCurrency: hasCurrency,
              delta: delta,
              labelLineIdx: cand.lineIdx,
              isSameLineRight: isSameLineRight,
              alignmentTolerance: alignmentTolerance,
              acceptedReason: 'total_label_nearby',
            )) {
              continue;
            }

            // ラベル weight × 0.5（合計=1.0 → 0.5、ご請求=0.8 → 0.4）
            final weightScore = cand.rule.weight * 0.5;
            // labelより右なら +0.5、左で同程度なら +0.1
            final xScore = tokenLeftX > labelLeftX ? 0.5 : 0.1;
            // 通貨記号ボーナス
            final currencyScore = hasCurrency ? 0.2 : 0.0;
            // Y 距離ペナルティ（同一/隣接以外で）
            final tokenMiddleY =
                token.bbox!.y + token.bbox!.height / 2;
            final yDistRatio = (tokenMiddleY - labelMiddleY).abs() /
                (cand.labelToken.bbox!.height + 1);
            final yPenalty = (yDistRatio * 0.05).clamp(0.0, 0.4);

            final score =
                posScore + weightScore + xScore + currencyScore - yPenalty;

            if (score < scoreThreshold) {
              _trace(
                'totalCandidate nearby_amount_rejected '
                'reason=below_threshold line_idx=$idx amount=$amount',
              );
              continue;
            }

            if (cand.rule.weight > bestWeight ||
                (cand.rule.weight == bestWeight && score > bestScore)) {
              bestScore = score;
              bestAmount = amount;
              bestWeight = cand.rule.weight;
              _bestNearbyLineIdx = idx;
              _bestNearbyLabelLineIdx = cand.lineIdx;
              _bestNearbyDelta = delta;
              _bestNearbyHasCurrency = hasCurrency;
            }
          }
        }
      }
    }

    if (bestAmount == null) return null;
    _trace(
      'totalCandidate accepted reason=total_label_nearby '
      'amount=$bestAmount weight=$bestWeight '
      'line_idx=$_bestNearbyLineIdx '
      'label_line_idx=$_bestNearbyLabelLineIdx '
      'delta=$_bestNearbyDelta '
      'has_currency=$_bestNearbyHasCurrency '
      'score=${bestScore.toStringAsFixed(2)}',
    );
    return ScoredResult(bestAmount, bestScore);
  }

  // Step24: 採用 trace に必要な近傍メタを保持する一時フィールド
  static int _bestNearbyLineIdx = -1;
  static int _bestNearbyLabelLineIdx = -1;
  static int _bestNearbyDelta = 0;
  static bool _bestNearbyHasCurrency = false;

  /// Step24: 強い列整列判定
  ///
  /// 候補tokenの右端Xが、近傍領域(ラベル行±2行)に存在する他の金額token
  /// の右端Xと近似（中央値±許容幅）している場合のみ「強い列整列」と判定する。
  /// 整列基準となる他の金額tokenが無い場合は false（採用不可）。
  ///
  /// Step24 r56: 許容幅 (alignmentTolerance) は呼び出し元で画像幅から計算した値を渡す。
  /// 2160px / 4284px の差分で固定 40px が妥当でないため可変化。
  ///
  /// Step24 r57: 整列基準から除外文脈行（税率/商品代金/支払/伝票番号 等）の
  /// 金額 token を取り除く。例えば `税率 8%対象 148` の `148` を整列基準として
  /// 利用すると、通貨記号なし小額が誤って強い列整列扱いになる。
  static bool _hasStrongAmountColumnAlignment(
    List<List<OcrToken>> pseudoLines,
    OcrToken target,
    int labelLineIdx,
    double alignmentTolerance,
  ) {
    if (target.bbox == null) return false;
    final fromIdx = (labelLineIdx - 2).clamp(0, pseudoLines.length - 1);
    final toIdx = (labelLineIdx + 2).clamp(0, pseudoLines.length - 1);
    final amountRights = <double>[];
    for (int i = fromIdx; i <= toIdx; i++) {
      // Step24 r57: 整列基準から除外文脈行を弾く
      final lineText = pseudoLines[i].map((tk) => tk.text.trim()).join(' ');
      if (isUnsafeAmountContext(lineText)) continue;
      if (totalExcludeKeywords.any((kw) => lineText.contains(kw))) continue;
      if (totalFallbackExcludeKeywords.any((kw) => lineText.contains(kw))) {
        continue;
      }
      for (final tk in pseudoLines[i]) {
        if (identical(tk, target)) continue;
        if (tk.bbox == null) continue;
        final candidates = extractAmountCandidates(tk.text.trim());
        if (candidates.isEmpty) continue;
        amountRights.add(tk.bbox!.x + tk.bbox!.width);
      }
    }
    if (amountRights.isEmpty) return false;
    amountRights.sort();
    final median = amountRights[amountRights.length ~/ 2];
    final tokenRight = target.bbox!.x + target.bbox!.width;
    return (tokenRight - median).abs() <= alignmentTolerance;
  }

  /// Step24 r56: 画像幅推定（pseudoLines 全体の bbox 右端最大値）
  static double _estimateImageWidth(List<List<OcrToken>> pseudoLines) {
    double maxRight = 0;
    for (final line in pseudoLines) {
      for (final t in line) {
        if (t.bbox == null) continue;
        final right = t.bbox!.x + t.bbox!.width;
        if (right > maxRight) maxRight = right;
      }
    }
    return maxRight;
  }

  /// Step24 r56: 隣接窓（idx-1..idx+1）に商品/支払/税系が混在し、
  /// 「合計」系の強ラベルが無ければ採用不可と判定する。
  /// 通貨記号なし小額専用（通貨記号付きは既存仕様維持）。
  ///
  /// Step24 r57: 税系除外の緩和条件を厳格化。
  /// 隣接行に通常の `合計` ラベルがあるだけでは緩和しない。
  /// 候補行自身が「税込合計 / 合計(税込)」のように合計と税が共存する強合計表現
  /// である場合のみ、税系隣接文脈による reject を緩める。
  static bool _hasUnsafeNeighborContext(
    List<List<OcrToken>> pseudoLines,
    int idx,
    int labelLineIdx,
  ) {
    const taxKeywords = ['税率', '対象', '内税', '外税', '消費税', '税額'];
    const productKeywords = ['商品代金', '商品', '単価', '点数', '数量',
        '対象商品'];
    const paymentKeywords = ['PayPay', '支払', '現金', 'カード',
        '電子マネー', '預り', 'お預り', 'お釣り', 'おつり'];

    // Step24 r57: 候補行自身に強合計+税の共存があるか判定
    // 例: `合計(税込) ¥1,580`, `税込合計 1,580`
    // 隣接行の通常の `合計` ラベルだけでは緩和しない。
    bool isCandidateRowStrongTotalWithTax() {
      if (idx < 0 || idx >= pseudoLines.length) return false;
      final t = pseudoLines[idx].map((tk) => tk.text.trim()).join('');
      const totalWords = ['合計', 'ご請求', '総合計'];
      const taxCoexistWords = ['税込', '税抜', '内税', '外税'];
      final hasTotal = totalWords.any((kw) => t.contains(kw));
      final hasTaxCoexist = taxCoexistWords.any((kw) => t.contains(kw));
      return hasTotal && hasTaxCoexist;
    }

    final relaxTax = isCandidateRowStrongTotalWithTax();
    for (int i = idx - 1; i <= idx + 1; i++) {
      if (i < 0 || i >= pseudoLines.length) continue;
      if (i == idx) continue; // 候補行自身は別途行レベル除外で評価済み
      final t = pseudoLines[i].map((tk) => tk.text.trim()).join(' ');
      if (productKeywords.any((kw) => t.contains(kw))) return true;
      if (paymentKeywords.any((kw) => t.contains(kw))) return true;
      if (taxKeywords.any((kw) => t.contains(kw))) {
        if (!relaxTax) return true;
      }
    }
    return false;
  }

  /// Step24 r56: 通貨記号なし弱小額ガード（共通ヘルパー）
  ///
  /// 通貨記号なしかつ `amount <= 999` の候補に対して以下を強制する:
  ///   - 2行差以上 (|delta| >= 2) は採用不可
  ///   - 同一行ラベル右側でない場合は強い列整列 (`_hasStrongAmountColumnAlignment`) 必須
  ///   - 隣接窓 (idx-1..idx+1) に税/商品/支払系の文脈がある場合は棄却
  ///
  /// Phase 1 の同一行/直下行ペアリングと、Phase 1.5 の近傍探索の両方から
  /// 呼び出し、`total_label_below_line` バイパスを塞ぐ。
  /// 戻り値 true: ガードを通過（採用してよい）。false: reject（PII 非保存 trace あり）。
  static bool _passesWeakSmallAmountGuard({
    required List<List<OcrToken>> pseudoLines,
    required OcrToken token,
    required int amount,
    required bool hasCurrency,
    required int delta,
    required int labelLineIdx,
    required bool isSameLineRight,
    required double alignmentTolerance,
    required String acceptedReason,
  }) {
    if (hasCurrency || amount > 999) return true;
    final candIdx = labelLineIdx + delta;
    if (delta.abs() >= 2) {
      _trace(
        'totalCandidate weak_small_amount_rejected '
        'reason=weak_alignment route=$acceptedReason '
        'line_idx=$candIdx label_line_idx=$labelLineIdx '
        'amount=$amount delta=$delta',
      );
      return false;
    }
    if (!isSameLineRight) {
      final hasStrong = _hasStrongAmountColumnAlignment(
        pseudoLines,
        token,
        labelLineIdx,
        alignmentTolerance,
      );
      if (!hasStrong) {
        _trace(
          'totalCandidate weak_small_amount_rejected '
          'reason=weak_small_amount route=$acceptedReason '
          'line_idx=$candIdx label_line_idx=$labelLineIdx '
          'amount=$amount has_currency=false delta=$delta',
        );
        return false;
      }
    }
    if (_hasUnsafeNeighborContext(pseudoLines, candIdx, labelLineIdx)) {
      _trace(
        'totalCandidate weak_small_amount_rejected '
        'reason=neighbor_excluded_context route=$acceptedReason '
        'line_idx=$candIdx label_line_idx=$labelLineIdx '
        'amount=$amount delta=$delta',
      );
      return false;
    }
    return true;
  }

  // ─── Step25: 候補可視化 trace（PII 非保存） ───
  //
  // 観測専用ヘルパー。抽出スコア・採用条件には影響しない。
  // assert + kDebugMode 経由の `_trace()` に乗せ、release ビルドでは出力しない。
  // OCR 行原文・住所・電話番号・会員番号・伝票番号全文は trace に含めない。

  /// 画像高さ推定（pseudoLines 全体の bbox 下端最大値）
  static double _estimateImageHeight(List<List<OcrToken>> pseudoLines) {
    double maxBottom = 0;
    for (final line in pseudoLines) {
      for (final t in line) {
        if (t.bbox == null) continue;
        final bottom = t.bbox!.y + t.bbox!.height;
        if (bottom > maxBottom) maxBottom = bottom;
      }
    }
    return maxBottom;
  }

  /// bbox を 3 段階バケット化（左/中央/右、上/中/下）して PII を残さない位置情報を返す
  static (String xBucket, String yBucket) _bucketBbox(
    OcrToken token,
    double imageWidth,
    double imageHeight,
  ) {
    if (token.bbox == null) return ('center', 'mid');
    final cx = token.bbox!.x + token.bbox!.width / 2;
    final cy = token.bbox!.y + token.bbox!.height / 2;
    String xBucket = 'center';
    if (imageWidth > 0) {
      if (cx < imageWidth / 3) {
        xBucket = 'left';
      } else if (cx > imageWidth * 2 / 3) {
        xBucket = 'right';
      }
    }
    String yBucket = 'mid';
    if (imageHeight > 0) {
      if (cy < imageHeight / 3) {
        yBucket = 'top';
      } else if (cy > imageHeight * 2 / 3) {
        yBucket = 'bottom';
      }
    }
    return (xBucket, yBucket);
  }

  /// Step25: 採用/棄却を予測する分類（trace 用、固定 enum 文字列）
  ///
  /// 実際の抽出ロジックを流用せず、行/トークン状態から分類のみを返す。
  /// 戻り値は `would_accept_*` / `would_reject_*` / `outside_nearby_window` /
  /// `not_amount` の固定文字列。
  static String _classifyAmountForTrace({
    required List<List<OcrToken>> pseudoLines,
    required int lineIdx,
    required int labelLineIdx,
    required OcrToken token,
    required int amount,
    required double alignmentTolerance,
    required bool consideredOutsideWindow,
  }) {
    if (consideredOutsideWindow) return 'outside_nearby_window';
    final lineText =
        pseudoLines[lineIdx].map((t) => t.text.trim()).join(' ');
    if (isUnsafeAmountContext(lineText)) {
      return 'would_reject_excluded_context';
    }
    if (totalExcludeKeywords.any((kw) => lineText.contains(kw))) {
      return 'would_reject_excluded_context';
    }
    if (totalFallbackExcludeKeywords.any((kw) => lineText.contains(kw))) {
      return 'would_reject_excluded_context';
    }
    if (_serialNumberPattern.hasMatch(lineText) &&
        !_hasCurrencyMark(lineText)) {
      return 'would_reject_serial_or_receipt_number';
    }
    if (_bareLongDigitsPattern.hasMatch(lineText.replaceAll(' ', ''))) {
      return 'would_reject_serial_or_receipt_number';
    }
    final text = token.text.trim();
    final hasCurrency = _hasCurrencyMark(text);
    final delta = lineIdx - labelLineIdx;
    if (!hasCurrency && amount <= 999) {
      if (delta.abs() >= 2) return 'would_reject_weak_small_amount';
      if (_hasUnsafeNeighborContext(pseudoLines, lineIdx, labelLineIdx)) {
        return 'would_reject_neighbor_context';
      }
      if (delta != 0) {
        final hasStrong = _hasStrongAmountColumnAlignment(
          pseudoLines,
          token,
          labelLineIdx,
          alignmentTolerance,
        );
        if (!hasStrong) return 'would_reject_weak_small_amount';
      }
    }
    if (!hasCurrency && amount > 999) {
      if (!_isFallbackSafeAmount(lineText, amount)) {
        return 'would_reject_no_currency_mark';
      }
    }
    if (delta == 0) return 'would_accept_same_line';
    if (delta == 1) return 'would_accept_below_line';
    return 'would_accept_nearby';
  }

  /// Step25 T25-02: ラベル近傍スキャン trace
  ///
  /// `_searchNearbyTotalAmounts` の冒頭で呼び出され、抽出ロジックには影響しない。
  /// 各ラベル候補について scan_start / scan_line / scan_summary を出力する。
  /// `scan_line` は行原文を含めず、金額値・行 index・分類のみを残す。
  static void _emitNearbyScanTrace(
    List<List<OcrToken>> pseudoLines,
    List<_LabelCandidate> labelCandidates,
    double alignmentTolerance,
  ) {
    if (labelCandidates.isEmpty) return;
    int totalBboxTokens = 0;
    for (final line in pseudoLines) {
      totalBboxTokens += line.length;
    }
    for (final cand in labelCandidates) {
      final fromIdx = (cand.lineIdx - 2).clamp(0, pseudoLines.length - 1);
      final toIdx = (cand.lineIdx + 2).clamp(0, pseudoLines.length - 1);
      _trace(
        'totalCandidate scan_start '
        'label_line_idx=${cand.lineIdx} '
        'window=2 '
        'token_count=$totalBboxTokens',
      );
      int rejectedCount = 0;
      int acceptedCount = 0;
      int amountTokens = 0;
      for (int idx = fromIdx; idx <= toIdx; idx++) {
        final line = pseudoLines[idx];
        final delta = idx - cand.lineIdx;
        final lineText = line.map((t) => t.text.trim()).join(' ');
        final amounts = <int>[];
        bool anyHasCurrency = false;
        OcrToken? primaryToken;
        int? primaryAmount;
        for (final tk in line) {
          final text = tk.text.trim();
          final cands = extractAmountCandidates(text);
          if (cands.isEmpty) continue;
          if (_hasCurrencyMark(text)) anyHasCurrency = true;
          for (final (a, _) in cands) {
            amounts.add(a);
            primaryToken ??= tk;
            primaryAmount ??= a;
          }
        }
        amountTokens += amounts.length;
        final lineExcluded = isUnsafeAmountContext(lineText) ||
            totalExcludeKeywords.any((kw) => lineText.contains(kw)) ||
            totalFallbackExcludeKeywords.any((kw) => lineText.contains(kw));
        final neighborUnsafe =
            _hasUnsafeNeighborContext(pseudoLines, idx, cand.lineIdx);
        final hasWeakSmall = amounts.any((a) => a <= 999) && !anyHasCurrency;
        bool rightAligned = false;
        if (primaryToken != null) {
          rightAligned = _hasStrongAmountColumnAlignment(
            pseudoLines,
            primaryToken,
            cand.lineIdx,
            alignmentTolerance,
          );
        }
        String classification;
        if (amounts.isEmpty) {
          classification = 'not_amount';
        } else {
          classification = _classifyAmountForTrace(
            pseudoLines: pseudoLines,
            lineIdx: idx,
            labelLineIdx: cand.lineIdx,
            token: primaryToken!,
            amount: primaryAmount!,
            alignmentTolerance: alignmentTolerance,
            consideredOutsideWindow: false,
          );
        }
        if (classification.startsWith('would_accept_')) {
          acceptedCount++;
        } else if (classification != 'not_amount') {
          rejectedCount++;
        }
        // amount_candidates は最大 5 件にcap（PII 観点）
        final cappedAmounts = amounts.take(5).join(',');
        _trace(
          'totalCandidate scan_line '
          'line_idx=$idx label_line_idx=${cand.lineIdx} '
          'delta=$delta '
          'amount_candidates=[$cappedAmounts] '
          'has_currency=$anyHasCurrency '
          'excluded=$lineExcluded '
          'weak_small=$hasWeakSmall '
          'neighbor_excluded=$neighborUnsafe '
          'right_aligned=$rightAligned '
          'route=total_label_nearby '
          'classification=$classification',
        );
      }
      _trace(
        'totalCandidate scan_summary '
        'label_line_idx=${cand.lineIdx} '
        'total_amount_tokens=$amountTokens '
        'accepted_candidates=$acceptedCount '
        'rejected_candidates=$rejectedCount',
      );
    }
  }

  /// Step25 T25-03: 文書全体の金額候補 inventory trace
  ///
  /// `labelCandidates` が 1 件以上あり、最終 `totalAmount=null` のときだけ呼ぶ。
  /// 文書内の各金額 token に対し、近傍窓内なら `would_accept_*` / `would_reject_*`、
  /// 近傍窓外なら `outside_nearby_window` を分類として付ける。
  /// 出力は最大 [maxEmitted] 件で cap し、ハイライト件数を `capped` で残す。
  static void _emitAmountInventoryTrace(
    List<List<OcrToken>> pseudoLines,
    List<_LabelCandidate> labelCandidates,
    double alignmentTolerance, {
    int maxEmitted = 20,
  }) {
    if (labelCandidates.isEmpty) return;
    final reference = labelCandidates.first;
    final imageWidth = _estimateImageWidth(pseudoLines);
    final imageHeight = _estimateImageHeight(pseudoLines);
    _trace(
      'totalCandidate amount_inventory_start '
      'reason=label_present_total_null '
      'max_candidates=$maxEmitted',
    );
    int total = 0;
    int emitted = 0;
    for (int idx = 0; idx < pseudoLines.length; idx++) {
      final line = pseudoLines[idx];
      for (final tk in line) {
        if (tk.bbox == null) continue;
        final text = tk.text.trim();
        final cands = extractAmountCandidates(text);
        if (cands.isEmpty) continue;
        for (final (amount, _) in cands) {
          total++;
          if (emitted >= maxEmitted) continue;
          final delta = idx - reference.lineIdx;
          final outside = delta.abs() > 2;
          final hasCurrency = _hasCurrencyMark(text);
          final lineText = line.map((t) => t.text.trim()).join(' ');
          final lineExcluded = isUnsafeAmountContext(lineText) ||
              totalExcludeKeywords.any((kw) => lineText.contains(kw)) ||
              totalFallbackExcludeKeywords.any((kw) => lineText.contains(kw));
          final isWeakSmall = !hasCurrency && amount <= 999;
          final classification = _classifyAmountForTrace(
            pseudoLines: pseudoLines,
            lineIdx: idx,
            labelLineIdx: reference.lineIdx,
            token: tk,
            amount: amount,
            alignmentTolerance: alignmentTolerance,
            consideredOutsideWindow: outside,
          );
          final (xBucket, yBucket) =
              _bucketBbox(tk, imageWidth, imageHeight);
          _trace(
            'totalCandidate amount_inventory '
            'line_idx=$idx '
            'delta_from_label=$delta '
            'amount=$amount '
            'has_currency=$hasCurrency '
            'excluded=$lineExcluded '
            'weak_small=$isWeakSmall '
            'y_bucket=$yBucket '
            'x_bucket=$xBucket '
            'classification=$classification',
          );
          emitted++;
        }
      }
    }
    _trace(
      'totalCandidate amount_inventory_summary '
      'total_candidates=$total '
      'emitted=$emitted '
      'capped=${total > emitted}',
    );
  }

  // ─── Step21: チェーン名正規化 ───

  /// Step22 N-2: source 付きでチェーン名を検出する（exact / fragments /
  /// segmented_fragments の区別を呼び出し元に渡すため）
  ///
  /// hasBbox=true の場合は上部 35% を対象。bbox が無い場合は先頭 N 行を対象。
  static _ChainMatchResult? _detectChainNameWithSource(
    List<OcrToken> tokens,
    List<String> lines, {
    required bool hasBbox,
  }) {
    if (hasBbox) {
      final bboxTokens = tokens.where((t) => t.bbox != null).toList();
      if (bboxTokens.isEmpty) return _detectChainNameWithSourceFromLines(lines);
      double maxY = 0;
      for (final t in bboxTokens) {
        final bottom = t.bbox!.y + t.bbox!.height;
        if (bottom > maxY) maxY = bottom;
      }
      final upperThreshold = maxY * 0.35;
      final upperTexts = <String>[];
      for (final t in bboxTokens) {
        if (t.bbox!.y < upperThreshold) {
          upperTexts.add(t.text.trim());
        }
      }
      if (upperTexts.isEmpty) return null;
      return _matchChainRuleWithSource(upperTexts);
    }
    return _detectChainNameWithSourceFromLines(lines);
  }

  /// 行リスト先頭領域から source 付きでチェーン名を検出する（bbox なし経路）
  static _ChainMatchResult? _detectChainNameWithSourceFromLines(
    List<String> lines,
  ) {
    if (lines.isEmpty) return null;
    // 上部 6 行（_merchantSearchLines + α）を検索対象とする
    final searchCount = lines.length < 6 ? lines.length : 6;
    final upperLines = lines.sublist(0, searchCount);
    return _matchChainRuleWithSource(upperLines);
  }

  /// チェーン判定用にトークン文字列を内部セグメントへ分割する
  ///
  /// 区切り文字: 半角/全角空白、ハイフン類（`-` `－` `ー` `‐` `―`）、
  /// 中黒（`・`）、`/`、`|`、タブ。
  ///
  /// Step22 改修: ロゴ崩れで `ピ セブ フン - イ ルレ ル ブン` のように
  /// 1トークン/1行に潰れたケースで、group A（seven 系）と group B（eleven 系）が
  /// 別セグメントに出現する場合のみ正規化可能とする。
  /// 同一セグメント内（例: `セブンスター` 単独）の重複断片は不採用にする。
  static List<String> _segmentChainText(String text) {
    final separator = RegExp(
      r'[ \t\u3000\-\u30FC\u2010\u2011\u2012\u2013\u2014\u2015\uFF0D・/|]+',
    );
    return text
        .split(separator)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// チェーン名ルールに対してマッチングを行う
  ///
  /// 確定方針（Step22 改修）:
  /// 1. [MerchantChainRule.excludePatterns] が含まれていれば確定しない。
  /// 2. [MerchantChainRule.exactPatterns] が含まれていれば単独で確定
  ///    （空白・ハイフン除去後の連結文字列に対する一致）。
  /// 3. [MerchantChainRule.requiredFragmentGroups] の全グループから
  ///    1 件以上のヒットが揃った場合のみ確定。
  ///
  /// group 判定はセグメント単位で行う:
  /// - 各トークンは [_segmentChainText] で内部分割される
  /// - 同一セグメント内に group A と group B の両方が出現しても採用しない
  /// - group A セグメントを除いた残りセグメントから group B 以降の断片を探す
  ///
  /// これにより:
  /// - `セブンスター 喫茶` (1トークン) → `[セブンスター, 喫茶]`
  ///   `セブンスター` は group A セグメント。group B 断片は他セグメントになく不成立。
  /// - `ピ セブ フン - イ ルレ ル ブン` (1トークン) →
  ///   `[ピ, セブ, フン, イ, ルレ, ル, ブン]`
  ///   `セブ` セグメントが group A、`ブン` セグメントが group B → 成立。
  ///
  /// Step22 N-2: 判定経路（exact / fragments / segmented_fragments）を含む内部版
  static _ChainMatchResult? _matchChainRuleWithSource(List<String> texts) {
    // セグメント単位の正規化リストと、トークン全体の連結文字列を作る。
    // - segments: セグメント単位（group A/B 判定用、由来 texts index を保持）
    // - joinedNormalized: 空白・ハイフン除去した連結（exact/exclude 一致用）
    final segments = <(String, int)>[];
    final normalizedTokens = <String>[];
    for (int ti = 0; ti < texts.length; ti++) {
      final t = texts[ti];
      // exact / exclude 用は空白・ハイフン除去のみ（連結部分一致を許す）
      final tNorm = t
          .replaceAll(' ', '')
          .replaceAll('\u3000', '')
          .toLowerCase();
      normalizedTokens.add(tNorm);
      // group 判定用はセグメント分割（由来 texts index を保持）
      for (final seg in _segmentChainText(t)) {
        final segNorm =
            seg.replaceAll(' ', '').replaceAll('\u3000', '').toLowerCase();
        if (segNorm.isNotEmpty) {
          segments.add((segNorm, ti));
        }
      }
    }
    final joinedNormalized = normalizedTokens.join('|');

    for (final rule in chainRules) {
      // 1. 除外パターン（連結文字列に対して一致判定）
      bool excluded = false;
      for (final ex in rule.excludePatterns) {
        final exNorm = ex
            .replaceAll(' ', '')
            .replaceAll('\u3000', '')
            .toLowerCase();
        if (exNorm.isEmpty) continue;
        if (joinedNormalized.contains(exNorm)) {
          excluded = true;
          break;
        }
      }
      if (excluded) continue;

      // 2. exact patterns（連結文字列に部分一致で確定）
      bool exactHit = false;
      for (final p in rule.exactPatterns) {
        final pNorm = p
            .replaceAll(' ', '')
            .replaceAll('\u3000', '')
            .replaceAll('-', '')
            .replaceAll('\u30FC', '')
            .replaceAll('\uFF0D', '')
            .toLowerCase();
        if (pNorm.isEmpty) continue;
        // 連結文字列はハイフンを保持しているため、ハイフンを除去した形でも比較する
        final joinedNoHyphen = joinedNormalized
            .replaceAll('-', '')
            .replaceAll('\u30FC', '')
            .replaceAll('\uFF0D', '');
        if (joinedNormalized.contains(pNorm) ||
            joinedNoHyphen.contains(pNorm)) {
          exactHit = true;
          break;
        }
      }
      if (exactHit) {
        return _ChainMatchResult(rule.canonicalName, 'exact');
      }

      // 3. required fragment groups（全グループから 1 件以上、セグメント単位）
      if (rule.requiredFragmentGroups.isEmpty) continue;
      final groupA = rule.requiredFragmentGroups.first
          .map((f) => f.replaceAll(' ', '').toLowerCase())
          .where((f) => f.length >= 2)
          .toList();
      bool groupAHit = false;
      // group A セグメントの由来 texts index 集合（segmented_fragments 判定用）
      final groupASrcIdx = <int>{};
      final nonASegments = <(String, int)>[];
      for (final (seg, srcIdx) in segments) {
        bool segHasA = false;
        for (final f in groupA) {
          if (seg.contains(f)) {
            segHasA = true;
            groupAHit = true;
            groupASrcIdx.add(srcIdx);
            break;
          }
        }
        if (!segHasA) {
          nonASegments.add((seg, srcIdx));
        }
      }
      if (!groupAHit) continue;
      // Step24: 同一source idx の nonA セグメント連結文字列（group A 由来との
      // 隣接マージ補助）を作る。`雪 セフン - イ ル ブ ン` の様に1トークンが
      // 1文字ずつに細切れになっても `ブン` 連続を再構成できるようにする。
      final concatNonABySrc = <int, String>{};
      for (final (seg, srcIdx) in nonASegments) {
        concatNonABySrc[srcIdx] = (concatNonABySrc[srcIdx] ?? '') + seg;
      }
      bool restGroupsSatisfied = true;
      // 後続グループ（B, C ...）の由来 idx 集合
      final restSrcIdx = <int>{};
      for (int gi = 1; gi < rule.requiredFragmentGroups.length; gi++) {
        bool gHit = false;
        for (final frag in rule.requiredFragmentGroups[gi]) {
          if (frag.length < 2) continue;
          final fNorm = frag.replaceAll(' ', '').toLowerCase();
          if (fNorm.isEmpty) continue;
          for (final (seg, srcIdx) in nonASegments) {
            if (seg.contains(fNorm)) {
              gHit = true;
              restSrcIdx.add(srcIdx);
              break;
            }
          }
          if (gHit) break;
          // Step24: セグメント単独で取れない場合、同一source 内 nonA 連結に対して
          // 部分一致を試す（group A セグメントを除いて連結する）。
          for (final entry in concatNonABySrc.entries) {
            if (entry.value.contains(fNorm)) {
              gHit = true;
              restSrcIdx.add(entry.key);
              break;
            }
          }
          if (gHit) break;
        }
        if (!gHit) {
          restGroupsSatisfied = false;
          break;
        }
      }
      if (restGroupsSatisfied) {
        // 同一 texts 要素由来のセグメントだけで成立した場合は segmented_fragments
        // それ以外（異なる OCR トークンにまたがる）は従来通り fragments
        final overlap = groupASrcIdx.intersection(restSrcIdx);
        final source =
            overlap.isNotEmpty ? 'segmented_fragments' : 'fragments';
        return _ChainMatchResult(rule.canonicalName, source);
      }
    }
    return null;
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
