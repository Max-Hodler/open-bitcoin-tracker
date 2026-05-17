import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// One block in the mempool widget — either projected (would fill from the
/// current mempool) or already mined. The fields are a superset; which ones
/// are populated depends on the source endpoint.
@immutable
class MempoolBlock {
  const MempoolBlock({
    required this.medianFeeSatVb,
    required this.txCount,
    this.height,
    this.etaMinutes,
    this.hash,
    this.timestamp,
    this.sizeBytes,
    this.weight,
    this.totalFeesSats,
    this.feeRangeSatVb,
    this.poolName,
  });

  // Nullable for the very-recent-mined enrichment-lag case where mempool.space
  // hasn't yet attached `extras.medianFee` to a freshly indexed block.
  final double? medianFeeSatVb;
  final int txCount;
  // Mined blocks only.
  final int? height;
  // Projected blocks only — derived from index in the projection array.
  final int? etaMinutes;
  // Mined only — block hash for the `/block/{hash}` deep link.
  final String? hash;
  // Mined only — UTC time the block was mined.
  final DateTime? timestamp;
  // Block size in bytes. Both endpoints expose it (`size` for mined,
  // `blockSize` for projected).
  final int? sizeBytes;
  // Mined only — block weight (WU). Projected blocks expose virtual size
  // (`blockVSize`) instead, which we don't currently surface.
  final int? weight;
  // Both endpoints expose it (`extras.totalFees` mined, `totalFees` projected).
  final int? totalFeesSats;
  // Min/max sat/vB seen in the block. Mined blocks fold this through
  // `extras.feeRange`; projected blocks expose it as `feeRange`. The array
  // mempool.space returns has 7 percentile entries; we only keep first/last.
  final ({double min, double max})? feeRangeSatVb;
  // Mined only — name of the pool that mined the block (`extras.pool.name`).
  final String? poolName;
}

/// One fetch's worth of mempool data: up to 8 projected blocks (mempool.space
/// returns "however many full blocks the current mempool would fill," so this
/// list can be shorter during low-load periods) and up to 4 mined blocks.
///
/// Either list can be empty if the corresponding endpoint failed while the
/// other succeeded — partial success is preferred over a blank card.
@immutable
class MempoolSnapshot {
  const MempoolSnapshot({
    required this.projected,
    required this.mined,
    required this.fetchedAt,
  });

  final List<MempoolBlock> projected;
  final List<MempoolBlock> mined;
  final DateTime fetchedAt;

  bool get isEmpty => projected.isEmpty && mined.isEmpty;
}

/// Talks to mempool.space's public REST API. No authentication required.
///
/// Two endpoints:
/// - `/v1/blocks` — last 10–15 mined blocks; we keep the most recent 4. Each
///   carries `extras.medianFee` (sat/vB) and `extras.totalOutputAmt` (sats),
///   either of which may be null on a very recently indexed block while the
///   enrichment pipeline catches up.
/// - `/v1/fees/mempool-blocks` — variable-length array of projected blocks
///   the current mempool would fill, in fee-priority order. Each entry has
///   `medianFee` (sat/vB), `nTx`, plus other fields we don't currently use.
///
/// Both fetches run in parallel via [Future.wait]. If one fails and the other
/// succeeds, the card still renders the half it has rather than going blank.
class MempoolClient {
  MempoolClient({http.Client? httpClient, ApiConfig? config})
      : _http = httpClient ?? http.Client(),
        _config = config ?? const ApiConfig();

  static const String _baseUrl = 'https://mempool.space/api';
  static const int _maxMined = 4;
  static const int _maxProjected = 8;

  final http.Client _http;
  final ApiConfig _config;

  /// Fetches both endpoints in parallel. Returns null only if both fail; a
  /// partial result (one endpoint failed) returns a snapshot with the failed
  /// side empty.
  Future<MempoolSnapshot?> fetch() async {
    final results = await Future.wait([
      _fetchMined(),
      _fetchProjected(),
    ]);
    final mined = results[0];
    final projected = results[1];
    if (mined == null && projected == null) return null;
    return MempoolSnapshot(
      mined: mined ?? const [],
      projected: projected ?? const [],
      fetchedAt: DateTime.now(),
    );
  }

  Future<List<MempoolBlock>?> _fetchMined() async {
    final first = await _fetchMinedOnce();
    if (first != null) return first;
    await Future<void>.delayed(const Duration(seconds: 1));
    return _fetchMinedOnce();
  }

  Future<List<MempoolBlock>?> _fetchMinedOnce() async {
    final uri = Uri.parse('$_baseUrl/v1/blocks');
    try {
      final res = await _http.get(uri).timeout(_config.requestTimeout);
      if (res.statusCode != 200) {
        if (kDebugMode) debugPrint('mempool /v1/blocks ${res.statusCode}');
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List) return null;
      final out = <MempoolBlock>[];
      for (final raw in decoded) {
        if (out.length >= _maxMined) break;
        if (raw is! Map) continue;
        final extras = raw['extras'];
        final ts = (raw['timestamp'] as num?)?.toInt();
        out.add(MempoolBlock(
          medianFeeSatVb: extras is Map
              ? _asDouble(extras['medianFee'])
              : null,
          txCount: (raw['tx_count'] as num?)?.toInt() ?? 0,
          height: (raw['height'] as num?)?.toInt(),
          hash: raw['id'] as String?,
          timestamp: ts != null
              ? DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
              : null,
          sizeBytes: (raw['size'] as num?)?.toInt(),
          weight: (raw['weight'] as num?)?.toInt(),
          totalFeesSats: extras is Map
              ? (extras['totalFees'] as num?)?.toInt()
              : null,
          feeRangeSatVb:
              extras is Map ? _parseFeeRange(extras['feeRange']) : null,
          poolName: extras is Map && extras['pool'] is Map
              ? (extras['pool']['name'] as String?)
              : null,
        ));
      }
      return out;
    } on Object catch (e) {
      if (kDebugMode) debugPrint('mempool /v1/blocks failed: $e');
      return null;
    }
  }

  Future<List<MempoolBlock>?> _fetchProjected() async {
    final uri = Uri.parse('$_baseUrl/v1/fees/mempool-blocks');
    try {
      final res = await _http.get(uri).timeout(_config.requestTimeout);
      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('mempool /v1/fees/mempool-blocks ${res.statusCode}');
        }
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List) return null;
      final out = <MempoolBlock>[];
      for (var i = 0; i < decoded.length && i < _maxProjected; i++) {
        final raw = decoded[i];
        if (raw is! Map) continue;
        out.add(MempoolBlock(
          medianFeeSatVb: _asDouble(raw['medianFee']),
          txCount: (raw['nTx'] as num?)?.toInt() ?? 0,
          // mempool.space's site uses (index + 1) * 10 for its tooltips; we
          // match that mental model rather than computing a more precise ETA
          // off difficulty-adjustment data we'd have to fetch separately.
          etaMinutes: (i + 1) * 10,
          sizeBytes: (raw['blockSize'] as num?)?.toInt(),
          totalFeesSats: (raw['totalFees'] as num?)?.toInt(),
          feeRangeSatVb: _parseFeeRange(raw['feeRange']),
        ));
      }
      return out;
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('mempool /v1/fees/mempool-blocks failed: $e');
      }
      return null;
    }
  }

  void close() => _http.close();
}

double? _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

({double min, double max})? _parseFeeRange(Object? v) {
  if (v is! List || v.isEmpty) return null;
  final lo = _asDouble(v.first);
  final hi = _asDouble(v.last);
  if (lo == null || hi == null) return null;
  return (min: lo, max: hi);
}
