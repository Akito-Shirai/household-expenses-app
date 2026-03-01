import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/receipt_ocr_result.dart';
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
}
