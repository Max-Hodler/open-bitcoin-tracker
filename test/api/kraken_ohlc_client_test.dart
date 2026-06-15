import 'dart:convert';

import 'package:open_bitcoin_tracker/api/api.dart';
import 'package:open_bitcoin_tracker/data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _payload(List<List<dynamic>> rows, {int last = 0}) => {
      'error': const [],
      'result': {
        'XXBTZUSD': rows,
        'last': last,
      },
    };

void main() {
  group('KrakenOhlcClient.daily', () {
    test('parses time/close (string-encoded) and converts seconds to ms', () async {
      final client = KrakenOhlcClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode(_payload([
                [1700000000, '39000.0', '40500.0', '38800.0', '40000.0', '0', '0', 0],
                [1700086400, '40000.0', '41200.0', '39900.0', '41000.0', '0', '0', 0],
              ])),
              200,
            )),
      );
      final points = await client.daily();
      expect(points, hasLength(2));
      expect(points![0].timeMs, 1700000000 * 1000);
      expect(points[0].priceUsd, 40000.0);
      expect(points[1].priceUsd, 41000.0);
    });

    test('skips rows with close=0', () async {
      final client = KrakenOhlcClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode(_payload([
                [1, '0', '0', '0', '0', '0', '0', 0],
                [2, '0', '0', '0', '100.0', '0', '0', 0],
              ])),
              200,
            )),
      );
      final points = await client.daily();
      expect(points, hasLength(1));
      expect(points!.first.priceUsd, 100);
    });

    test('passes interval=1440 and forwards `since`', () async {
      late Uri captured;
      final client = KrakenOhlcClient(
        httpClient: MockClient((req) async {
          captured = req.url;
          return http.Response(jsonEncode(_payload(const [])), 200);
        }),
      );
      await client.daily(sinceTs: 1700000000);
      expect(captured.path, endsWith('/0/public/OHLC'));
      expect(captured.queryParameters['pair'], 'XBTUSD');
      expect(captured.queryParameters['interval'], '1440');
      expect(captured.queryParameters['since'], '1700000000');
    });

    test('returns null on non-200', () async {
      final client = KrakenOhlcClient(
        httpClient: MockClient((_) async => http.Response('', 503)),
      );
      expect(await client.daily(), isNull);
    });

    test('returns null on network error', () async {
      final client = KrakenOhlcClient(
        httpClient: MockClient((_) async => throw Exception('boom')),
      );
      expect(await client.daily(), isNull);
    });
  });

  group('KrakenOhlcClient.intraday', () {
    test('1D uses interval=15 and trims to last 96 candles', () async {
      late Uri captured;
      // Send 720 rows; the client should trim down to 96.
      final rows = [
        for (var i = 0; i < 720; i++)
          [1700000000 + i * 900, '0', '0', '0', '${100.0 + i}', '0', '0', 0],
      ];
      final client = KrakenOhlcClient(
        httpClient: MockClient((req) async {
          captured = req.url;
          return http.Response(jsonEncode(_payload(rows)), 200);
        }),
      );
      final points = await client.intraday(BtcRange.d1);
      expect(captured.queryParameters['interval'], '15');
      expect(points, hasLength(96));
      // Trim takes the trailing 96 — so the first kept row corresponds to index 624.
      expect(points!.first.priceUsd, 100.0 + 624);
      expect(points.last.priceUsd, 100.0 + 719);
    });

    test('7D trims to last 672 candles', () async {
      // 7 × 96 = 672 candles fit under Kraken's 720-candle response cap, so
      // 7D draws a genuinely wider window than 3D (288 candles) rather than
      // collapsing onto the same ~2.5-day slice the 5-min feed used to give.
      final rows = [
        for (var i = 0; i < 720; i++)
          [1700000000 + i * 900, '0', '0', '0', '${100.0 + i}', '0', '0', 0],
      ];
      final client = KrakenOhlcClient(
        httpClient: MockClient((_) async => http.Response(jsonEncode(_payload(rows)), 200)),
      );
      final points = await client.intraday(BtcRange.d7);
      expect(points, hasLength(672));
      expect(points!.first.priceUsd, 100.0 + 48);
    });

    test('1W uses interval=60 and trims to last 168 candles', () async {
      late Uri captured;
      final rows = [
        for (var i = 0; i < 720; i++)
          [1700000000 + i * 3600, '0', '0', '0', '${200.0 + i}', '0', '0', 0],
      ];
      final client = KrakenOhlcClient(
        httpClient: MockClient((req) async {
          captured = req.url;
          return http.Response(jsonEncode(_payload(rows)), 200);
        }),
      );
      final points = await client.intraday(BtcRange.w1);
      expect(captured.queryParameters['interval'], '60');
      expect(points, hasLength(168));
      expect(points!.first.priceUsd, 200.0 + (720 - 168));
    });

    test('1M uses interval=60 and keeps the full series', () async {
      final rows = [
        for (var i = 0; i < 720; i++)
          [1700000000 + i * 3600, '0', '0', '0', '${300.0 + i}', '0', '0', 0],
      ];
      final client = KrakenOhlcClient(
        httpClient: MockClient((_) async => http.Response(jsonEncode(_payload(rows)), 200)),
      );
      final points = await client.intraday(BtcRange.m1);
      expect(points, hasLength(720));
    });

    test('long ranges throw ArgumentError without hitting the network', () async {
      var called = false;
      final client = KrakenOhlcClient(
        httpClient: MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );
      expect(() => client.intraday(BtcRange.all), throwsArgumentError);
      expect(called, isFalse);
    });
  });
}
