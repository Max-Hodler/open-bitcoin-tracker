import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api/_tick_throttler.dart';
import '../api/kraken_ohlc_client.dart';
import '../api/kraken_stream_service.dart';
import '../api/price_data.dart';
import '../data/app_enums.dart';
import '../data/btc_history.dart';
import '../data/btc_history_cache.dart';
import '../data/btc_rates_cache.dart';
import '../data/fx_history.dart';

class LivePriceController extends ChangeNotifier with WidgetsBindingObserver {
  LivePriceController({
    required KrakenStreamService stream,
    required KrakenOhlcClient ohlc,
    required BtcRatesCache cache,
    required BtcHistoryCache historyCache,
    LivePriceCadence cadence = LivePriceCadence.s5,
  })  : _stream = stream,
        _ohlc = ohlc,
        _cache = cache,
        _historyCache = historyCache,
        _cadence = cadence,
        _rates = cache.load() {
    _throttler = TickThrottler(onFire: notifyListeners)
      ..interval = cadence.minInterval;
  }

  final KrakenStreamService _stream;
  final KrakenOhlcClient _ohlc;
  final BtcRatesCache _cache;
  final BtcHistoryCache _historyCache;

  static const int _trailingRefetchDays = 3;

  BtcRates _rates;
  List<HistoryPoint> _allHistory = const [];
  // Bundled daily USD->fiat rates, used to convert the USD-only history series
  // per-day for non-USD charts. Null until the asset finishes loading; callers
  // fall back to the live scalar rate while it is null.
  FxHistory? _fxHistory;
  final Map<BtcRange, List<HistoryPoint>> _intraday = {};
  final Set<BtcRange> _intradayFailed = {};
  BtcRange? _intradayLoading;
  // Tracked so resume-time invalidation can re-fetch the visible range without
  // the screen having to drive its own lifecycle observer.
  BtcRange? _activeIntradayRange;
  StreamSubscription<KrakenTick>? _streamSub;
  // Periodic auto-refresh for the 1D intraday series. Kraken's 5-min candles
  // mean a re-fetch more often than ~once a minute returns the same data; on
  // 1W/1M (1h candles) the value of polling is too low to be worth the round
  // trip, so we only arm this timer for 1D.
  Timer? _intradayAutoRefreshTimer;
  static const Duration _intradayAutoRefreshInterval = Duration(seconds: 60);
  bool _appBackgrounded = false;
  bool _disposed = false;
  LivePriceCadence _cadence;
  // Gates price-card repaints to at most one per `_cadence.minInterval`,
  // queueing one deferred fire so a tick suppressed by the gate isn't dropped.
  late final TickThrottler _throttler;
  // Updated on every accepted WS tick, so under live conditions this is
  // effectively "now". Kept around because the chart hover/badge code still
  // reads it via [lastFetchedAt].
  DateTime? _lastFetchedAt;
  DateTime? _lastHistoryFetchedAt;
  DateTime? _lastIntradayFetchedAt;
  // Skip back-to-back refreshes within this window so a quick foreground/
  // background flicker doesn't double-tap the API.
  static const Duration _resumeQuietWindow = Duration(seconds: 30);
  // Relative tolerance below which a tick is treated as a no-op (no repaint).
  // Tightened from 1bp to ~zero so the WS path passes through real ticks —
  // at ~1 tick/sec a 1bp gate would suppress most updates.
  static const double _noOpRelTolerance = 1e-6;

  BtcRates get rates => _rates;
  List<HistoryPoint> get allHistory => _allHistory;
  FxHistory? get fxHistory => _fxHistory;
  DateTime? get lastFetchedAt => _lastFetchedAt;
  LivePriceCadence get cadence => _cadence;

  /// Update the throttle policy. Off → suppresses repaints entirely (the WS
  /// keeps streaming so `_rates` stays current and currency-swipe is instant).
  /// Switching from a slower cadence to a faster one fires one repaint
  /// immediately so the UI catches up rather than waiting for the next tick.
  set cadence(LivePriceCadence value) {
    if (_cadence == value) return;
    final wasOff = _cadence == LivePriceCadence.off;
    _cadence = value;
    _throttler.interval = value.minInterval;
    _throttler.cancelPending();
    if (value != LivePriceCadence.off && wasOff) {
      // Coming back from "off": flush the cached rate so the price card
      // reflects whatever ticks landed while we were silent. Mark the
      // throttler as just-fired so the next tick waits a full interval.
      _throttler.markFired();
      notifyListeners();
    }
  }

  List<HistoryPoint>? intradayFor(BtcRange range) => _intraday[range];
  bool isIntradayLoading(BtcRange range) => _intradayLoading == range;
  bool didIntradayFail(BtcRange range) => _intradayFailed.contains(range);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _streamSub ??= _stream.ticks.listen(_applyTick);
    _stream.start();
    unawaited(refreshHistory());
    unawaited(_loadFxHistory());
  }

  // Load the bundled FX-rate history once. Independent of the BTC history
  // fetch — failure here just leaves `_fxHistory` null and the chart on the
  // live-scalar fallback.
  Future<void> _loadFxHistory() async {
    final fx = await loadBundledFxHistory();
    if (_disposed) return;
    _fxHistory = fx;
    notifyListeners();
  }

  Future<void> refreshHistory() => _fetchAllHistory();

  Future<void> _fetchAllHistory() async {
    // Prefer the persisted cache; fall back to the bundled CSV on first launch.
    var base = await _historyCache.load();
    if (_disposed) return;
    if (base.isEmpty) {
      base = await loadBundledHistory();
      if (_disposed) return;
    }
    if (base.isNotEmpty) {
      _allHistory = base;
      notifyListeners();
    }

    final lastTs = base.isNotEmpty ? base.last.timeMs : 0;
    final daysGap =
        ((DateTime.now().millisecondsSinceEpoch - lastTs) / 86400000)
            .ceil()
            .clamp(0, 2000);
    // Always re-fetch a small trailing window so vendor corrections propagate.
    // Kraken's daily candle endpoint caps at 720 points (~2y) per call; deep
    // history continues to come from the bundled CSV.
    final fetchDays = base.isEmpty
        ? 720
        : (daysGap + _trailingRefetchDays).clamp(1, 720);

    // Kraken's `since` is epoch seconds. Aligning the cursor to one day before
    // the desired window keeps overlap with the cached series so the merge has
    // matching keys.
    final sinceTs = fetchDays >= 720
        ? null
        : (DateTime.now().millisecondsSinceEpoch ~/ 1000) -
            (fetchDays + 1) * 86400;
    final recent = await _ohlc.daily(sinceTs: sinceTs);
    if (_disposed || recent == null || recent.isEmpty) return;

    final merged = _mergeByDay(base, recent);
    _allHistory = merged;
    _lastHistoryFetchedAt = DateTime.now();
    notifyListeners();
    unawaited(_historyCache.save(merged));
  }

  static List<HistoryPoint> _mergeByDay(
    List<HistoryPoint> base,
    List<HistoryPoint> recent,
  ) {
    const dayMs = 86400000;
    // Recent wins: insert recent first into the seen set, then add base for any
    // day not already covered.
    final byDay = <int, double>{};
    for (final p in recent) {
      byDay[(p.timeMs ~/ dayMs) * dayMs] = p.priceUsd;
    }
    for (final p in base) {
      final key = (p.timeMs ~/ dayMs) * dayMs;
      byDay.putIfAbsent(key, () => p.priceUsd);
    }
    final keys = byDay.keys.toList()..sort();
    return [for (final k in keys) HistoryPoint(k, byDay[k]!)];
  }

  /// Debug-only: synthesize a price tick by nudging every rate by a small
  /// signed percentage. Lets us exercise the rolling-number + delta-badge
  /// animations without waiting on the network.
  void debugSimulateTick({double maxPctDrift = 0.0015}) {
    if (!kDebugMode) return;
    final rng = Random();
    double? jitter(double? v) {
      if (v == null) return null;
      final pct = (rng.nextDouble() * 2 - 1) * maxPctDrift;
      return v * (1 + pct);
    }
    _rates = BtcRates(
      usd: jitter(_rates.usd),
      gbp: jitter(_rates.gbp),
      eur: jitter(_rates.eur),
      jpy: jitter(_rates.jpy),
      cad: jitter(_rates.cad),
      aud: jitter(_rates.aud),
      chf: jitter(_rates.chf),
    );
    _lastFetchedAt = DateTime.now();
    notifyListeners();
  }

  void _applyTick(KrakenTick tick) {
    if (_disposed) return;
    final updated = _mergeKrakenTick(_rates, tick);
    if (updated == null) return; // unrecognised pair
    if (_isNoOpUpdate(_rates, updated)) {
      _lastFetchedAt = DateTime.now();
      return;
    }
    _rates = updated;
    _lastFetchedAt = DateTime.now();
    unawaited(_cache.save(_rates));
    _maybeNotify();
  }

  // Cadence gate. "Off" suppresses notifications; the rate is still cached
  // and stream-fresh, so resuming a non-off cadence shows up-to-date data.
  // Throttled cadences delegate to [_throttler], which handles the immediate-
  // vs-deferred decision and coalesces ticks suppressed by the gate.
  void _maybeNotify() {
    if (_disposed) return;
    if (_cadence == LivePriceCadence.off) return;
    _throttler.request();
  }

  static BtcRates? _mergeKrakenTick(BtcRates current, KrakenTick tick) {
    final price = tick.last;
    return switch (tick.pairCode) {
      'BTC/USD' => current.copyWith(usd: price),
      'BTC/EUR' => current.copyWith(eur: price),
      'BTC/GBP' => current.copyWith(gbp: price),
      'BTC/JPY' => current.copyWith(jpy: price),
      'BTC/CAD' => current.copyWith(cad: price),
      'BTC/AUD' => current.copyWith(aud: price),
      'BTC/CHF' => current.copyWith(chf: price),
      _ => null,
    };
  }

  static bool _isNoOpUpdate(BtcRates a, BtcRates b) {
    bool close(double? x, double? y) {
      if (x == null || y == null) return x == y;
      if (x == y) return true;
      if (x == 0) return y == 0;
      return ((x - y).abs() / x.abs()) < _noOpRelTolerance;
    }

    return close(a.usd, b.usd) &&
        close(a.gbp, b.gbp) &&
        close(a.eur, b.eur) &&
        close(a.jpy, b.jpy) &&
        close(a.cad, b.cad) &&
        close(a.aud, b.aud) &&
        close(a.chf, b.chf);
  }

  /// The screen calls this every time the displayed range changes, passing the
  /// range when it's intraday (1D/1W/1M) or null otherwise. The controller
  /// uses it to decide what to re-fetch after a resume-time invalidation, and
  /// whether to arm the 1D auto-refresh timer.
  void setActiveIntradayRange(BtcRange? range) {
    if (_activeIntradayRange == range) return;
    _activeIntradayRange = range;
    _syncIntradayAutoRefresh();
  }

  void _syncIntradayAutoRefresh() {
    final shouldRun = !_disposed &&
        !_appBackgrounded &&
        _activeIntradayRange == BtcRange.d1;
    if (!shouldRun) {
      _intradayAutoRefreshTimer?.cancel();
      _intradayAutoRefreshTimer = null;
      return;
    }
    if (_intradayAutoRefreshTimer != null) return;
    _intradayAutoRefreshTimer = Timer.periodic(
      _intradayAutoRefreshInterval,
      (_) {
        if (_disposed) return;
        if (_activeIntradayRange != BtcRange.d1) return;
        unawaited(fetchIntraday(BtcRange.d1, force: true));
      },
    );
  }

  Future<void> fetchIntraday(BtcRange range, {bool force = false}) async {
    if (_intradayLoading == range) return;
    if (!force &&
        _intraday.containsKey(range) &&
        !_intradayFailed.contains(range)) {
      return;
    }

    // 1W can be sliced from a cached 1M (last 168 hourly points) without a
    // network call.
    if (!force && range == BtcRange.w1) {
      final m1 = _intraday[BtcRange.m1];
      if (m1 != null && !_intradayFailed.contains(BtcRange.m1)) {
        final start = m1.length > 168 ? m1.length - 168 : 0;
        _intraday[range] = m1.sublist(start);
        _intradayFailed.remove(range);
        notifyListeners();
        return;
      }
    }

    _intradayLoading = range;
    notifyListeners();

    final points = await _ohlc.intraday(range);
    if (_disposed) return;
    if (points == null) {
      _intradayFailed.add(range);
      _intradayLoading = null;
      notifyListeners();
      return;
    }
    _intraday[range] = points;
    _lastIntradayFetchedAt = DateTime.now();
    _intradayFailed.remove(range);
    _intradayLoading = null;
    // A fresh 1M invalidates any previously sliced 1W so the next request
    // re-slices from the updated 1M.
    if (range == BtcRange.m1) _intraday.remove(BtcRange.w1);
    notifyListeners();
  }

  /// Bounce the WS so the live-price feed reconnects without waiting out the
  /// current backoff. Paired with `fetchIntraday(force: true)` from the chart's
  /// retry button, since both Kraken transports tend to fail together.
  void restartStream() => _stream.restart();

  void _invalidateIntraday() {
    if (_intraday.isEmpty && _intradayFailed.isEmpty) return;
    _intraday.clear();
    _intradayFailed.clear();
    notifyListeners();
    final active = _activeIntradayRange;
    if (active != null) unawaited(fetchIntraday(active));
  }

  bool _isStale(DateTime? at) =>
      at == null || DateTime.now().difference(at) >= _resumeQuietWindow;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _appBackgrounded = true;
        _stream.stop();
        _syncIntradayAutoRefresh();
      case AppLifecycleState.resumed:
        _appBackgrounded = false;
        _stream.start();
        // Only re-fetch the data the active view actually shows. Intraday
        // ranges (1D/1W/1M) read from `_intraday`; long ranges (3M+) read
        // from `_allHistory`. Re-fetching the side the user isn't looking
        // at is wasted bytes — they'll be stale-gated again on their next
        // visit anyway.
        final onIntraday = _activeIntradayRange != null;
        if (onIntraday) {
          if (_isStale(_lastIntradayFetchedAt)) _invalidateIntraday();
        } else {
          if (_isStale(_lastHistoryFetchedAt)) unawaited(refreshHistory());
        }
        _syncIntradayAutoRefresh();
      case AppLifecycleState.detached:
        _appBackgrounded = true;
        _stream.stop();
        _syncIntradayAutoRefresh();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _throttler.dispose();
    _intradayAutoRefreshTimer?.cancel();
    _intradayAutoRefreshTimer = null;
    _streamSub?.cancel();
    _streamSub = null;
    unawaited(_stream.dispose());
    _ohlc.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
