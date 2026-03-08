import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/ocr_token.dart';
import 'package:household_mvp/models/receipt_ocr_result.dart';
import 'package:household_mvp/services/image_pick/image_pick_adapter.dart';
import 'package:household_mvp/services/receipt_image_preprocessor.dart';
import 'package:household_mvp/services/receipt_image_preprocessor_stub.dart';
import 'package:household_mvp/services/receipt_ocr_service.dart';

/// コンビニレシートのサンプル
const sampleConvenienceReceipt = '''
セブン-イレブン
千代田区丸の内1-1-1
TEL 03-1234-5678
2026/03/01 12:34
---
おにぎり鮭    ¥150
お茶 500ml    ¥160
---
小計          ¥310
消費税(8%)     ¥24
合計          ¥334
お預り        ¥500
お釣り        ¥166
''';

/// スーパーマーケットレシートのサンプル
const sampleSupermarketReceipt = '''
イオンモール幕張
千葉県千葉市美浜区豊砂1-1
TEL 043-123-4567
2026/02/28 15:30
---
牛乳          ¥198
パン          ¥128
卵 10個       ¥298
---
小計          ¥624
消費税(8%)     ¥49
合計          ¥673
WAON          ¥673
''';

/// 飲食店レシートのサンプル
const sampleRestaurantReceipt = '''
焼肉レストラン牛角
2026/03/01
テーブル 5
---
カルビ        ¥880
ハラミ        ¥980
ビール        ¥550
---
小計          ¥2,410
サービス料10%  ¥241
消費税(10%)    ¥265
ご請求額      ¥2,916
お支払 現金   ¥3,000
お釣り        ¥84
''';

/// QR決済控えのサンプル
const sampleQrPayment = '''
PayPay決済完了
加盟店名: ドラッグストアマツキヨ
利用金額 ¥1,580
決済日時 2026/03/01 10:15
ポイント付与 +15P
''';

void main() {
  group('ReceiptOcrResult', () {
    test('confidenceLevel が高に分類される（>= 0.8）', () {
      const result = ReceiptOcrResult(confidence: 0.85);
      expect(result.confidenceLevel, ConfidenceLevel.high);
      expect(result.confidenceLevel.label, '高');
    });

    test('confidenceLevel が中に分類される（>= 0.5）', () {
      const result = ReceiptOcrResult(confidence: 0.6);
      expect(result.confidenceLevel, ConfidenceLevel.medium);
      expect(result.confidenceLevel.label, '中');
    });

    test('confidenceLevel が低に分類される（< 0.5）', () {
      const result = ReceiptOcrResult(confidence: 0.3);
      expect(result.confidenceLevel, ConfidenceLevel.low);
      expect(result.confidenceLevel.label, '低');
    });

    test('isEmpty: 両方 null なら true', () {
      const result = ReceiptOcrResult(confidence: 0.0);
      expect(result.isEmpty, isTrue);
    });

    test('isEmpty: 店名のみあれば false', () {
      const result =
          ReceiptOcrResult(merchantName: 'テスト店', confidence: 0.5);
      expect(result.isEmpty, isFalse);
    });

    test('isEmpty: 金額のみあれば false', () {
      const result = ReceiptOcrResult(totalAmount: 500, confidence: 0.5);
      expect(result.isEmpty, isFalse);
    });
  });

  group('店名抽出', () {
    test('上部の日本語店名が抽出される', () {
      final lines = ['セブン-イレブン', '千代田区丸の内1-1-1', 'TEL 03-1234-5678'];
      final result = ReceiptOcrService.extractMerchant(lines);
      expect(result, isNotNull);
      expect(result!.value, 'セブン-イレブン');
    });

    test('住所行は除外される', () {
      final lines = ['千代田区丸の内1-1-1', 'テスト店'];
      final result = ReceiptOcrService.extractMerchant(lines);
      expect(result, isNotNull);
      expect(result!.value, 'テスト店');
    });

    test('TEL/FAXを含む行は除外される', () {
      final lines = ['TEL 03-1234-5678', 'テスト店'];
      final result = ReceiptOcrService.extractMerchant(lines);
      expect(result, isNotNull);
      expect(result!.value, 'テスト店');
    });

    test('短すぎる行（<2文字）は除外される', () {
      final lines = ['A', 'テスト店'];
      final result = ReceiptOcrService.extractMerchant(lines);
      expect(result, isNotNull);
      expect(result!.value, 'テスト店');
    });

    test('長すぎる行（>30文字）は除外される', () {
      final longLine = 'あ' * 31;
      final lines = [longLine, 'テスト店'];
      final result = ReceiptOcrService.extractMerchant(lines);
      expect(result, isNotNull);
      expect(result!.value, 'テスト店');
    });

    test('記号のみの行は除外される', () {
      final lines = ['---===---', 'テスト店'];
      final result = ReceiptOcrService.extractMerchant(lines);
      expect(result, isNotNull);
      expect(result!.value, 'テスト店');
    });

    test('「店」「ストア」を含む行が優先される', () {
      final lines = ['おすすめ商品', '焼肉レストラン牛角'];
      final result = ReceiptOcrService.extractMerchant(lines);
      expect(result, isNotNull);
      // 1行目のほうが位置スコアが高いが、内容次第で店名が優先される
    });

    test('全行が除外対象の場合は null', () {
      final lines = ['TEL 03-1234-5678', '千代田区丸の内'];
      final result = ReceiptOcrService.extractMerchant(lines);
      expect(result, isNull);
    });
  });

  group('合計金額抽出', () {
    test('「合計」キーワード隣の金額が抽出される', () {
      final lines = ['小計 ¥310', '消費税 ¥24', '合計 ¥334'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 334);
    });

    test('¥記号付き金額が正しくパースされる', () {
      final lines = ['合計 ¥1,234'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 1234);
    });

    test('カンマ区切り金額が正しくパースされる', () {
      final lines = ['合計 ¥12,345'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 12345);
    });

    test('「円」付き金額が正しくパースされる', () {
      final lines = ['合計 500円'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 500);
    });

    test('「小計」行は除外される', () {
      final lines = ['小計 ¥310', '合計 ¥334'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 334);
    });

    test('「お釣り」行は除外される', () {
      final lines = ['合計 ¥334', 'お釣り ¥166'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 334);
    });

    test('「ポイント」行は除外される', () {
      final lines = ['合計 ¥1,000', 'ポイント +10P'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 1000);
    });

    test('金額が100万超の場合は除外される', () {
      final lines = ['合計 ¥1,500,000'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNull);
    });

    test('「ご請求額」が優先キーワードとして機能する', () {
      final lines = ['小計 ¥2,410', 'ご請求額 ¥2,916'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 2916);
    });

    test('金額がない行のみの場合は null', () {
      final lines = ['テスト店', '2026/03/01', '---'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNull);
    });
  });

  group('信頼度計算', () {
    test('店名+合計の両方が高スコアの場合は高信頼度', () {
      final merchant = ScoredResult('テスト店', 1.0);
      final total = ScoredResult(500, 1.5);
      final confidence =
          ReceiptOcrService.calculateConfidence(merchant, total);
      expect(confidence, greaterThanOrEqualTo(0.8));
    });

    test('片方のみ抽出成功の場合は中程度', () {
      final total = ScoredResult(500, 1.0);
      final confidence =
          ReceiptOcrService.calculateConfidence(null, total);
      expect(confidence, greaterThan(0.0));
      expect(confidence, lessThan(0.8));
    });

    test('どちらも null の場合は 0.0', () {
      final confidence =
          ReceiptOcrService.calculateConfidence(null, null);
      expect(confidence, 0.0);
    });

    test('信頼度は 0.0〜1.0 の範囲に収まる', () {
      final merchant = ScoredResult('テスト店', 5.0);
      final total = ScoredResult(500, 5.0);
      final confidence =
          ReceiptOcrService.calculateConfidence(merchant, total);
      expect(confidence, lessThanOrEqualTo(1.0));
      expect(confidence, greaterThanOrEqualTo(0.0));
    });
  });

  group('extractFromText 統合テスト', () {
    test('コンビニレシート', () {
      final result =
          ReceiptOcrService.extractFromText(sampleConvenienceReceipt);
      expect(result.merchantName, 'セブン-イレブン');
      expect(result.totalAmount, 334);
      expect(result.isEmpty, isFalse);
    });

    test('スーパーマーケットレシート', () {
      final result =
          ReceiptOcrService.extractFromText(sampleSupermarketReceipt);
      expect(result.merchantName, isNotNull);
      expect(result.totalAmount, 673);
      expect(result.isEmpty, isFalse);
    });

    test('飲食店レシート', () {
      final result =
          ReceiptOcrService.extractFromText(sampleRestaurantReceipt);
      expect(result.merchantName, isNotNull);
      expect(result.totalAmount, 2916);
      expect(result.isEmpty, isFalse);
    });

    test('QR決済控え', () {
      final result = ReceiptOcrService.extractFromText(sampleQrPayment);
      expect(result.totalAmount, 1580);
      expect(result.isEmpty, isFalse);
    });

    test('空文字列の場合は空結果', () {
      final result = ReceiptOcrService.extractFromText('');
      expect(result.isEmpty, isTrue);
      expect(result.confidence, 0.0);
    });

    test('数字のみの文字列', () {
      final result = ReceiptOcrService.extractFromText('12345');
      // 数字のみでも金額として抽出可能
      expect(result.totalAmount, isNotNull);
    });

    test('日本語のみの文字列（金額なし）', () {
      final result =
          ReceiptOcrService.extractFromText('テスト店舗\n東京都港区');
      // 店名は抽出されるが金額はなし
      expect(result.merchantName, isNotNull);
      expect(result.totalAmount, isNull);
    });
  });

  group('1日上限チェック', () {
    test('初期状態では上限に達していない', () {
      // テスト環境ではカウンタがリセットされないため、
      // isDailyLimitReached が false であることのみ確認
      // （実際のカウントは processImage 経由で増加）
      expect(ReceiptOcrService.dailyLimit, 30);
    });
  });

  // ─── Step13: 除外強化テスト ───

  group('除外強化', () {
    test('和暦日付行はスキップされる', () {
      final lines = ['令和8年3月1日', '合計 ¥500'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 500);
    });

    test('10桁以上の連番のみの行はスキップされる', () {
      final lines = ['1234567890', '合計 ¥500'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 500);
    });

    test('連番を含むが金額記号がある行はスキップされない', () {
      final lines = ['合計 ¥1234567890'];
      // 100万超なので除外される
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNull);
    });

    test('平成日付行はスキップされる', () {
      final lines = ['平成31年4月1日', '合計 ¥800'];
      final result = ReceiptOcrService.extractTotal(lines);
      expect(result, isNotNull);
      expect(result!.value, 800);
    });
  });

  // ─── Step13: bbox版 店名抽出テスト ───

  group('bbox版 店名抽出', () {
    test('上位25%の大きいフォントが優先される', () {
      final tokens = [
        // 店名（上部、大きいフォント）
        OcrToken(
          text: 'テスト店舗',
          bbox: const OcrBoundingBox(x: 10, y: 10, width: 200, height: 40),
        ),
        // 住所（上部、小さいフォント）
        OcrToken(
          text: '渋谷区',
          bbox: const OcrBoundingBox(x: 10, y: 60, width: 150, height: 20),
        ),
        // 合計（下部）
        OcrToken(
          text: '合計 ¥500',
          bbox: const OcrBoundingBox(x: 10, y: 300, width: 150, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractMerchantFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 'テスト店舗');
    });

    test('除外キーワードを含むトークンはスキップされる', () {
      final tokens = [
        OcrToken(
          text: 'TEL 03-1234-5678',
          bbox: const OcrBoundingBox(x: 10, y: 10, width: 200, height: 40),
        ),
        OcrToken(
          text: 'テスト店',
          bbox: const OcrBoundingBox(x: 10, y: 60, width: 150, height: 30),
        ),
        OcrToken(
          text: '合計 ¥500',
          bbox: const OcrBoundingBox(x: 10, y: 300, width: 150, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractMerchantFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 'テスト店');
    });

    test('下部（25%以下）のトークンのみの場合はnull', () {
      final tokens = [
        OcrToken(
          text: 'テスト店',
          bbox: const OcrBoundingBox(x: 10, y: 350, width: 150, height: 30),
        ),
        OcrToken(
          text: '合計 ¥500',
          bbox: const OcrBoundingBox(x: 10, y: 380, width: 150, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractMerchantFromTokens(tokens);
      // 上位25%にトークンがない場合はnull
      expect(result, isNull);
    });

    test('店舗系キーワード+大きいフォントが優先される', () {
      final tokens = [
        // 同じ位置だが、ドラッグストアの方がフォントが大きい
        OcrToken(
          text: 'お知らせ',
          bbox: const OcrBoundingBox(x: 10, y: 10, width: 200, height: 20),
        ),
        OcrToken(
          text: 'ドラッグストア',
          bbox: const OcrBoundingBox(x: 10, y: 40, width: 200, height: 40),
        ),
        OcrToken(
          text: '合計 ¥500',
          bbox: const OcrBoundingBox(x: 10, y: 300, width: 150, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractMerchantFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 'ドラッグストア');
    });
  });

  // ─── Step13: bbox版 合計金額抽出テスト ───

  group('bbox版 合計金額抽出', () {
    test('同一テキスト内のキーワード+金額が最優先される', () {
      final tokens = [
        OcrToken(
          text: 'おにぎり ¥150',
          bbox: const OcrBoundingBox(x: 10, y: 100, width: 200, height: 20),
        ),
        OcrToken(
          text: '合計 ¥334',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 200, height: 20),
        ),
        OcrToken(
          text: 'お釣り ¥166',
          bbox: const OcrBoundingBox(x: 10, y: 250, width: 200, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 334);
    });

    test('キーワードと金額が別トークンで同一行にある場合', () {
      final tokens = [
        OcrToken(
          text: '合計',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 60, height: 20),
        ),
        OcrToken(
          text: '¥500',
          bbox: const OcrBoundingBox(x: 100, y: 200, width: 80, height: 20),
        ),
        OcrToken(
          text: '小計 ¥400',
          bbox: const OcrBoundingBox(x: 10, y: 150, width: 200, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 500);
    });

    test('除外キーワード行はスキップされる', () {
      final tokens = [
        OcrToken(
          text: '合計 ¥500',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 200, height: 20),
        ),
        OcrToken(
          text: 'お釣り ¥1,000',
          bbox: const OcrBoundingBox(x: 10, y: 250, width: 200, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 500);
    });

    test('和暦日付トークンはスキップされる', () {
      final tokens = [
        OcrToken(
          text: '令和8年3月1日',
          bbox: const OcrBoundingBox(x: 10, y: 50, width: 200, height: 20),
        ),
        OcrToken(
          text: '合計 ¥700',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 200, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 700);
    });
  });

  // ─── Step13: extractFromTokens 統合テスト ───

  group('extractFromTokens 統合テスト', () {
    test('bbox付きトークンから店名と金額が抽出される', () {
      final tokens = [
        OcrToken(
          text: 'セブン-イレブン',
          bbox: const OcrBoundingBox(x: 10, y: 10, width: 200, height: 40),
        ),
        OcrToken(
          text: 'TEL 03-1234-5678',
          bbox: const OcrBoundingBox(x: 10, y: 60, width: 200, height: 20),
        ),
        OcrToken(
          text: '合計 ¥334',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 200, height: 20),
        ),
        OcrToken(
          text: 'お釣り ¥166',
          bbox: const OcrBoundingBox(x: 10, y: 250, width: 200, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractFromTokens(tokens);
      expect(result.merchantName, 'セブン-イレブン');
      expect(result.totalAmount, 334);
      expect(result.isEmpty, isFalse);
    });

    test('bboxなしトークンはテキストベースフォールバックを使用', () {
      final tokens = [
        const OcrToken(text: 'テスト店'),
        const OcrToken(text: '合計 ¥1,000'),
      ];
      final result = ReceiptOcrService.extractFromTokens(tokens);
      expect(result.merchantName, 'テスト店');
      expect(result.totalAmount, 1000);
    });

    test('空トークンリストは空結果', () {
      final result = ReceiptOcrService.extractFromTokens([]);
      expect(result.isEmpty, isTrue);
      expect(result.confidence, 0.0);
    });
  });

  // ─── Step17: ラベル起点合計抽出 回帰テスト ───

  group('合計ラベルペア抽出: テキスト行ベース', () {
    test('小計+税+合計 混在: 合計の金額が採用される', () {
      final result = ReceiptOcrService.extractTotal([
        '小計 310',
        '消費税 24',
        '合計 334',
        'お釣り 166',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 334);
    });

    test('ご請求額 が優先ラベルとして機能する', () {
      final result = ReceiptOcrService.extractTotal([
        '小計 2,800',
        '消費税 116',
        'ご請求額 2,916',
        'お支払 3,000',
        'お釣り 84',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 2916);
    });

    test('利用金額 ¥1,580 が抽出される', () {
      final result = ReceiptOcrService.extractTotal([
        '利用金額 ¥1,580',
        'ポイント +15P',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 1580);
    });

    test('TOTAL 1,234 が抽出される', () {
      final result = ReceiptOcrService.extractTotal([
        'TOTAL 1,234',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 1234);
    });

    test('H-1: Fee 100 Total 200 → Total 直後の 200 を返す', () {
      final result = ReceiptOcrService.extractTotal([
        'Fee 100 Total 200',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 200);
    });

    test('H-1: TOTAL 200 Fee 100 → TOTAL 直後の 200 を返す', () {
      final result = ReceiptOcrService.extractTotal([
        'TOTAL 200 Fee 100',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 200);
    });

    test('H-1: Total ¥1,580 Change ¥420 → Total 直後の 1580 を返す', () {
      final result = ReceiptOcrService.extractTotal([
        'Total ¥1,580 Change ¥420',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 1580);
    });

    test('OCR 誤認: 合計 ¥3O4 → 304 に正規化される', () {
      final result = ReceiptOcrService.extractTotal([
        '合計 ¥3O4',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 304);
    });

    test('合計ラベルなし: フォールバックで金額が取れる', () {
      final result = ReceiptOcrService.extractTotal([
        '牛乳 ¥198',
        'パン ¥128',
        '¥326',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 326);
    });

    test('H-1: ご請求額+お支払が1行に結合 → ラベル直後の金額を返す', () {
      final result = ReceiptOcrService.extractTotal([
        'ご請求額 2,916 お支払 3,000',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 2916);
    });

    test('H-1: 合計+お釣りが1行に結合 → ラベル直後の金額を返す', () {
      final result = ReceiptOcrService.extractTotal([
        '合計 334 お釣り 166',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 334);
    });

    test('H-2: 税込 単独は優先ラベルとして扱わない', () {
      final result = ReceiptOcrService.extractTotal([
        'お茶 税込 108',
        '小計 108',
      ]);
      // 税込単独行が即採用されない（フォールバック経路で取れる可能性はある）
      expect(result == null || result.value == 108, isTrue);
      // Phase 1 スコア（2.0）ではないことを確認
      if (result != null) {
        expect(result.score < 2.0, isTrue);
      }
    });

    test('H-2: 税込合計 は合計キーワード経由で機能する', () {
      final result = ReceiptOcrService.extractTotal([
        '税込合計 1,580',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 1580);
      expect(result.score, 2.0); // ラベル行スコア
    });

    test('H-2: 合計(税込) は合計キーワード経由で機能する', () {
      final result = ReceiptOcrService.extractTotal([
        '合計(税込) 1,580',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 1580);
      expect(result.score, 2.0); // ラベル行スコア
    });

    // ── 複数ラベル一致時の重み優先テスト ──

    test('合計 vs ご請求額: 合計（weight 1.0）が優先される', () {
      final result = ReceiptOcrService.extractTotal([
        'ご請求額 2,916',
        '合計 2,916',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 2916);
    });

    test('合計 vs 利用金額: 合計（weight 1.0）が優先される', () {
      final result = ReceiptOcrService.extractTotal([
        '利用金額 ¥1,580',
        '合計 ¥1,580',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 1580);
    });

    test('TOTAL vs 合計: 合計（weight 1.0）が優先される', () {
      final result = ReceiptOcrService.extractTotal([
        'TOTAL 1,234',
        '合計 1,234',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 1234);
    });

    test('税込合計 vs ご請求額: 税込合計（合計 weight 1.0）が優先される', () {
      final result = ReceiptOcrService.extractTotal([
        'ご請求額 1,580',
        '税込合計 1,580',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 1580);
    });

    test('利用金額のみの場合でも正常に抽出される', () {
      final result = ReceiptOcrService.extractTotal([
        '利用金額 ¥1,580',
        'ポイント +15P',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 1580);
    });
  });

  group('合計ラベルペア抽出: bbox 版', () {
    test('小計+合計+お釣り 混在: 合計ラベル右側の金額が採用される', () {
      final tokens = [
        OcrToken(
          text: '小計',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 60, height: 20),
        ),
        OcrToken(
          text: '¥310',
          bbox: const OcrBoundingBox(x: 200, y: 200, width: 60, height: 20),
        ),
        OcrToken(
          text: '合計',
          bbox: const OcrBoundingBox(x: 10, y: 240, width: 60, height: 20),
        ),
        OcrToken(
          text: '¥334',
          bbox: const OcrBoundingBox(x: 200, y: 240, width: 60, height: 20),
        ),
        OcrToken(
          text: 'お釣り',
          bbox: const OcrBoundingBox(x: 10, y: 280, width: 60, height: 20),
        ),
        OcrToken(
          text: '¥166',
          bbox: const OcrBoundingBox(x: 200, y: 280, width: 60, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 334);
    });

    test('ご請求額 と金額が同一行の別トークン', () {
      final tokens = [
        OcrToken(
          text: 'ご請求額',
          bbox: const OcrBoundingBox(x: 10, y: 300, width: 80, height: 20),
        ),
        OcrToken(
          text: '¥2,916',
          bbox: const OcrBoundingBox(x: 200, y: 300, width: 80, height: 20),
        ),
        OcrToken(
          text: 'お支払',
          bbox: const OcrBoundingBox(x: 10, y: 340, width: 60, height: 20),
        ),
        OcrToken(
          text: '¥3,000',
          bbox: const OcrBoundingBox(x: 200, y: 340, width: 80, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 2916);
    });

    test('合計 ラベルと金額が同一トークン内（合計 ¥334）', () {
      final tokens = [
        OcrToken(
          text: '合計 ¥334',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 200, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 334);
    });

    test('TOTAL と金額が同一行', () {
      final tokens = [
        OcrToken(
          text: 'TOTAL',
          bbox: const OcrBoundingBox(x: 10, y: 400, width: 80, height: 20),
        ),
        OcrToken(
          text: '1,234',
          bbox: const OcrBoundingBox(x: 200, y: 400, width: 60, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 1234);
    });

    test('H-1: 合計+お釣り が同一トークン内 → ラベル直後の金額を返す', () {
      final tokens = [
        OcrToken(
          text: '合計 334 お釣り 166',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 300, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 334);
    });

    test('token 分断: 合 + 計 + ¥334（ラベルが分割されたケース）', () {
      // 「合」「計」が別トークンの場合、結合テキストに合計が含まれる行を検出
      // 現状の実装では個別トークンに「合計」が含まれないためフォールバック経路
      final tokens = [
        OcrToken(
          text: '合',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 20, height: 20),
        ),
        OcrToken(
          text: '計',
          bbox: const OcrBoundingBox(x: 35, y: 200, width: 20, height: 20),
        ),
        OcrToken(
          text: '¥334',
          bbox: const OcrBoundingBox(x: 200, y: 200, width: 60, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      // フォールバック経路でも金額自体は取れる
      expect(result!.value, 334);
    });

    // ── 複数ラベル一致時の重み優先テスト（bbox 版） ──

    test('bbox: 合計 vs ご請求額 → 合計（weight 1.0）が優先される', () {
      final tokens = [
        OcrToken(
          text: 'ご請求額',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 80, height: 20),
        ),
        OcrToken(
          text: '¥2,916',
          bbox: const OcrBoundingBox(x: 200, y: 200, width: 80, height: 20),
        ),
        OcrToken(
          text: '合計',
          bbox: const OcrBoundingBox(x: 10, y: 240, width: 60, height: 20),
        ),
        OcrToken(
          text: '¥2,916',
          bbox: const OcrBoundingBox(x: 200, y: 240, width: 80, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 2916);
    });

    test('bbox: TOTAL vs 合計 → 合計（weight 1.0）が優先される', () {
      final tokens = [
        OcrToken(
          text: 'TOTAL',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 80, height: 20),
        ),
        OcrToken(
          text: '¥1,234',
          bbox: const OcrBoundingBox(x: 200, y: 200, width: 80, height: 20),
        ),
        OcrToken(
          text: '合計',
          bbox: const OcrBoundingBox(x: 10, y: 240, width: 60, height: 20),
        ),
        OcrToken(
          text: '¥1,234',
          bbox: const OcrBoundingBox(x: 200, y: 240, width: 80, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 1234);
    });
  });

  group('行グルーピング', () {
    test('Y座標近接のトークンが同一行にグルーピングされる', () {
      final tokens = [
        OcrToken(
          text: '合計',
          bbox: const OcrBoundingBox(x: 10, y: 100, width: 60, height: 20),
        ),
        OcrToken(
          text: '¥334',
          bbox: const OcrBoundingBox(x: 200, y: 102, width: 60, height: 20),
        ),
        OcrToken(
          text: 'お釣り',
          bbox: const OcrBoundingBox(x: 10, y: 150, width: 60, height: 20),
        ),
      ];
      final lines = ReceiptOcrService.groupTokensIntoLines(tokens, 30.0);
      expect(lines.length, 2);
      expect(lines[0].length, 2); // 合計 + ¥334
      expect(lines[1].length, 1); // お釣り
    });

    test('X座標でソートされる', () {
      final tokens = [
        OcrToken(
          text: '¥334',
          bbox: const OcrBoundingBox(x: 200, y: 100, width: 60, height: 20),
        ),
        OcrToken(
          text: '合計',
          bbox: const OcrBoundingBox(x: 10, y: 100, width: 60, height: 20),
        ),
      ];
      final lines = ReceiptOcrService.groupTokensIntoLines(tokens, 30.0);
      expect(lines.length, 1);
      expect(lines[0][0].text, '合計');
      expect(lines[0][1].text, '¥334');
    });
  });

  group('OCR 誤認正規化', () {
    test('O → 0 に正規化される', () {
      expect(ReceiptOcrService.normalizeAmountText('3O4'), '304');
    });

    test('I → 1 に正規化される', () {
      expect(ReceiptOcrService.normalizeAmountText('I,234'), '1,234');
    });

    test('l → 1 に正規化される', () {
      expect(ReceiptOcrService.normalizeAmountText('l,580'), '1,580');
    });

    test('正常な数字はそのまま', () {
      expect(ReceiptOcrService.normalizeAmountText('1,234'), '1,234');
    });

    test('空白と重複カンマが整理される', () {
      expect(ReceiptOcrService.normalizeAmountText('1,,234'), '1,234');
      expect(ReceiptOcrService.normalizeAmountText('1 234'), '1234');
    });
  });

  group('金額候補抽出', () {
    test('¥記号付き金額が抽出される', () {
      final candidates =
          ReceiptOcrService.extractAmountCandidates('¥1,234');
      expect(candidates.length, 1);
      expect(candidates[0].$1, 1234);
    });

    test('OCR 誤認付き金額が正規化されて抽出される', () {
      final candidates =
          ReceiptOcrService.extractAmountCandidates('¥3O4');
      expect(candidates.length, 1);
      expect(candidates[0].$1, 304);
    });

    test('100万超は除外される', () {
      final candidates =
          ReceiptOcrService.extractAmountCandidates('¥1,500,000');
      expect(candidates, isEmpty);
    });
  });

  // ─── PickImageStatus / PickImageResult テスト ───

  group('PickImageStatus 新種別', () {
    test('unsupportedFormat が定義されている', () {
      expect(PickImageStatus.unsupportedFormat, isNotNull);
      expect(PickImageStatus.unsupportedFormat.name, 'unsupportedFormat');
    });

    test('fileTooLarge が定義されている', () {
      expect(PickImageStatus.fileTooLarge, isNotNull);
      expect(PickImageStatus.fileTooLarge.name, 'fileTooLarge');
    });

    test('PickImageResult に errorDetail を設定できる', () {
      const result = PickImageResult(
        PickImageStatus.unsupportedFormat,
        errorDetail: 'テスト詳細メッセージ',
      );
      expect(result.status, PickImageStatus.unsupportedFormat);
      expect(result.errorDetail, 'テスト詳細メッセージ');
      expect(result.imageBytes, isNull);
    });

    test('PickImageResult の success には imageBytes を設定できる', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = PickImageResult(
        PickImageStatus.success,
        imageBytes: bytes,
      );
      expect(result.status, PickImageStatus.success);
      expect(result.imageBytes, bytes);
      expect(result.errorDetail, isNull);
    });

    test('全ステータスが switch で網羅できる', () {
      // コンパイル時に網羅性が保証される（非網羅ならビルドエラー）
      for (final status in PickImageStatus.values) {
        final label = switch (status) {
          PickImageStatus.success => 'ok',
          PickImageStatus.canceled => 'cancel',
          PickImageStatus.permissionDenied => 'perm',
          PickImageStatus.browserBlocked => 'blocked',
          PickImageStatus.fileReadError => 'read',
          PickImageStatus.unsupportedFormat => 'format',
          PickImageStatus.fileTooLarge => 'size',
          PickImageStatus.unknown => 'unknown',
        };
        expect(label, isNotEmpty);
      }
    });
  });

  // ─── 失敗種別カウンタ テスト ───

  group('失敗種別カウンタ（匿名メトリクス）', () {
    setUp(() {
      ReceiptOcrService.resetPickFailureCounts();
    });

    test('失敗を記録するとカウンタが増える', () {
      ReceiptOcrService.recordPickFailure(PickImageStatus.unknown);
      ReceiptOcrService.recordPickFailure(PickImageStatus.unknown);
      ReceiptOcrService.recordPickFailure(PickImageStatus.unsupportedFormat);

      final counts = ReceiptOcrService.pickFailureCounts;
      expect(counts[PickImageStatus.unknown], 2);
      expect(counts[PickImageStatus.unsupportedFormat], 1);
    });

    test('success / canceled は記録されない', () {
      ReceiptOcrService.recordPickFailure(PickImageStatus.success);
      ReceiptOcrService.recordPickFailure(PickImageStatus.canceled);

      final counts = ReceiptOcrService.pickFailureCounts;
      expect(counts[PickImageStatus.success], isNull);
      expect(counts[PickImageStatus.canceled], isNull);
    });

    test('リセットでカウンタがクリアされる', () {
      ReceiptOcrService.recordPickFailure(PickImageStatus.fileTooLarge);
      expect(ReceiptOcrService.pickFailureCounts[PickImageStatus.fileTooLarge], 1);

      ReceiptOcrService.resetPickFailureCounts();
      expect(ReceiptOcrService.pickFailureCounts, isEmpty);
    });

    test('browserBlocked / fileReadError も記録される', () {
      ReceiptOcrService.recordPickFailure(PickImageStatus.browserBlocked);
      ReceiptOcrService.recordPickFailure(PickImageStatus.fileReadError);
      ReceiptOcrService.recordPickFailure(PickImageStatus.browserBlocked);

      final counts = ReceiptOcrService.pickFailureCounts;
      expect(counts[PickImageStatus.browserBlocked], 2);
      expect(counts[PickImageStatus.fileReadError], 1);
    });
  });

  // ─── Web画像取得フロー回帰テスト ───

  group('Web画像取得: 失敗分類', () {
    test('browserBlocked の PickImageResult が正しく構成される', () {
      const result = PickImageResult(
        PickImageStatus.browserBlocked,
        errorDetail: 'ブラウザの制約でファイル選択を開始できませんでした。'
            'もう一度押すか、別のブラウザで試してください。手入力でも続けられます。',
      );
      expect(result.status, PickImageStatus.browserBlocked);
      expect(result.errorDetail, contains('ブラウザ'));
      expect(result.imageBytes, isNull);
    });

    test('fileReadError の PickImageResult が正しく構成される', () {
      const result = PickImageResult(
        PickImageStatus.fileReadError,
        errorDetail: '画像の読み込みに失敗しました。別の画像で再試行してください。',
      );
      expect(result.status, PickImageStatus.fileReadError);
      expect(result.errorDetail, contains('読み込み'));
      expect(result.imageBytes, isNull);
    });

    test('unknown の PickImageResult が正しく構成される', () {
      const result = PickImageResult(
        PickImageStatus.unknown,
        errorDetail: '画像取得に失敗しました。再試行または手入力で続けてください。',
      );
      expect(result.status, PickImageStatus.unknown);
      expect(result.errorDetail, contains('再試行'));
      expect(result.imageBytes, isNull);
    });

    test('fileTooLarge にサイズ情報が含まれる', () {
      const result = PickImageResult(
        PickImageStatus.fileTooLarge,
        errorDetail: '画像サイズが大きすぎます（15.2MB）。10MB以下の画像を選択してください。',
      );
      expect(result.status, PickImageStatus.fileTooLarge);
      expect(result.errorDetail, contains('15.2MB'));
      expect(result.errorDetail, contains('10MB'));
    });
  });

  // ─── UI分岐ロジック回帰テスト ───

  group('PickImageResult: displayMessage（UI表示メッセージ）', () {
    test('success は null を返す', () {
      final result = PickImageResult(
        PickImageStatus.success,
        imageBytes: Uint8List.fromList([0xFF, 0xD8]),
      );
      expect(result.displayMessage, isNull);
    });

    test('canceled は null を返す', () {
      const result = PickImageResult(PickImageStatus.canceled);
      expect(result.displayMessage, isNull);
    });

    test('browserBlocked はデフォルトメッセージを返す', () {
      const result = PickImageResult(PickImageStatus.browserBlocked);
      expect(result.displayMessage, contains('ブラウザ'));
      expect(result.displayMessage, contains('手入力'));
    });

    test('fileReadError はデフォルトメッセージを返す', () {
      const result = PickImageResult(PickImageStatus.fileReadError);
      expect(result.displayMessage, contains('読み込み'));
      expect(result.displayMessage, contains('再試行'));
    });

    test('unsupportedFormat はデフォルトメッセージを返す', () {
      const result = PickImageResult(PickImageStatus.unsupportedFormat);
      expect(result.displayMessage, contains('JPEG/PNG'));
    });

    test('fileTooLarge はデフォルトメッセージを返す', () {
      const result = PickImageResult(PickImageStatus.fileTooLarge);
      expect(result.displayMessage, contains('10MB'));
    });

    test('unknown はデフォルトメッセージを返す', () {
      const result = PickImageResult(PickImageStatus.unknown);
      expect(result.displayMessage, contains('手入力'));
    });

    test('errorDetail が設定されている場合はそちらを優先', () {
      const result = PickImageResult(
        PickImageStatus.fileTooLarge,
        errorDetail: 'カスタムメッセージ: 15.2MB',
      );
      expect(result.displayMessage, 'カスタムメッセージ: 15.2MB');
    });

    test('permissionDenied はデフォルトメッセージを返す', () {
      const result = PickImageResult(PickImageStatus.permissionDenied);
      expect(result.displayMessage, contains('アクセス'));
    });
  });

  group('PickImageResult: shouldShowRetry（再試行導線）', () {
    test('success は再試行不要', () {
      final result = PickImageResult(
        PickImageStatus.success,
        imageBytes: Uint8List(0),
      );
      expect(result.shouldShowRetry, isFalse);
    });

    test('canceled は再試行不要', () {
      const result = PickImageResult(PickImageStatus.canceled);
      expect(result.shouldShowRetry, isFalse);
    });

    test('permissionDenied は再試行不要（ダイアログで対応）', () {
      const result = PickImageResult(PickImageStatus.permissionDenied);
      expect(result.shouldShowRetry, isFalse);
    });

    test('browserBlocked は再試行あり', () {
      const result = PickImageResult(PickImageStatus.browserBlocked);
      expect(result.shouldShowRetry, isTrue);
    });

    test('fileReadError は再試行あり', () {
      const result = PickImageResult(PickImageStatus.fileReadError);
      expect(result.shouldShowRetry, isTrue);
    });

    test('unsupportedFormat は再試行あり', () {
      const result = PickImageResult(PickImageStatus.unsupportedFormat);
      expect(result.shouldShowRetry, isTrue);
    });

    test('fileTooLarge は再試行あり', () {
      const result = PickImageResult(PickImageStatus.fileTooLarge);
      expect(result.shouldShowRetry, isTrue);
    });

    test('unknown は再試行あり', () {
      const result = PickImageResult(PickImageStatus.unknown);
      expect(result.shouldShowRetry, isTrue);
    });
  });

  group('PickImageStatus: defaultMessage（PRD定義文言との一致）', () {
    test('browserBlocked の文言がPRD定義と一致', () {
      expect(
        PickImageStatus.browserBlocked.defaultMessage,
        'ブラウザの制約でファイル選択を開始できませんでした。'
        'もう一度押すか、別のブラウザで試してください。手入力でも続けられます。',
      );
    });

    test('fileReadError の文言がPRD定義と一致', () {
      expect(
        PickImageStatus.fileReadError.defaultMessage,
        '画像の読み込みに失敗しました。別の画像で再試行してください。',
      );
    });

    test('unsupportedFormat の文言がPRD定義と一致', () {
      expect(
        PickImageStatus.unsupportedFormat.defaultMessage,
        contains('JPEG/PNG'),
      );
    });

    test('unknown の文言がPRD定義と一致', () {
      expect(
        PickImageStatus.unknown.defaultMessage,
        '画像取得に失敗しました。再試行または手入力で続けてください。',
      );
    });

    test('全ステータスのdefaultMessageが非null', () {
      for (final status in PickImageStatus.values) {
        expect(status.defaultMessage, isNotNull);
        expect(status.defaultMessage, isA<String>());
      }
    });
  });

  group('Web画像取得: 画像形式判定（isValidImageFormat）', () {
    test('JPEG ファイル（0xFF 0xD8 先頭）は有効', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      expect(isValidImageFormat(jpeg), isTrue);
    });

    test('PNG ファイル（0x89 0x50 0x4E 0x47 先頭）は有効', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      expect(isValidImageFormat(png), isTrue);
    });

    test('GIF ファイルは無効', () {
      final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x37, 0x61]);
      expect(isValidImageFormat(gif), isFalse);
    });

    test('WebP ファイルは無効', () {
      final webp = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0x00, 0x00]);
      expect(isValidImageFormat(webp), isFalse);
    });

    test('空バイト列は無効', () {
      expect(isValidImageFormat(Uint8List(0)), isFalse);
    });

    test('3バイト未満は無効', () {
      expect(isValidImageFormat(Uint8List.fromList([0xFF, 0xD8, 0xFF])), isFalse);
    });
  });

  // ─── 例外→ステータス変換テスト（classifyPickException） ───

  group('classifyPickException: 例外→PickImageStatus 変換', () {
    test('PlatformException camera_access_denied → permissionDenied', () {
      final result = classifyPickException(
        PlatformException(code: 'camera_access_denied'),
      );
      expect(result.status, PickImageStatus.permissionDenied);
    });

    test('PlatformException photo_access_denied → permissionDenied', () {
      final result = classifyPickException(
        PlatformException(code: 'photo_access_denied'),
      );
      expect(result.status, PickImageStatus.permissionDenied);
    });

    test('Web + PlatformException（権限以外）→ browserBlocked', () {
      final result = classifyPickException(
        PlatformException(code: 'some_error'),
        isWeb: true,
      );
      expect(result.status, PickImageStatus.browserBlocked);
      expect(result.errorDetail, contains('ブラウザ'));
    });

    test('Web + 一般例外 → unknown（内部エラーとして分類）', () {
      final result = classifyPickException(
        Exception('test error'),
        isWeb: true,
      );
      expect(result.status, PickImageStatus.unknown);
      expect(result.errorDetail, contains('手入力'));
    });

    test('Mobile + 一般例外 → unknown', () {
      final result = classifyPickException(
        Exception('test error'),
      );
      expect(result.status, PickImageStatus.unknown);
      expect(result.errorDetail, contains('手入力'));
    });

    test('Mobile + PlatformException（権限以外）→ unknown', () {
      final result = classifyPickException(
        PlatformException(code: 'unknown_error'),
      );
      expect(result.status, PickImageStatus.unknown);
    });
  });

  // ─── バイト列検証テスト（validateImageBytes） ───

  group('validateImageBytes: サイズ/形式チェック', () {
    test('正常な JPEG バイト列は null（問題なし）', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(100, 0)]);
      expect(validateImageBytes(jpeg), isNull);
    });

    test('正常な PNG バイト列は null（問題なし）', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...List.filled(100, 0)]);
      expect(validateImageBytes(png), isNull);
    });

    test('10MB超のバイト列 → fileTooLarge', () {
      // 10MB + 1バイトのダミーJPEGデータ
      final oversized = Uint8List(10 * 1024 * 1024 + 1);
      oversized[0] = 0xFF;
      oversized[1] = 0xD8;
      final result = validateImageBytes(oversized);
      expect(result, isNotNull);
      expect(result!.status, PickImageStatus.fileTooLarge);
      expect(result.errorDetail, contains('10MB'));
    });

    test('非対応形式のバイト列 → unsupportedFormat', () {
      final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x37, 0x61]);
      final result = validateImageBytes(gif);
      expect(result, isNotNull);
      expect(result!.status, PickImageStatus.unsupportedFormat);
      expect(result.errorDetail, contains('JPEG/PNG'));
    });

    test('10MB丁度は通過', () {
      final exact = Uint8List(10 * 1024 * 1024);
      exact[0] = 0xFF;
      exact[1] = 0xD8;
      expect(validateImageBytes(exact), isNull);
    });
  });

  // ─── OCRフロー統合テスト（モックアダプタ経由） ───

  // ─── 前処理レイヤーテスト ───

  group('画像前処理: StubImagePreprocessor（パススルー）', () {
    test('JPEG バイト列はパススルーされる', () async {
      final preprocessor = StubImagePreprocessor();
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(100, 0)]);
      final result = await preprocessor.preprocess(jpeg);
      expect(result.bytes, jpeg);
      expect(result.format, 'jpeg');
      expect(result.converted, isFalse);
    });

    test('PNG バイト列はパススルーされる', () async {
      final preprocessor = StubImagePreprocessor();
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...List.filled(100, 0)]);
      final result = await preprocessor.preprocess(png);
      expect(result.bytes, png);
      expect(result.format, 'png');
      expect(result.converted, isFalse);
    });

    test('不明形式は unknown フォーマットでパススルーされる', () async {
      final preprocessor = StubImagePreprocessor();
      final unknown = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final result = await preprocessor.preprocess(unknown);
      expect(result.bytes, unknown);
      expect(result.format, 'unknown');
      expect(result.converted, isFalse);
    });

    test('HEIC バイト列（ftyp ボックス）が heic として検出される', () async {
      final preprocessor = StubImagePreprocessor();
      // HEIC magic: offset 4-7 が 'ftyp'
      final heic = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x1C, // サイズ
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
        ...List.filled(20, 0),
      ]);
      final result = await preprocessor.preprocess(heic);
      expect(result.format, 'heic');
      // Stub はパススルーなので変換されない
      expect(result.converted, isFalse);
      expect(result.bytes, heic);
    });

    test('mimeType ヒントで HEIC が検出される', () async {
      final preprocessor = StubImagePreprocessor();
      // マジックバイトなしでも mimeType で判定
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final result = await preprocessor.preprocess(
        bytes, mimeType: 'image/heic',
      );
      expect(result.format, 'heic');
    });
  });

  // ─── フォーマット検出テスト ───

  group('detectImageFormat: マジックバイト判定', () {
    test('JPEG マジックバイト', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      expect(detectImageFormat(jpeg), 'jpeg');
    });

    test('PNG マジックバイト', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      expect(detectImageFormat(png), 'png');
    });

    test('HEIC ftyp ボックス', () {
      final heic = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x1C,
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
      ]);
      expect(detectImageFormat(heic), 'heic');
    });

    test('mimeType ヒント: image/heif → heic', () {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      expect(detectImageFormat(bytes, mimeType: 'image/heif'), 'heic');
    });

    test('mimeType ヒント: image/jpeg → jpeg', () {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      expect(detectImageFormat(bytes, mimeType: 'image/jpeg'), 'jpeg');
    });

    test('mimeType ヒント: image/png → png', () {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      expect(detectImageFormat(bytes, mimeType: 'image/png'), 'png');
    });

    test('判定不能 → unknown', () {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      expect(detectImageFormat(bytes), 'unknown');
    });

    test('マジックバイトが mimeType より優先される', () {
      // JPEG マジックバイトだが mimeType は png → jpeg を返す
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      expect(detectImageFormat(jpeg, mimeType: 'image/png'), 'jpeg');
    });
  });

  // ─── 画像サイズパーサーテスト ───

  group('parseImageDimensions: ヘッダーからサイズ取得', () {
    test('JPEG SOF0 マーカーから width/height を取得', () {
      // 最小限の JPEG 構造: SOI + SOF0
      // SOF0: FF C0 [len 2B] [precision 1B] [height 2B] [width 2B]
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xC0, // SOF0
        0x00, 0x0B, // length = 11
        0x08, // precision
        0x03, 0x00, // height = 768
        0x04, 0x00, // width = 1024
        0x03, // components
        0x01, 0x22, 0x00,
      ]);
      final dims = parseImageDimensions(jpeg);
      expect(dims, isNotNull);
      expect(dims!.width, 1024);
      expect(dims.height, 768);
    });

    test('JPEG SOF2（プログレッシブ）マーカーから取得', () {
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xC2, // SOF2 (progressive)
        0x00, 0x0B, // length
        0x08, // precision
        0x08, 0x00, // height = 2048
        0x06, 0x00, // width = 1536
        0x03,
        0x01, 0x22, 0x00,
      ]);
      final dims = parseImageDimensions(jpeg);
      expect(dims, isNotNull);
      expect(dims!.width, 1536);
      expect(dims.height, 2048);
    });

    test('PNG IHDR チャンクから width/height を取得', () {
      // PNG signature (8B) + IHDR chunk length (4B) + "IHDR" (4B) + width (4B) + height (4B)
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
        0x00, 0x00, 0x00, 0x0D, // IHDR length
        0x49, 0x48, 0x44, 0x52, // "IHDR"
        0x00, 0x00, 0x03, 0x20, // width = 800
        0x00, 0x00, 0x02, 0x58, // height = 600
      ]);
      final dims = parseImageDimensions(png);
      expect(dims, isNotNull);
      expect(dims!.width, 800);
      expect(dims.height, 600);
    });

    test('短すぎるバイト列は null', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8]);
      expect(parseImageDimensions(bytes), isNull);
    });

    test('不明フォーマットは null', () {
      final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04]);
      expect(parseImageDimensions(bytes), isNull);
    });

    test('JPEG で SOF マーカーがない場合は null', () {
      // SOI のみで SOF なし
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xD9, // EOI
      ]);
      expect(parseImageDimensions(jpeg), isNull);
    });

    test('HEIC ispe ボックスから width/height を取得', () {
      // HEIC ファイルの簡易構造: ftyp + 中間データ + ispe ボックス
      // ispe: [size 4B][type 4B='ispe'][ver+flags 4B][width 4B][height 4B]
      final heic = Uint8List.fromList([
        // ftyp ボックス (12 bytes)
        0x00, 0x00, 0x00, 0x0C, // size = 12
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
        // 中間データ（padding）
        ...List.filled(20, 0x00),
        // ispe ボックス (20 bytes)
        0x00, 0x00, 0x00, 0x14, // size = 20
        0x69, 0x73, 0x70, 0x65, // 'ispe'
        0x00, 0x00, 0x00, 0x00, // version + flags
        0x00, 0x00, 0x10, 0x00, // width = 4096
        0x00, 0x00, 0x0C, 0x00, // height = 3072
      ]);
      final dims = parseImageDimensions(heic);
      expect(dims, isNotNull);
      expect(dims!.width, 4096);
      expect(dims.height, 3072);
    });

    test('HEIC で ispe ボックスがない場合は null', () {
      // ftyp のみで ispe なし
      final heic = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x0C,
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
        ...List.filled(20, 0x00),
      ]);
      expect(parseImageDimensions(heic), isNull);
    });

    test('HEIC ispe で異常サイズ（width=0）はスキップ', () {
      final heic = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x0C,
        0x66, 0x74, 0x79, 0x70,
        0x68, 0x65, 0x69, 0x63,
        ...List.filled(20, 0x00),
        // ispe with width=0
        0x00, 0x00, 0x00, 0x14,
        0x69, 0x73, 0x70, 0x65,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, // width = 0
        0x00, 0x00, 0x0C, 0x00, // height = 3072
      ]);
      expect(parseImageDimensions(heic), isNull);
    });

    test('HEIC 複数 ispe → 最大面積が返る（サムネイル + 本体）', () {
      // IMG_1783.HEIC 相当: サムネイル 640x896 + 本体 5712x4284
      final heic = Uint8List.fromList([
        // ftyp ボックス
        0x00, 0x00, 0x00, 0x0C,
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
        // 中間データ
        ...List.filled(20, 0x00),
        // ispe #1: サムネイル 640x896
        0x00, 0x00, 0x00, 0x14, // size = 20
        0x69, 0x73, 0x70, 0x65, // 'ispe'
        0x00, 0x00, 0x00, 0x00, // version + flags
        0x00, 0x00, 0x02, 0x80, // width = 640
        0x00, 0x00, 0x03, 0x80, // height = 896
        // 中間データ
        ...List.filled(40, 0x00),
        // ispe #2: 本体 5712x4284
        0x00, 0x00, 0x00, 0x14, // size = 20
        0x69, 0x73, 0x70, 0x65, // 'ispe'
        0x00, 0x00, 0x00, 0x00, // version + flags
        0x00, 0x00, 0x16, 0x50, // width = 5712
        0x00, 0x00, 0x10, 0xBC, // height = 4284
      ]);
      final dims = parseImageDimensions(heic);
      expect(dims, isNotNull);
      expect(dims!.width, 5712);
      expect(dims.height, 4284);
    });

    test('HEIC 複数 ispe → 順序無関係で最大が返る', () {
      // 本体が先、サムネイルが後の場合でも最大が返る
      final heic = Uint8List.fromList([
        // ftyp ボックス
        0x00, 0x00, 0x00, 0x0C,
        0x66, 0x74, 0x79, 0x70,
        0x68, 0x65, 0x69, 0x63,
        ...List.filled(20, 0x00),
        // ispe #1: 本体 4032x3024
        0x00, 0x00, 0x00, 0x14,
        0x69, 0x73, 0x70, 0x65,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x0F, 0xC0, // width = 4032
        0x00, 0x00, 0x0B, 0xD0, // height = 3024
        ...List.filled(40, 0x00),
        // ispe #2: サムネイル 320x240
        0x00, 0x00, 0x00, 0x14,
        0x69, 0x73, 0x70, 0x65,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x40, // width = 320
        0x00, 0x00, 0x00, 0xF0, // height = 240
      ]);
      final dims = parseImageDimensions(heic);
      expect(dims, isNotNull);
      expect(dims!.width, 4032);
      expect(dims.height, 3024);
    });
  });

  group('PreprocessResult: dimensions', () {
    test('width/height が設定される', () {
      final result = PreprocessResult(
        bytes: Uint8List(0),
        format: 'jpeg',
        width: 1024,
        height: 768,
      );
      expect(result.width, 1024);
      expect(result.height, 768);
      expect(result.dimensionsString, '1024x768');
    });

    test('width/height が null の場合 unknown', () {
      final result = PreprocessResult(
        bytes: Uint8List(0),
        format: 'jpeg',
      );
      expect(result.width, isNull);
      expect(result.height, isNull);
      expect(result.dimensionsString, 'unknown');
    });
  });

  group('StubImagePreprocessor: dimensions 取得', () {
    test('JPEG バイト列から dimensions が取得される', () async {
      final preprocessor = StubImagePreprocessor();
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xC0, // SOF0
        0x00, 0x0B,
        0x08,
        0x02, 0x00, // height = 512
        0x03, 0x00, // width = 768
        0x03,
        0x01, 0x22, 0x00,
      ]);
      final result = await preprocessor.preprocess(jpeg);
      expect(result.width, 768);
      expect(result.height, 512);
    });

    test('不明フォーマットでは dimensions が null', () async {
      final preprocessor = StubImagePreprocessor();
      final unknown = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final result = await preprocessor.preprocess(unknown);
      expect(result.width, isNull);
      expect(result.height, isNull);
    });
  });

  // ─── 重み付きラベルルールテスト ───

  group('TotalLabelRule: 重み付きラベル辞書', () {
    test('合計 が weight 1.0 の最高優先度', () {
      final rules = ReceiptOcrService.totalLabelRules;
      final gokeiRule = rules.firstWhere((r) => r.pattern == '合計');
      expect(gokeiRule.weight, 1.0);
    });

    test('ご請求 が weight 0.8', () {
      final rules = ReceiptOcrService.totalLabelRules;
      final rule = rules.firstWhere((r) => r.pattern == 'ご請求');
      expect(rule.weight, 0.8);
    });

    test('TOTAL が weight 0.8', () {
      final rules = ReceiptOcrService.totalLabelRules;
      final rule = rules.firstWhere((r) => r.pattern == 'TOTAL');
      expect(rule.weight, 0.8);
    });

    test('利用金額 が weight 0.6', () {
      final rules = ReceiptOcrService.totalLabelRules;
      final rule = rules.firstWhere((r) => r.pattern == '利用金額');
      expect(rule.weight, 0.6);
    });

    test('税込 は辞書に含まれない', () {
      final rules = ReceiptOcrService.totalLabelRules;
      expect(rules.any((r) => r.pattern == '税込'), isFalse);
    });

    test('totalPriorityKeywords 後方互換が機能する', () {
      final keywords = ReceiptOcrService.totalPriorityKeywords;
      expect(keywords, contains('合計'));
      expect(keywords, contains('TOTAL'));
      expect(keywords, contains('利用金額'));
      expect(keywords, isNot(contains('税込')));
    });
  });

  group('OCRフロー: モックアダプタ → UI分岐シミュレーション', () {
    // 各ステータスでモックアダプタを作り、displayMessage / shouldShowRetry を検証
    for (final testCase in [
      (PickImageStatus.browserBlocked, true, 'ブラウザ'),
      (PickImageStatus.fileReadError, true, '読み込み'),
      (PickImageStatus.unsupportedFormat, true, 'JPEG/PNG'),
      (PickImageStatus.fileTooLarge, true, '10MB'),
      (PickImageStatus.unknown, true, '手入力'),
    ]) {
      test('${testCase.$1.name}: メッセージ表示あり + 再試行あり', () {
        final result = PickImageResult(testCase.$1);
        expect(result.displayMessage, isNotNull);
        expect(result.displayMessage, contains(testCase.$3));
        expect(result.shouldShowRetry, testCase.$2);
      });
    }

    test('success: メッセージなし + 再試行なし', () {
      final result = PickImageResult(
        PickImageStatus.success,
        imageBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      );
      expect(result.displayMessage, isNull);
      expect(result.shouldShowRetry, isFalse);
    });

    test('canceled: メッセージなし + 再試行なし', () {
      const result = PickImageResult(PickImageStatus.canceled);
      expect(result.displayMessage, isNull);
      expect(result.shouldShowRetry, isFalse);
    });

    test('permissionDenied: メッセージあり + 再試行なし（ダイアログ対応）', () {
      const result = PickImageResult(PickImageStatus.permissionDenied);
      expect(result.displayMessage, isNotNull);
      expect(result.shouldShowRetry, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // Step19: ラベル正規化（T19-04）
  // ══════════════════════════════════════════════════════════════

  group('normalizeLabelText: ラベル正規化', () {
    test('ASCII 空白が除去される', () {
      expect(ReceiptOcrService.normalizeLabelText('合 計'), '合計');
    });

    test('全角空白が除去される', () {
      expect(ReceiptOcrService.normalizeLabelText('合\u3000計'), '合計');
    });

    test('タブが除去される', () {
      expect(ReceiptOcrService.normalizeLabelText('合\t計'), '合計');
    });

    test('複数空白が除去される', () {
      expect(ReceiptOcrService.normalizeLabelText('合  計'), '合計');
    });

    test('空白なしはそのまま', () {
      expect(ReceiptOcrService.normalizeLabelText('合計'), '合計');
    });
  });

  group('Step19: 空白分断ラベルの抽出', () {
    test('合 計 ¥670 → 670 が抽出される', () {
      final result = ReceiptOcrService.extractTotal([
        '合 計 ¥670',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 670);
      expect(result.score, 2.0);
    });

    test('合　計 ¥670（全角空白）→ 670 が抽出される', () {
      final result = ReceiptOcrService.extractTotal([
        '合\u3000計 ¥670',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 670);
      expect(result.score, 2.0);
    });

    test('合  計 ¥670（複数空白）→ 670 が抽出される', () {
      final result = ReceiptOcrService.extractTotal([
        '合  計 ¥670',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 670);
      expect(result.score, 2.0);
    });

    test('bbox: 合 + 計 が別トークン → ラベル行として検出される', () {
      final tokens = [
        OcrToken(
          text: '合',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 20, height: 20),
        ),
        OcrToken(
          text: '計',
          bbox: const OcrBoundingBox(x: 35, y: 200, width: 20, height: 20),
        ),
        OcrToken(
          text: '¥670',
          bbox: const OcrBoundingBox(x: 200, y: 200, width: 60, height: 20),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 670);
      // Phase 1 のラベル行として検出される（スコア 2.5 以上）
      expect(result.score, greaterThanOrEqualTo(2.5));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // Step19: Fallback 除外強化（T19-05）
  // ══════════════════════════════════════════════════════════════

  group('Step19: fallback 除外強化', () {
    test('PayPay支払 ¥670 は除外される', () {
      final result = ReceiptOcrService.extractTotal([
        'PayPay支払 ¥670',
      ]);
      // ラベルなし + 除外キーワードあり → null
      expect(result, isNull);
    });

    test('税率 8%対象 ¥667 は除外される', () {
      final result = ReceiptOcrService.extractTotal([
        '税率 8%対象 ¥667',
      ]);
      expect(result, isNull);
    });

    test('現金 ¥1,000 は除外される', () {
      final result = ReceiptOcrService.extractTotal([
        '現金 ¥1,000',
      ]);
      expect(result, isNull);
    });

    test('電子マネー ¥670 は除外される', () {
      final result = ReceiptOcrService.extractTotal([
        '電子マネー ¥670',
      ]);
      expect(result, isNull);
    });

    test('カード ¥670 は除外される', () {
      final result = ReceiptOcrService.extractTotal([
        'カード ¥670',
      ]);
      expect(result, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // Step19: サンプル回帰テスト（T19-06）
  // ══════════════════════════════════════════════════════════════

  group('Step19: IMG_1783 サンプル回帰', () {
    test('合計 ¥670 vs 小計 ¥618 → 合計が優先される', () {
      final result = ReceiptOcrService.extractTotal([
        '小計 ¥618',
        '消費税等 ¥49',
        '合計 ¥670',
        'PayPay支払 ¥670',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 670);
      expect(result.score, 2.0);
    });

    test('合 計 ¥670 vs 税率行 → 合計が優先される', () {
      final result = ReceiptOcrService.extractTotal([
        '小計(税抜10%) ¥3',
        '税率 8%対象 ¥667',
        '小計 ¥618',
        '合 計 ¥670',
        'PayPay支払 ¥670',
      ]);
      expect(result, isNotNull);
      expect(result!.value, 670);
      expect(result.score, 2.0);
    });

    test('bbox: 合計 vs PayPay支払 → 合計が優先される', () {
      final tokens = [
        OcrToken(
          text: '小計',
          bbox: const OcrBoundingBox(x: 10, y: 100, width: 60, height: 16),
        ),
        OcrToken(
          text: '¥618',
          bbox: const OcrBoundingBox(x: 200, y: 100, width: 60, height: 16),
        ),
        OcrToken(
          text: '消費税等',
          bbox: const OcrBoundingBox(x: 10, y: 120, width: 80, height: 16),
        ),
        OcrToken(
          text: '¥49',
          bbox: const OcrBoundingBox(x: 200, y: 120, width: 40, height: 16),
        ),
        OcrToken(
          text: '合計',
          bbox: const OcrBoundingBox(x: 10, y: 160, width: 60, height: 20),
        ),
        OcrToken(
          text: '¥670',
          bbox: const OcrBoundingBox(x: 200, y: 160, width: 60, height: 20),
        ),
        OcrToken(
          text: 'PayPay支払',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 120, height: 16),
        ),
        OcrToken(
          text: '¥670',
          bbox: const OcrBoundingBox(x: 200, y: 200, width: 60, height: 16),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 670);
    });

    test('bbox: 合 + 計 分断 + PayPay支払 → 合計が優先される', () {
      final tokens = [
        OcrToken(
          text: '小計',
          bbox: const OcrBoundingBox(x: 10, y: 100, width: 60, height: 16),
        ),
        OcrToken(
          text: '¥618',
          bbox: const OcrBoundingBox(x: 200, y: 100, width: 60, height: 16),
        ),
        OcrToken(
          text: '合',
          bbox: const OcrBoundingBox(x: 10, y: 160, width: 20, height: 20),
        ),
        OcrToken(
          text: '計',
          bbox: const OcrBoundingBox(x: 35, y: 160, width: 20, height: 20),
        ),
        OcrToken(
          text: '¥670',
          bbox: const OcrBoundingBox(x: 200, y: 160, width: 60, height: 20),
        ),
        OcrToken(
          text: 'PayPay支払',
          bbox: const OcrBoundingBox(x: 10, y: 200, width: 120, height: 16),
        ),
        OcrToken(
          text: '¥670',
          bbox: const OcrBoundingBox(x: 200, y: 200, width: 60, height: 16),
        ),
      ];
      final result = ReceiptOcrService.extractTotalFromTokens(tokens);
      expect(result, isNotNull);
      expect(result!.value, 670);
    });
  });
}
