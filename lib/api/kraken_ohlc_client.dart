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

  /// Intraday candles for d1..d7, w1..w4, and 1M ranges. The home screen
  /// requests a single trailing window; we slice the response down to exactly
  /// the span the chart will draw — Kraken always sends the most recent 720
  /// candles regardless of the interval.
  ///
  /// All day ranges share Kraken's 15-min candle feed (96 candles = 1 day).
  /// All week ranges share the 1-hour feed (168 candles = 1 week).
  ///
  /// 15-min (not 5-min) candles for the day ranges because Kraken caps every
  /// OHLC response at the most recent 720 candles regardless of interval. At
  /// 5-min that ceiling is only 720 × 5 min = 2.5 days, so 3D–7D would all
  /// collapse onto the same ~2.5-day window. 15-min candles put 7 days
  /// (7 × 96 = 672 candles) comfortably under the cap.
  Future<List<HistoryPoint>?> intraday(BtcRange range) {
    final days = range.days;
    if (days != null) {
      return _fetch(intervalMinutes: 15, takeLast: days * 96);
    }
    final weeks = range.weeks;
    if (weeks != null) {
      return _fetch(intervalMinutes: 60, takeLast: weeks * 168);
    }
    if (range == BtcRange.m1) {
      return _fetch(intervalMinutes: 60);
    }
    throw ArgumentError.value(range, 'range', 'intraday only supports day, week, and m1 ranges');
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
      // Parsed off the main isolate: decoding a 36-50 KB body into thousands
      // of lists plus the HistoryPoint construction loop costs ~10-20 ms —
      // more than a frame — and responses tend to land while the user is
      // interacting with the chart that requested them. Mirrors the bundled
      // CSV path in loadBundledHistory.
      return await compute(_parseOhlcBody, (res.body, takeLast));
    } on Object catch (e) {
      if (kDebugMode) debugPrint('Kraken OHLC failed: $e');
      return null;
    }
  }

  void close() => _http.close();
}

List<HistoryPoint>? _parseOhlcBody((String, int?) args) {
  final (body, takeLast) = args;
  final decoded = jsonDecode(body);
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
}
