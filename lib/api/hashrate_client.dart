import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// User-facing range buckets for the hashrate widget. Most map 1:1 to a
/// mempool.space `/v1/mining/hashrate/{period}` endpoint, but `y5` and `y10`
/// are client-side slices: mempool doesn't expose 5- or 10-year endpoints,
/// so we fetch `all` and trim to the trailing N days.
enum HashrateRange {
  d3('3d', null),
  m1('1m', null),
  m6('6m', null),
  y1('1y', null),
  y5('all', 365 * 5),
  y10('all', 365 * 10),
  all('all', null);

  const HashrateRange(this.apiPath, this.windowDays);

  /// The mempool path segment to hit. Multiple ranges may share an apiPath
  /// (e.g. y5, y10 and all fetch `/all`); the windowDays trim differentiates
  /// what the chart actually displays. Sharing lets the controller satisfy
  /// every sibling with one network call — see [HashrateController._fetch].
  final String apiPath;

  /// When non-null, only the trailing N days of the API response are kept;
  /// when null, the entire response is used.
  final int? windowDays;

  String get code => name;

  static HashrateRange fromCode(String? code) {
    for (final r in HashrateRange.values) {
      if (r.code == code) return r;
    }
    return HashrateRange.d3;
  }
}

/// One sample on the hashrate timeline (timestamp + EH/s). Same units as
/// [HashrateSnapshot.currentHashrateEHs] so the chart can render straight
/// from this list without any rescaling.
@immutable
class HashratePoint {
  const HashratePoint(this.timestampMs, this.hashrateEHs);
  final int timestampMs;
  final double hashrateEHs;
}

/// Raw payload from one mempool `/hashrate/{period}` response, already in
/// display units (EH/s) and timestamped in ms. Intentionally range-agnostic
/// so a single network call can satisfy multiple [HashrateRange]s that share
/// the same apiPath (e.g. `y5`, `y10`, `all` all read `/all`).
@immutable
class HashrateApiPayload {
  const HashrateApiPayload({
    required this.currentHashrateEHs,
    required this.points,
    required this.fetchedAt,
  });

  final double currentHashrateEHs;
  // Oldest-first, full timeline returned by the endpoint (no client-side trim).
  final List<HashratePoint> points;
  final DateTime fetchedAt;
}

/// One fetch's worth of network-hashrate data, converted to display units
/// (EH/s = exahashes per second). The API returns raw H/s; the client divides
/// by 1e18 once, here, so the widget never has to think about units.
class HashrateSnapshot {
  HashrateSnapshot({
    required this.currentHashrateEHs,
    required this.deltaPercent,
    required this.points,
    required this.fetchedAt,
  });

  final double currentHashrateEHs;
  // Signed percent change vs the oldest sample in the fetched window. Null
  // when the window was empty or its oldest value was zero (avoids div-by-zero
  // and surfaces "no delta available" to the UI).
  final double? deltaPercent;
  // Full timeline (oldest-first) for the fetched window. Empty when the API
  // returned no samples; consumers should guard for length < 2 before charting.
  final List<HashratePoint> points;
  final DateTime fetchedAt;

  // Built lazily on first hover. The chart's touch callback hands us a
  // PricePoint whose `t` is the original timestampMs, and we need the source
  // HashratePoint to read the row's EH/s — O(1) lookup vs an O(N) scan that
  // ran on every touch event (5,000+ samples on the All range).
  Map<int, HashratePoint>? _byTimestamp;
  Map<int, HashratePoint> get byTimestamp =>
      _byTimestamp ??= {for (final p in points) p.timestampMs: p};
}

/// Talks to mempool.space's mining-stats endpoint. No authentication required.
///
/// `/v1/mining/hashrate/{period}` returns:
/// - `currentHashrate` — instantaneous network hashrate in raw H/s.
/// - `hashrates` — array of `{timestamp, avgHashrate}` daily rollups,
///   oldest-first (timestamps ascending). Period values are `3d`, `1m`, `3m`,
///   `6m`, `1y`, `2y`, `3y`, `all`; `3d` is the only one that updates on a
///   sub-day cadence and is what the collapsed widget tracks.
///
/// Returns null on any failure (HTTP non-200, missing fields, decode error)
/// so the controller's error path mirrors [MempoolClient]'s.
class HashrateClient {
  HashrateClient({http.Client? httpClient, ApiConfig? config})
      : _http = httpClient ?? http.Client(),
        _config = config ?? const ApiConfig();

  static const String _baseUrl =
      'https://mempool.space/api/v1/mining/hashrate';
  // 1 EH/s = 10^18 H/s. Raw values come back as ~10^21, so dividing keeps
  // the rendered number in the 600–1000 range we expect at present-day
  // network scale.
  static const double _ehsPerHs = 1e18;

  final http.Client _http;
  final ApiConfig _config;

  /// Hits the mempool endpoint for a given apiPath and returns the parsed
  /// payload (un-trimmed). Multiple [HashrateRange]s that share an apiPath
  /// can derive their snapshots from a single payload via [snapshotForRange],
  /// so the controller does only one HTTP call to satisfy `y5`/`y10`/`all`.
  Future<HashrateApiPayload?> fetchApiPath(String apiPath) async {
    final uri = Uri.parse('$_baseUrl/$apiPath');
    try {
      final res = await _http.get(uri).timeout(_config.requestTimeout);
      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('hashrate /$apiPath ${res.statusCode}');
        }
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final currentRaw = decoded['currentHashrate'];
      if (currentRaw is! num) return null;
      final currentEHs = currentRaw.toDouble() / _ehsPerHs;

      final points = <HashratePoint>[];
      final hashrates = decoded['hashrates'];
      if (hashrates is List) {
        for (final entry in hashrates) {
          if (entry is! Map) continue;
          final ts = entry['timestamp'];
          final v = entry['avgHashrate'];
          if (ts is! num || v is! num) continue;
          // mempool returns timestamps in seconds; chart wants ms.
          points.add(HashratePoint(
            ts.toInt() * 1000,
            v.toDouble() / _ehsPerHs,
          ));
        }
      }

      return HashrateApiPayload(
        currentHashrateEHs: currentEHs,
        points: points,
        fetchedAt: DateTime.now(),
      );
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('hashrate /$apiPath failed: $e');
      }
      return null;
    }
  }

  void close() => _http.close();
}

/// Trims [payload] to the window for [range] and computes the signed delta
/// vs the window's oldest sample. Pure: no I/O, safe to call repeatedly so
/// one network response can satisfy every range that shares its apiPath.
HashrateSnapshot snapshotForRange(HashrateApiPayload payload, HashrateRange range) {
  var points = payload.points;
  final windowDays = range.windowDays;
  if (windowDays != null && points.isNotEmpty) {
    final cutoffMs = payload.fetchedAt
        .subtract(Duration(days: windowDays))
        .millisecondsSinceEpoch;
    final firstInWindow = points.indexWhere((p) => p.timestampMs >= cutoffMs);
    points = firstInWindow < 0 ? const [] : points.sublist(firstInWindow);
  }
  final oldestEHs = points.isNotEmpty ? points.first.hashrateEHs : null;
  final double? deltaPct;
  if (oldestEHs == null || oldestEHs == 0) {
    deltaPct = null;
  } else {
    deltaPct = (payload.currentHashrateEHs - oldestEHs) / oldestEHs * 100;
  }
  return HashrateSnapshot(
    currentHashrateEHs: payload.currentHashrateEHs,
    deltaPercent: deltaPct,
    points: points,
    fetchedAt: payload.fetchedAt,
  );
}
