import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/app_enums.dart';
import 'api_config.dart';
import 'price_data.dart';

/// Talks to Kraken's `/0/public/OHLC` REST endpoint and returns the close
/// price of each candle in BTC/USD. Up to 720 candles per response.
///
/// Response shape: a top-level `result` object whose first list-valued entry
/// is the candle array `[time, open, high, low, close, vwap, volume, count]`.
/// The key Kraken uses for that entry is whatever altname it picks
/// (historically `XXBTZUSD`); we just pick the first list-valued entry under
/// `result` so we don't have to track that.
class KrakenOhlcClient {
  KrakenOhlcClient({http.Client? httpClient, ApiConfig? config})
      : _http = httpClient ?? http.Client(),
        _config = config ?? const ApiConfig();

  final http.Client _http;
  final ApiConfig _config;

  static const String _restPair = 'XBTUSD';

  /// Intraday candles for the 1D / 1W / 1M ranges. The home screen requests a
  /// single trailing window, so we slice the response down to exactly the
  /// span the chart will draw — Kraken always sends the most recent 720
  /// candles regardless of the interval.
  Future<List<HistoryPoint>?> intraday(BtcRange range) {
    switch (range) {
      case BtcRange.d1:
        return _fetch(intervalMinutes: 5, takeLast: 288);
      case BtcRange.w1:
        return _fetch(intervalMinutes: 60, takeLast: 168);
      case BtcRange.m1:
        return _fetch(intervalMinutes: 60);
      case BtcRange.m2:
      case BtcRange.m3:
      case BtcRange.m4:
      case BtcRange.m5:
      case BtcRange.m6:
      case BtcRange.m7:
      case BtcRange.m8:
      case BtcRange.m9:
      case BtcRange.m10:
      case BtcRange.m11:
      case BtcRange.m12:
      case BtcRange.ytd:
      case BtcRange.y1:
      case BtcRange.y2:
      case BtcRange.y3:
      case BtcRange.y4:
      case BtcRange.y5:
      case BtcRange.y6:
      case BtcRange.y7:
      case BtcRange.y8:
      case BtcRange.y9:
      case BtcRange.y10:
      case BtcRange.y11:
      case BtcRange.y12:
      case BtcRange.y13:
      case BtcRange.y14:
      case BtcRange.y15:
      case BtcRange.all:
        throw ArgumentError.value(
          range,
          'range',
          'intraday only supports d1, w1, m1',
        );
    }
  }

  /// Daily candles. Kraken returns up to 720 days (~2y); deeper history is
  /// served by the bundled CSV merged into `_allHistory`.
  Future<List<HistoryPoint>?> daily({int? sinceTs}) {
    return _fetch(intervalMinutes: 1440, sinceSeconds: sinceTs);
  }

  Future<List<HistoryPoint>?> _fetch({
    required int intervalMinutes,
    int? takeLast,
    int? sinceSeconds,
  }) async {
    final params = <String, String>{
      'pair': _restPair,
      'interval': '$intervalMinutes',
      if (sinceSeconds != null) 'since': '$sinceSeconds',
    };
    final uri =
        Uri.parse('https://api.kraken.com/0/public/OHLC').replace(queryParameters: params);
    try {
      final res = await _http.get(uri).timeout(_config.requestTimeout);
      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('Kraken OHLC returned ${res.statusCode}');
        }
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final result = decoded['result'];
      if (result is! Map) return null;

      List<dynamic>? rows;
      for (final entry in result.entries) {
        final v = entry.value;
        if (v is List) {
          rows = v;
          break;
        }
      }
      if (rows == null) return null;

      final out = <HistoryPoint>[];
      for (final raw in rows) {
        if (raw is! List || raw.length < 5) continue;
        final time = raw[0];
        final close = raw[4];
        if (time is! num) continue;
        final closeVal = close is num
            ? close.toDouble()
            : (close is String ? double.tryParse(close) : null);
        if (closeVal == null || closeVal == 0) continue;
        out.add(HistoryPoint(time.toInt() * 1000, closeVal));
      }
      if (takeLast != null && out.length > takeLast) {
        return out.sublist(out.length - takeLast);
      }
      return out;
    } on Object catch (e) {
      if (kDebugMode) debugPrint('Kraken OHLC failed: $e');
      return null;
    }
  }

  void close() => _http.close();
}
