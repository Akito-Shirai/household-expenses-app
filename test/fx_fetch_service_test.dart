import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:household_mvp/utils/fx_fetch_service.dart';

void main() {
  group('FxFetchService.fetchJpyRate', () {
    test('JPY を指定した場合は null を返す', () async {
      final result = await FxFetchService.fetchJpyRate('JPY');
      expect(result, isNull);
    });

    test('API成功時に正しいレートを返す', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['base'], 'USD');
        expect(request.url.queryParameters['symbols'], 'JPY');
        return http.Response(
          jsonEncode({
            'base': 'USD',
            'date': '2026-02-19',
            'rates': {'JPY': 149.85},
          }),
          200,
        );
      });

      final result = await FxFetchService.fetchJpyRate(
        'USD',
        httpClient: mockClient,
      );
      expect(result, 149.85);
    });

    test('API成功だがレートがintの場合もdoubleに変換される', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'base': 'USD',
            'date': '2026-02-19',
            'rates': {'JPY': 150},
          }),
          200,
        );
      });

      final result = await FxFetchService.fetchJpyRate(
        'USD',
        httpClient: mockClient,
      );
      expect(result, 150.0);
    });

    test('HTTPエラー（500）時は null を返す', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final result = await FxFetchService.fetchJpyRate(
        'USD',
        httpClient: mockClient,
      );
      expect(result, isNull);
    });

    test('HTTPエラー（404）時は null を返す', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final result = await FxFetchService.fetchJpyRate(
        'EUR',
        httpClient: mockClient,
      );
      expect(result, isNull);
    });

    test('レスポンスにJPYレートが含まれない場合は null を返す', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'base': 'USD',
            'date': '2026-02-19',
            'rates': {'EUR': 0.92},
          }),
          200,
        );
      });

      final result = await FxFetchService.fetchJpyRate(
        'USD',
        httpClient: mockClient,
      );
      expect(result, isNull);
    });

    test('不正なJSON時は null を返す（クラッシュしない）', () async {
      final mockClient = MockClient((request) async {
        return http.Response('not json', 200);
      });

      final result = await FxFetchService.fetchJpyRate(
        'USD',
        httpClient: mockClient,
      );
      expect(result, isNull);
    });

    test('ネットワーク例外時は null を返す（クラッシュしない）', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network error');
      });

      final result = await FxFetchService.fetchJpyRate(
        'USD',
        httpClient: mockClient,
      );
      expect(result, isNull);
    });

    test('各通貨で正しいbaseパラメータが送信される', () async {
      for (final currency in ['USD', 'AUD', 'EUR', 'GBP']) {
        String? capturedBase;
        final mockClient = MockClient((request) async {
          capturedBase = request.url.queryParameters['base'];
          return http.Response(
            jsonEncode({
              'base': currency,
              'date': '2026-02-19',
              'rates': {'JPY': 100.0},
            }),
            200,
          );
        });

        await FxFetchService.fetchJpyRate(currency, httpClient: mockClient);
        expect(capturedBase, currency, reason: '$currency のbaseパラメータが正しいこと');
      }
    });
  });
}
