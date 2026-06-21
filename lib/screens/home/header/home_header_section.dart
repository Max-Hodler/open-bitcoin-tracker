import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/api.dart';
import '../../../data/app_enums.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../../l10n/generated/app_localizations.dart';

import '../../full_screen_price/full_screen_price_screen.dart';
import '../../settings/currency_picker_screen.dart';
import '../../settings/range_config_bar.dart';
import '../../settings/settings_widgets.dart';
import '../../../widgets/sheet_safe_area.dart';
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
    required this.onRange,
    required this.onRetry,
    this.onOpenConverter,
  });

  final BtcRange range;
  final Currency currency;
  final List<Currency> selectedCurrencies;
  final bool showChart;
  final ValueChanged<BtcRange> onRange;
  final VoidCallback onRetry;
  final VoidCallback? onOpenConverter;

  @override
  State<HomeHeaderSection> createState() => _HomeHeaderSectionState();
}

class _HomeHeaderSectionState extends State<HomeHeaderSection> {
  final ValueNotifier<PricePoint?> _hover = ValueNotifier(null);
  int _lastHoverHapticMs = 0;

  // Set to true the first time the user swipes the price (or the picker
  // reduces to 1 currency) this session. Combined with the persisted
  // priceSwipeHintDismissed flag to derive showSwipeHint in build — keeping
  // them separate means a "reset all options" that clears the persisted flag
  // is reflected immediately on the next build.
  bool _swipedThisSession = false;
  // Mirrors the last-seen value of priceSwipeHintDismissed so build() can
  // detect when a "reset all options" flips it false and clear _swipedThisSession.
  bool _prevPriceSwipeHintDismissed = false;

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

    final currentPrice = context.select<LivePriceController, double?>(
      (c) => c.rates.forCurrency(currency),
    );
    final usdRate = context.select<LivePriceController, double?>(
      (c) => c.rates.usd,
    );
    final usdToCurrency = (usdRate != null && usdRate > 0 && currentPrice != null)
        ? currentPrice / usdRate
        : 1.0;

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
      livePrice: (intradayStale || currentPrice == null) ? 0 : currentPrice,
    );

    // Long-range chart rendering uses the full all-history curve so switching
    // between 3M–All animates the visible window as a camera zoom.
    final convertedAllHistory = priceController.convertedAllHistoryWithLive(
      currency: currency,
      usdToCurrencyFallback: usdToCurrency,
      livePrice: currentPrice ?? 0,
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

    final priceSwipeHintDismissed = context.select<AppStateNotifier, bool>(
        (a) => a.priceSwipeHintDismissed);
    // "Reset all options" flips priceSwipeHintDismissed back to false — when
    // that happens, also clear the session latch so the hint re-appears.
    if (_prevPriceSwipeHintDismissed && !priceSwipeHintDismissed) {
      _swipedThisSession = false;
    }
    _prevPriceSwipeHintDismissed = priceSwipeHintDismissed;
    final showSwipeHint = !_swipedThisSession &&
        !priceSwipeHintDismissed &&
        widget.selectedCurrencies.length >= 2;
    final currencyEverSwiped = _swipedThisSession || priceSwipeHintDismissed;

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
      showSwipeHint: showSwipeHint,
      currencyEverSwiped: currencyEverSwiped,
      onDismissSwipeHint: () {
        if (_swipedThisSession == false) {
          setState(() => _swipedThisSession = true);
          context.read<AppStateNotifier>().dismissPriceSwipeHint();
        }
      },
      onPriceTap: () {
        AppHaptics.light();
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: theme.brightness == Brightness.dark
              ? cs.surfaceContainerHigh
              : cs.surfaceContainerLow,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (ctx) {
            final l10n = AppLocalizations.of(ctx);
            return Consumer<AppStateNotifier>(
              builder: (ctx, app, _) => SheetSafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: Text(
                        l10n.settingsPriceTitle,
                        style: AppTypography.label.copyWith(
                          fontSize: 18,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.xl,
                      ),
                      child: SettingsGroup(
                        children: [
                          SettingsPickerTile(
                            label: l10n.settingsFullScreenPrice,
                            value: '',
                            onTap: () {
                              Navigator.of(ctx).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => FullScreenPriceScreen(
                                    currency: widget.currency,
                                  ),
                                ),
                              );
                            },
                            trailingIcon: Icons.fullscreen,
                          ),
                          SettingsPickerTile(
                            label: l10n.settingsCurrencies,
                            value: app.selectedCurrencies
                                .map((c) => c.code)
                                .join(', '),
                            onTap: () async {
                              Navigator.of(ctx).pop();
                              final picked = await Navigator.of(context)
                                  .push<List<Currency>>(
                                MaterialPageRoute(
                                  builder: (_) => CurrencyPickerScreen(
                                    initial: app.selectedCurrencies,
                                  ),
                                ),
                              );
                              if (picked != null) {
                                app.setSelectedCurrencies(picked);
                                if (picked.length == 1 && _swipedThisSession == false) {
                                  setState(() => _swipedThisSession = true);
                                  app.dismissPriceSwipeHint();
                                }
                              }
                            },
                            trailingIcon: Icons.chevron_right,
                          ),
                          SettingsPickerTile(
                            label: l10n.settingsLivePriceCadence,
                            value: _livePriceCadenceLabel(
                                l10n, app.livePriceCadence),
                            onTap: () async {
                              final picked =
                                  await _showLivePriceCadencePicker(
                                      ctx, app.livePriceCadence);
                              if (picked != null) {
                                app.setLivePriceCadence(picked);
                              }
                            },
                            trailingIcon: Icons.unfold_more,
                          ),
                          SettingsToggleTile(
                            label: l10n.settingsPriceDelta,
                            value: app.showPriceDelta,
                            enabled: true,
                            onChanged: app.setShowPriceDelta,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      onGraphSettingsTap: () {
        AppHaptics.light();
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: theme.brightness == Brightness.dark
              ? cs.surfaceContainerHigh
              : cs.surfaceContainerLow,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (ctx) {
            final l10n = AppLocalizations.of(ctx);
            return Consumer<AppStateNotifier>(
              builder: (ctx, app, _) => SheetSafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: Text(
                        l10n.graphSettingsTitle,
                        style: AppTypography.label.copyWith(
                          fontSize: 18,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.xl,
                      ),
                      child: SettingsGroup(
                        children: [
                          SettingsSegmentedTile(
                            label: l10n.settingsChartHeight,
                            options: [
                              l10n.settingsChartHeightNormal,
                              l10n.settingsChartHeightTall,
                              l10n.settingsChartHeightXl,
                              l10n.settingsChartHeightXxl,
                              l10n.settingsChartHeightXxxl,
                            ],
                            selectedIndex: app.chartHeight.index,
                            enabled: true,
                            onChanged: (i) =>
                                app.setChartHeight(ChartHeight.values[i]),
                          ),
                          SettingsSegmentedTile(
                            label: l10n.settingsScale,
                            options: [
                              l10n.settingsScaleLinear,
                              l10n.settingsScaleLog,
                            ],
                            selectedIndex: app.logScale ? 1 : 0,
                            enabled: true,
                            onChanged: (i) => app.setLogScale(i == 1),
                          ),
                          SettingsRangesTile(label: l10n.settingsRanges),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      onCurrencySwipe: (direction) async {
        final notifier = context.read<AppStateNotifier>();
        if (notifier.cycleCurrency(direction)) {
          AppHaptics.selection();
          if (_swipedThisSession == false) {
            setState(() => _swipedThisSession = true);
            notifier.dismissPriceSwipeHint();
          }
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
          if (picked.length == 1 && _swipedThisSession == false) {
            setState(() => _swipedThisSession = true);
            notifier.dismissPriceSwipeHint();
          }
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
      onOpenConverter: widget.onOpenConverter,
    );
  }
}

String _livePriceCadenceLabel(AppLocalizations l10n, LivePriceCadence c) {
  switch (c) {
    case LivePriceCadence.live:
      return l10n.livePriceCadenceLive;
    case LivePriceCadence.s5:
      return l10n.livePriceCadence5s;
    case LivePriceCadence.s15:
      return l10n.livePriceCadence15s;
  }
}

Future<LivePriceCadence?> _showLivePriceCadencePicker(
  BuildContext context,
  LivePriceCadence current,
) {
  return showDialog<LivePriceCadence>(
    context: context,
    barrierColor: appDialogBarrierColor(context),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return RadioGroup<LivePriceCadence>(
        groupValue: current,
        onChanged: (v) {
          AppHaptics.selection();
          Navigator.of(ctx).pop(v);
        },
        child: SimpleDialog(
          elevation: 24,
          shadowColor: Colors.black,
          title: Text(l10n.livePriceCadencePickerTitle),
          children: [
            for (final c in LivePriceCadence.values)
              RadioListTile<LivePriceCadence>(
                key: ValueKey('livePriceCadence-${c.code}'),
                title: Text(_livePriceCadenceLabel(l10n, c)),
                value: c,
              ),
          ],
        ),
      );
    },
  );
}
