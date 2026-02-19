import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Frankfurter API（https://api.frankfurter.dev）からJPYレートを取得するサービス
///
/// - APIキー不要・無料運用前提
/// - 失敗時は null を返す（例外は内部でログして呑む）
/// - テスト時は [httpClient] を注入してモック化可能
class FxFetchService {
  static const _baseUrl = 'https://api.frankfurter.dev';
  static const _timeoutSeconds = 10;

  const FxFetchService._();

  /// 指定通貨に対する JPY レートを取得
  ///
  /// - 返り値: `1 [currency] = x JPY` の x
  /// - [currency] が JPY の場合は null
  /// - ネットワーク障害・APIエラー時は null（クラッシュしない）
  /// - [httpClient] を指定するとテスト用のモッククライアントを注入できる
  static Future<double?> fetchJpyRate(
    String currency, {
    http.Client? httpClient,
  }) async {
    if (currency == 'JPY') return null;
    final client = httpClient ?? http.Client();
    try {
      final uri = Uri.parse(
        '$_baseUrl/v1/latest?base=$currency&symbols=JPY',
      );
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: _timeoutSeconds));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final rates = json['rates'] as Map<String, dynamic>?;
        final jpyRate = rates?['JPY'];
        if (jpyRate is num) return jpyRate.toDouble();
        debugPrint('FxFetchService: JPYレートがレスポンスに含まれていない: ${response.body}');
      } else {
        debugPrint('FxFetchService: HTTPエラー ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('FxFetchService: レート取得エラー: $e');
    } finally {
      // 自前生成したクライアントのみ閉じる
      if (httpClient == null) client.close();
    }
    return null;
  }
}
