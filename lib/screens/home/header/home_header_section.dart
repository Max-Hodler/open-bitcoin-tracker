import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/api.dart';
import '../../../data/app_enums.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../settings/btc_price_settings_screen.dart';
import '../../settings/currency_picker_screen.dart';
import '../chart_slice.dart';
import 'home_header.dart';

/// Owns every live-price subscription on the home screen and derives the
/// chart/header state from it, so a price tick rebuilds only this subtree —
/// the stack rows and the rest of the scroll body never see the tick.
class HomeHeaderSection extends StatefulWidget {
  const HomeHeaderSection({
    super.key,
    required this.range,
    required this.currency,
    required this.selectedCurrencies,
    required this.showChart,
    required this.stacksLocked,
    required this.stacksAuthMode,
    required this.onRange,
    required this.onRetry,
    this.onOpenSettings,
    this.onOpenConverter,
  });

  final BtcRange range;
  final Currency currency;
  final List<Currency> selectedCurrencies;
  final bool showChart;
  final bool stacksLocked;
  final StacksAuthMode stacksAuthMode;
  final ValueChanged<BtcRange> onRange;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenConverter;

  @override
  State<HomeHeaderSection> createState() => _HomeHeaderSectionState();
}

class _HomeHeaderSectionState extends State<HomeHeaderSection> {
  final ValueNotifier<PricePoint?> _hover = ValueNotifier(null);
  int _lastHoverHapticMs = 0;

  // Cached range-window slice around the binary search in [ChartSlicer].
  final ChartSlicer _slicer = ChartSlicer();

  // Tracks the direction of the last live USD tick so the rolling-digit
  // animation in the price header knows whether to roll up (price went up) or
  // down (price went down). Updated from the controller's notifications via
  // [_onPriceTick] — never from build — and read in build.
  LivePriceController? _priceController;
  double? _prevUsd;
  int _rollDirection = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<LivePriceController>();
    if (!identical(controller, _priceController)) {
      _priceController?.removeListener(_onPriceTick);
      _priceController = controller;
      _prevUsd = controller.rates.usd;
      controller.addListener(_onPriceTick);
    }
  }

  void _onPriceTick() {
    final usd = _priceController?.rates.usd;
    if (usd == null || usd <= 0) return;
    final prev = _prevUsd;
    _prevUsd = usd;
    if (prev == null || prev == usd) return;
    final direction = usd > prev ? 1 : -1;
    if (direction != _rollDirection && mounted) {
      setState(() => _rollDirection = direction);
    }
  }

  @override
  void dispose() {
    _priceController?.removeListener(_onPriceTick);
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final range = widget.range;
    final currency = widget.currency;

    final currentPrice = context.select<LivePriceController, double>(
      (c) => c.rates.forCurrency(currency) ?? 0,
    );
    final usdRate = context.select<LivePriceController, double>(
      (c) => c.rates.usd ?? 0,
    );
    final usdToCurrency = usdRate > 0 ? currentPrice / usdRate : 1.0;

    final usesAllHistory = range.usesAllHistory;
    final allHistory = context.select<LivePriceController, List<HistoryPoint>>(
      (c) => c.allHistory,
    );
    // Subscribe to FX-history availability so the section rebuilds (and the
    // controller's convertedSeries memo invalidates) the moment the bundled
    // asset finishes loading. The value itself is read inside the controller.
    context.select<LivePriceController, bool>((c) => c.fxHistory != null);
    final lastFetchedAt = context.select<LivePriceController, DateTime?>(
      (c) => c.lastFetchedAt,
    );
    final intradaySeries = usesAllHistory
        ? null
        : context.select<LivePriceController, List<HistoryPoint>?>(
            (c) => c.intradayFor(range),
          );
    final intradayLoading = usesAllHistory
        ? false
        : context.select<LivePriceController, bool>(
            (c) => c.isIntradayLoading(range),
          );
    final intradayFailed = usesAllHistory
        ? false
        : context.select<LivePriceController, bool>(
            (c) => c.didIntradayFail(range),
          );
    // When the cached intraday candles have fallen behind "now", skip the live
    // connector so the line ends at the last real candle instead of drawing a
    // long flat segment across the empty tail. A refetch is already in flight
    // (fetchIntraday treats stale data as a cache miss), so this is transient.
    final intradayStale = usesAllHistory
        ? false
        : context.select<LivePriceController, bool>(
            (c) => c.isIntradayStale(range),
          );
    final series = usesAllHistory
        ? _slicer.slice(allHistory, range)
        : (intradaySeries ?? const <HistoryPoint>[]);

    // Convert each historical point by its own day's FX rate (or the scalar
    // `usdToCurrency` fallback if FX history hasn't loaded) and append the
    // live "now" point. Both layers are memoized on the controller, so the
    // returned lists keep their identity across rebuilds until the underlying
    // series or the live price actually changes — calling these on every
    // build is cheap, and AreaChart's identical() check keeps passing.
    final priceController = context.read<LivePriceController>();
    final chartData = priceController.convertedSeriesWithLive(
      series: series,
      currency: currency,
      usdToCurrencyFallback: usdToCurrency,
      // A zero live price suppresses the appended point.
      livePrice: intradayStale ? 0 : currentPrice,
    );

    // Long-range chart rendering uses the full all-history curve so switching
    // between 3M–All animates the visible window as a camera zoom.
    final convertedAllHistory = priceController.convertedAllHistoryWithLive(
      currency: currency,
      usdToCurrencyFallback: usdToCurrency,
      livePrice: currentPrice,
    );

    // The price chart, delta text and range-pill percentages are always
    // bitcoin orange — we no longer tint them green/red by direction.
    final chartColor = p.bitcoinOrange;
    final rangeAbsDiff = chartData.length >= 2
        ? chartData.last.price - chartData.first.price
        : null;
    final rangePct = rangeAbsDiff != null && chartData.first.price > 0
        ? rangeAbsDiff / chartData.first.price * 100
        : null;

    // The chart renders the full all-history curve when the range is long
    // (3M–All) so switching between those ranges can animate the visible
    // window as a camera zoom instead of swapping the line. For intraday
    // ranges (1D/1W/1M) the data isn't part of all-history, so we use the
    // range-specific chartData and the window just covers the series.
    final chartRenderData = usesAllHistory ? convertedAllHistory : chartData;
    int chartWindowStartMs;
    int chartWindowEndMs;
    if (chartData.length >= 2) {
      chartWindowStartMs = chartData.first.t;
      chartWindowEndMs = chartData.last.t;
    } else if (chartRenderData.length >= 2) {
      chartWindowStartMs = chartRenderData.first.t;
      chartWindowEndMs = chartRenderData.last.t;
    } else {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      chartWindowStartMs = nowMs - 86400000;
      chartWindowEndMs = nowMs;
    }

    return HomeHeader(
      failed: intradayFailed,
      showChart: widget.showChart,
      currentPrice: currentPrice,
      hover: _hover,
      lastFetchedAt: lastFetchedAt,
      range: range,
      currency: currency,
      selectedCurrencies: widget.selectedCurrencies,
      chartColor: chartColor,
      rangePct: rangePct,
      rangeAbsDiff: rangeAbsDiff,
      rollDirection: _rollDirection,
      onPriceTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const BtcPriceSettingsScreen(),
        ),
      ),
      onCurrencySwipe: (direction) async {
        final notifier = context.read<AppStateNotifier>();
        if (notifier.cycleCurrency(direction)) {
          AppHaptics.selection();
          return;
        }
        // 0/1 currencies in the ring: nothing to cycle to. Open the picker so
        // the user can add another, then adopt their selection on return.
        final picked = await Navigator.of(context).push<List<Currency>>(
          MaterialPageRoute(
            builder: (_) =>
                CurrencyPickerScreen(initial: notifier.selectedCurrencies),
          ),
        );
        if (picked != null && context.mounted) {
          notifier.setSelectedCurrencies(picked);
        }
      },
      chartData: chartRenderData,
      chartWindowStartMs: chartWindowStartMs,
      chartWindowEndMs: chartWindowEndMs,
      allHistoryEmpty: allHistory.isEmpty,
      usesAllHistory: usesAllHistory,
      loading: intradayLoading,
      onRange: (r) {
        _hover.value = null;
        widget.onRange(r);
      },
      onHover: (point) {
        if (_hover.value?.t == point?.t) return;
        _hover.value = point;
        if (point != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastHoverHapticMs >= 90) {
            _lastHoverHapticMs = now;
            AppHaptics.selection();
          }
        }
      },
      onRetry: widget.onRetry,
      stacksLocked: widget.stacksLocked,
      stacksAuthMode: widget.stacksAuthMode,
      onOpenSettings: widget.onOpenSettings,
      onOpenConverter: widget.onOpenConverter,
    );
  }
}
