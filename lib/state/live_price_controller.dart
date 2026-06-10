import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api/tick_throttler.dart';
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
  // The candle interval Kraken serves for each intraday range. Used to detect a
  // cached series whose newest candle has fallen behind "now" (a failed refresh
  // or a long background gap) so it can be re-fetched before the chart draws a
  // long connector from the last candle to the live price.
  static const Map<BtcRange, Duration> _intradayCandleInterval = {
    BtcRange.d1: Duration(minutes: 5),
    BtcRange.d2: Duration(minutes: 5),
    BtcRange.d3: Duration(minutes: 5),
    BtcRange.d4: Duration(minutes: 5),
    BtcRange.d5: Duration(minutes: 5),
    BtcRange.d6: Duration(minutes: 5),
    BtcRange.d7: Duration(minutes: 5),
    BtcRange.w1: Duration(hours: 1),
    BtcRange.w2: Duration(hours: 1),
    BtcRange.w3: Duration(hours: 1),
    BtcRange.w4: Duration(hours: 1),
    BtcRange.m1: Duration(hours: 1),
  };
  bool _appBackgrounded = false;
  bool _disposed = false;
  // Debug-only screenshot mode. When on, incoming WS ticks are swallowed
  // before they touch `_rates`, so the displayed price freezes at whatever it
  // was when the mode was enabled. A frozen price never differs frame-to-frame,
  // so CurrentPrice's delta badge never fires — exactly the still, delta-free
  // state we want for marketing screenshots. The WS keeps streaming so leaving
  // the mode snaps straight back to a live price.
  bool _screenshotMode = false;
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

  // The fixed, clean price shown in screenshot mode. A round number in every
  // currency (so "$58,000", "€58,000", etc. — no FX conversion), chosen so
  // marketing screenshots always show the same figure regardless of when or
  // where they're taken.
  static const double _screenshotPrice = 58000;
  static const BtcRates _screenshotRates = BtcRates(
    usd: _screenshotPrice,
    gbp: _screenshotPrice,
    eur: _screenshotPrice,
    jpy: _screenshotPrice,
    cad: _screenshotPrice,
    aud: _screenshotPrice,
    chf: _screenshotPrice,
  );

  // In screenshot mode, hand out the fixed display rates instead of the live
  // (frozen) ones. The real rate stays in `_rates` so leaving the mode snaps
  // back to it.
  BtcRates get rates => _screenshotMode ? _screenshotRates : _rates;
  bool get screenshotMode => _screenshotMode;
  List<HistoryPoint> get allHistory => _allHistory;
  FxHistory? get fxHistory => _fxHistory;
  DateTime? get lastFetchedAt => _lastFetchedAt;
  LivePriceCadence get cadence => _cadence;

  /// Update the throttle policy. Switching from a slower cadence to a faster
  /// one fires one repaint immediately so the UI catches up rather than
  /// waiting for the next tick.
  set cadence(LivePriceCadence value) {
    if (_cadence == value) return;
    _cadence = value;
    _throttler.interval = value.minInterval;
    _throttler.cancelPending();
  }

  /// Debug-only: freeze the displayed price. While on, WS ticks are dropped
  /// before they reach `_rates` (see [_applyTick]), so the price card holds
  /// still and its delta badge never fires. Turning it off flushes the latest
  /// streamed rate so the card catches up to live. Gated to debug builds at the
  /// call site (the Settings toggle), so release builds can never enable it.
  set screenshotMode(bool value) {
    if (_screenshotMode == value) return;
    _screenshotMode = value;
    if (!value) {
      // Leaving freeze: adopt whatever the stream cached while we were frozen
      // so the live getter (and the next repaint) reflect the current price
      // rather than the rate from when we entered the mode.
      _rates = _cache.load();
      _lastFetchedAt = DateTime.now();
    }
    // Notify on both edges: the `rates` getter flips between the fixed and live
    // values here, and the Settings toggle (context.watch) must rebuild so the
    // switch reflects the new state.
    notifyListeners();
  }

  List<HistoryPoint>? intradayFor(BtcRange range) => _intraday[range];
  bool isIntradayLoading(BtcRange range) => _intradayLoading == range;
  bool didIntradayFail(BtcRange range) => _intradayFailed.contains(range);

  /// Whether the cached series for [range] is stale — empty, or its newest
  /// candle has fallen more than ~1.5 candle intervals behind now. Stale data
  /// is what produces the long flat connector on the right of the chart, so the
  /// screen uses this both to gate appending the live "now" point and to decide
  /// whether a fetch is worth forcing.
  bool isIntradayStale(BtcRange range) {
    final interval = _intradayCandleInterval[range];
    if (interval == null) return false;
    final series = _intraday[range];
    if (series == null || series.isEmpty) return true;
    final newest = DateTime.fromMillisecondsSinceEpoch(series.last.timeMs);
    return DateTime.now().difference(newest) > interval * 1.5;
  }

  // Two independent FX-conversion memos. The home screen renders both an
  // active-range series and the full all-history curve in the same frame, so a
  // single shared cache would thrash; one slot per use site.
  final _FxConvertMemo _convertedSeriesMemo = _FxConvertMemo();
  final _FxConvertMemo _convertedAllHistoryMemo = _FxConvertMemo();

  /// Returns [series] converted into [currency], one point per input point.
  /// Each historical point is converted by its own day's FX rate when
  /// [fxHistory] is available, falling back to the scalar
  /// [usdToCurrencyFallback] (live USD→fiat ratio) while it isn't.
  ///
  /// Result is memoized by series identity, currency, FX object identity, and
  /// (in the fallback path) the scalar rate. Re-fetching from the cache hands
  /// back the same list object, so callers can use `identical(...)` to
  /// short-circuit downstream work.
  List<PricePoint> convertedSeries({
    required List<HistoryPoint> series,
    required Currency currency,
    required double usdToCurrencyFallback,
  }) =>
      _convertedSeriesMemo.compute(
        series: series,
        currency: currency,
        fxHistory: _fxHistory,
        usdToCurrencyFallback: usdToCurrencyFallback,
      );

  /// Same as [convertedSeries] but with a separate cache slot. Used for the
  /// full all-history curve that the long-range chart "camera zooms" over.
  List<PricePoint> convertedAllHistory({
    required Currency currency,
    required double usdToCurrencyFallback,
  }) =>
      _convertedAllHistoryMemo.compute(
        series: _allHistory,
        currency: currency,
        fxHistory: _fxHistory,
        usdToCurrencyFallback: usdToCurrencyFallback,
      );

  // The live "now" point is appended in a second memo layer rather than inside
  // the FX memo so the FX cache doesn't invalidate on every live tick — and so
  // the appended list itself keeps its identity until the base series or the
  // live price actually changes. AreaChart's identical() spot cache depends on
  // that stability.
  final _LiveAppendMemo _seriesWithLiveMemo = _LiveAppendMemo();
  final _LiveAppendMemo _allHistoryWithLiveMemo = _LiveAppendMemo();

  /// [convertedSeries] with the live price appended as a trailing "now" point.
  /// Returns the bare converted series when [livePrice] is not positive.
  List<PricePoint> convertedSeriesWithLive({
    required List<HistoryPoint> series,
    required Currency currency,
    required double usdToCurrencyFallback,
    required double livePrice,
  }) {
    final base = convertedSeries(
      series: series,
      currency: currency,
      usdToCurrencyFallback: usdToCurrencyFallback,
    );
    if (livePrice <= 0) return base;
    return _seriesWithLiveMemo.compute(base, livePrice);
  }

  /// [convertedAllHistory] with the live price appended as a trailing "now"
  /// point. Returns the bare converted series when [livePrice] is not positive.
  List<PricePoint> convertedAllHistoryWithLive({
    required Currency currency,
    required double usdToCurrencyFallback,
    required double livePrice,
  }) {
    final base = convertedAllHistory(
      currency: currency,
      usdToCurrencyFallback: usdToCurrencyFallback,
    );
    if (livePrice <= 0) return base;
    return _allHistoryWithLiveMemo.compute(base, livePrice);
  }

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
    if (_screenshotMode) {
      // Frozen for screenshots: keep the cache warm off the live merge (so
      // leaving the mode can snap straight to the current price) but don't
      // touch `_rates` or repaint — the visible price holds still and no delta
      // fires. `_lastFetchedAt` is left stale on purpose so a background/resume
      // cycle during a shoot doesn't decide the data is fresh and skip a
      // refetch we'd want post-shoot.
      unawaited(_cache.save(updated));
      return;
    }
    if (_isNoOpUpdate(_rates, updated)) {
      _lastFetchedAt = DateTime.now();
      return;
    }
    _rates = updated;
    _lastFetchedAt = DateTime.now();
    unawaited(_cache.save(_rates));
    _maybeNotify();
  }

  // Cadence gate. Throttled cadences delegate to [_throttler], which handles
  // the immediate-vs-deferred decision and coalesces suppressed ticks.
  void _maybeNotify() {
    if (_disposed) return;
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
        !_intradayFailed.contains(range) &&
        !isIntradayStale(range)) {
      return;
    }

    // Week ranges (1W..4W) can be sliced from a cached 1M (hourly points)
    // without a network call — but only if that 1M is itself fresh.
    final weeks = range.weeks;
    if (!force && weeks != null) {
      final m1 = _intraday[BtcRange.m1];
      if (m1 != null &&
          !_intradayFailed.contains(BtcRange.m1) &&
          !isIntradayStale(BtcRange.m1)) {
        final take = weeks * 168;
        final start = m1.length > take ? m1.length - take : 0;
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
    // A fresh 1M invalidates all previously sliced week ranges so the next
    // request re-slices from the updated 1M.
    if (range == BtcRange.m1) {
      for (final r in btcRangeWeeks) _intraday.remove(r);
    }
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

/// One-entry memo around appending the live "now" point to a converted
/// series. Keyed on (base identity, live price): as long as neither changes,
/// callers get back the same list object — including its original timestamp,
/// which is fine because a rebuild without a price change has nothing new to
/// plot at the series tail anyway.
class _LiveAppendMemo {
  List<PricePoint>? _base;
  double _livePrice = double.nan;
  List<PricePoint> _result = const [];

  List<PricePoint> compute(List<PricePoint> base, double livePrice) {
    if (identical(_base, base) && _livePrice == livePrice) return _result;
    _base = base;
    _livePrice = livePrice;
    _result = [
      ...base,
      PricePoint(DateTime.now().millisecondsSinceEpoch, livePrice),
    ];
    return _result;
  }
}

/// One-entry memo around the USD→fiat conversion of a USD-priced history
/// series. Keyed on (series identity, currency, FX-history identity); when FX
/// history is null the scalar fallback rate is also part of the key.
class _FxConvertMemo {
  List<HistoryPoint>? _series;
  Currency? _currency;
  FxHistory? _fxHistory;
  double _usdToCurrency = double.nan;
  List<PricePoint> _converted = const [];

  List<PricePoint> compute({
    required List<HistoryPoint> series,
    required Currency currency,
    required FxHistory? fxHistory,
    required double usdToCurrencyFallback,
  }) {
    final hit = identical(_series, series) &&
        _currency == currency &&
        identical(_fxHistory, fxHistory) &&
        (fxHistory != null || _usdToCurrency == usdToCurrencyFallback);
    if (hit) return _converted;

    _series = series;
    _currency = currency;
    _fxHistory = fxHistory;
    _usdToCurrency = usdToCurrencyFallback;
    _converted = [
      for (final p in series)
        PricePoint(
          p.timeMs,
          p.priceUsd *
              (fxHistory != null
                  ? fxHistory.rateAt(currency, p.timeMs)
                  : usdToCurrencyFallback),
        ),
    ];
    return _converted;
  }
}
