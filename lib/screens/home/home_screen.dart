import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../data/app_enums.dart';
import '../../data/fx_history.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../services/stacks_unlock_orchestrator.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/menu_action_tile.dart';
import '../../widgets/scroll_hairline.dart';
import '../../widgets/stack_card.dart';
import '../pin_entry_screen.dart';
import '../settings_screen.dart';
import '_chart_slice.dart';
import 'header/area_chart.dart';
import 'header/home_header.dart';
import 'widgets/hashrate_card.dart';
import 'widgets/home_buttons.dart';
import 'widgets/mempool_card.dart';
import 'widgets/stacks_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onAddStack,
    this.onOpenConverter,
    this.onOpenSettings,
  });

  final VoidCallback? onAddStack;
  final VoidCallback? onOpenConverter;
  final VoidCallback? onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();

}

class _HomeScreenState extends State<HomeScreen> {
  final ValueNotifier<PricePoint?> _hover = ValueNotifier(null);
  final ScrollController _scrollCtrl = ScrollController();
  // 0..1 hairline strength below the pinned header, derived from scroll
  // offset. Ramped over the first 24px of scroll so the line eases in
  // instead of popping; rebuilding only the line keeps the rest static.
  final ValueNotifier<double> _headerHairline = ValueNotifier(0);
  bool _prevNeedsData = true;

  // Tracks the direction of the last live USD tick so the rolling-digit
  // animation in the price header knows whether to roll up (price went up) or
  // down (price went down). Read in build(), updated when usdRate changes.
  double? _prevUsd;
  int _rollDirection = 1;

  int _lastHoverHapticMs = 0;

  double? _headerHeight;

  void _onHeaderMeasured(Size size) {
    if (size.height == _headerHeight) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _headerHeight = size.height);
      // A header-height change (e.g. toggling the chart in settings) can
      // shrink the scrollable's max extent and clamp the scroll offset
      // without firing the controller's listener in time, leaving the
      // hairline stuck at its pre-toggle alpha. Resync from the current
      // offset so the line matches the post-layout scroll state.
      _onScroll();
    });
  }

  // Three independent one-entry memos. Re-fetching from the controller hands
  // back the same list object until the next merge, so identity (`identical`)
  // is enough to short-circuit the fiat-conversion list comprehensions.
  //   - _memo*Converted:    series-fiat conversion for the active range
  //   - _memoAllHistory*:   ditto for the full all-history curve (used by the
  //                         long-range "camera zoom" chart and the range pills)
  //   - _slicer:            range-window cache around the binary search in
  //                         [ChartSlicer] (file: lib/screens/home/_chart_slice.dart)
  // The fiat conversion now keys on (series identity, currency, FX-history
  // identity) instead of a single scalar rate: each historical point is
  // converted by its own day's FX rate, so the cache must invalidate whenever
  // the currency changes or the bundled FX object first loads. When FX history
  // hasn't loaded yet (`_memoFx == null`) the blocks fall back to the live
  // `usdToCurrency` scalar — `_memoUsdToCurrency` guards that fallback path.
  List<HistoryPoint>? _memoSeries;
  Currency? _memoCurrency;
  FxHistory? _memoFx;
  double _memoUsdToCurrency = double.nan;
  List<PricePoint> _memoConverted = const [];

  List<HistoryPoint>? _memoAllHistorySeries;
  Currency? _memoAllHistoryCurrency;
  FxHistory? _memoAllHistoryFx;
  double _memoAllHistoryUsdToCurrency = double.nan;
  List<PricePoint> _memoAllHistoryConverted = const [];

  final ChartSlicer _slicer = ChartSlicer();

  bool _needsData(AppStateNotifier app) => app.showChart && app.showBtcPrice;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    final app = context.read<AppStateNotifier>();
    _prevNeedsData = _needsData(app);
    // Deferred to a post-frame callback so fetchIntraday's notifyListeners
    // doesn't run during the in-progress mount and trip markNeedsBuild.
    if (_prevNeedsData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeFetchIntraday(app.btcRange);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppStateNotifier>();
    final nowNeeds = _needsData(app);
    if (nowNeeds && !_prevNeedsData) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeFetchIntraday(app.btcRange);
      });
    }
    _prevNeedsData = nowNeeds;
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _headerHairline.dispose();
    _hover.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    // When content fits in the viewport, no hairline — even if a stale offset
    // lingers from a prior layout (e.g., the user scrolled, then toggled a
    // home widget off in settings, shrinking the body below the fold).
    final pos = _scrollCtrl.position;
    final t = pos.maxScrollExtent <= 0
        ? 0.0
        : (pos.pixels / 24.0).clamp(0.0, 1.0);
    if (t != _headerHairline.value) _headerHairline.value = t;
  }

  void _maybeFetchIntraday(BtcRange range, {bool force = false}) {
    final controller = context.read<LivePriceController>();
    if (!_isIntradayRange(range)) {
      controller.setActiveIntradayRange(null);
      return;
    }
    controller.setActiveIntradayRange(range);
    controller.fetchIntraday(range, force: force);
  }

  bool _isIntradayRange(BtcRange range) =>
      range == BtcRange.d1 || range == BtcRange.w1 || range == BtcRange.m1;

  @override
  Widget build(BuildContext context) {
    // Resync the hairline after layout — toggling a home widget off in
    // settings can shrink the scrollable below the fold without firing the
    // scroll listener, leaving the line stuck at its pre-toggle alpha.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
    final app = context.watch<AppStateNotifier>();
    final lock = context.watch<StacksLockController>();
    final stacksLocked = lock.isLocked;
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final currency = app.currency;
    final range = app.btcRange;

    final currentPrice = context.select<LivePriceController, double>(
      (c) => c.rates.forCurrency(currency) ?? 0,
    );
    final usdRate = context.select<LivePriceController, double>(
      (c) => c.rates.usd ?? 0,
    );
    final usdToCurrency = usdRate > 0 ? currentPrice / usdRate : 1.0;

    if (usdRate > 0) {
      final prev = _prevUsd;
      _prevUsd = usdRate;
      if (prev != null && prev != usdRate) {
        _rollDirection = usdRate > prev ? 1 : -1;
      }
    }

    final usesAllHistory =
        range == BtcRange.all ||
        range == BtcRange.m2 ||
        range == BtcRange.m3 ||
        range == BtcRange.m4 ||
        range == BtcRange.m5 ||
        range == BtcRange.m6 ||
        range == BtcRange.m7 ||
        range == BtcRange.m8 ||
        range == BtcRange.m9 ||
        range == BtcRange.m10 ||
        range == BtcRange.m11 ||
        range == BtcRange.m12 ||
        range == BtcRange.ytd ||
        range == BtcRange.y1 ||
        range == BtcRange.y2 ||
        range == BtcRange.y3 ||
        range == BtcRange.y4 ||
        range == BtcRange.y5 ||
        range == BtcRange.y6 ||
        range == BtcRange.y7 ||
        range == BtcRange.y8 ||
        range == BtcRange.y9 ||
        range == BtcRange.y10 ||
        range == BtcRange.y11 ||
        range == BtcRange.y12 ||
        range == BtcRange.y13 ||
        range == BtcRange.y14 ||
        range == BtcRange.y15;
    final allHistory = context.select<LivePriceController, List<HistoryPoint>>(
      (c) => c.allHistory,
    );
    // Bundled daily FX history. Null until the asset finishes loading; while
    // null the conversion blocks fall back to the live `usdToCurrency` scalar.
    final fxHistory = context.select<LivePriceController, FxHistory?>(
      (c) => c.fxHistory,
    );
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
    final series = usesAllHistory
        ? _slicer.slice(allHistory, range)
        : (intradaySeries ?? const <HistoryPoint>[]);

    // Convert each historical point by its own day's FX rate. While FX history
    // hasn't loaded, fall back to the live `usdToCurrency` scalar. The memo
    // invalidates on series identity, currency, the FX object first loading,
    // and (fallback only) the scalar rate.
    if (!identical(_memoSeries, series) ||
        _memoCurrency != currency ||
        !identical(_memoFx, fxHistory) ||
        (fxHistory == null && _memoUsdToCurrency != usdToCurrency)) {
      _memoSeries = series;
      _memoCurrency = currency;
      _memoFx = fxHistory;
      _memoUsdToCurrency = usdToCurrency;
      final fx = fxHistory;
      _memoConverted = [
        for (final p in series)
          PricePoint(
            p.timeMs,
            p.priceUsd *
                (fx != null ? fx.rateAt(currency, p.timeMs) : usdToCurrency),
          ),
      ];
    }

    final List<PricePoint> chartData;
    if (currentPrice > 0) {
      chartData = [..._memoConverted, PricePoint(DateTime.now().millisecondsSinceEpoch, currentPrice)];
    } else {
      chartData = _memoConverted;
    }

    // Long-range chart rendering uses the full all-history curve so switching
    // between 3M–All animates the visible window as a camera zoom; cache the
    // fiat-converted series separately from the range-specific one.
    if (!identical(_memoAllHistorySeries, allHistory) ||
        _memoAllHistoryCurrency != currency ||
        !identical(_memoAllHistoryFx, fxHistory) ||
        (fxHistory == null && _memoAllHistoryUsdToCurrency != usdToCurrency)) {
      _memoAllHistorySeries = allHistory;
      _memoAllHistoryCurrency = currency;
      _memoAllHistoryFx = fxHistory;
      _memoAllHistoryUsdToCurrency = usdToCurrency;
      final fx = fxHistory;
      _memoAllHistoryConverted = [
        for (final p in allHistory)
          PricePoint(
            p.timeMs,
            p.priceUsd *
                (fx != null ? fx.rateAt(currency, p.timeMs) : usdToCurrency),
          ),
        if (currentPrice > 0)
          PricePoint(DateTime.now().millisecondsSinceEpoch, currentPrice),
      ];
    }

    final isUp = chartData.length >= 2 &&
        chartData.last.price >= chartData.first.price;
    final chartColor = isUp ? p.priceUp : p.priceDown;
    final rangePct = chartData.length >= 2 && chartData.first.price > 0
        ? (chartData.last.price - chartData.first.price) / chartData.first.price * 100
        : null;

    final stacks = app.stacks;
    final showTotal = app.showPortfolio && stacks.length >= 2;
    final totalSats = stacks.fold<int>(0, (sum, s) => sum + s.sats);
    final rate = context.select<LivePriceController, double?>(
      (c) => c.rates.forCurrency(currency),
    );

    // The chart renders the full all-history curve when the range is long
    // (3M–All) so switching between those ranges can animate the visible
    // window as a camera zoom instead of swapping the line. For intraday
    // ranges (1D/1W/1M) the data isn't part of all-history, so we use the
    // range-specific chartData and the window just covers the series.
    final chartRenderData = usesAllHistory ? _memoAllHistoryConverted : chartData;
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

    HomeHeader buildHeader() => HomeHeader(
      failed: intradayFailed,
      showBtcPrice: app.showBtcPrice,
      showChart: app.showChart,
      currentPrice: currentPrice,
      hover: _hover,
      lastFetchedAt: lastFetchedAt,
      range: range,
      currency: currency,
      selectedCurrencies: app.selectedCurrencies,
      chartColor: chartColor,
      rangePct: rangePct,
      rollDirection: _rollDirection,
      onPriceTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const BtcPriceSettingsScreen(),
        ),
      ),
      onCurrencySwipe: (direction) async {
        final notifier = context.read<AppStateNotifier>();
        final ring = notifier.selectedCurrencies;
        // 0/1 selected: nothing to cycle to, fall back to opening the picker.
        if (ring.length <= 1) {
          final picked = await Navigator.of(context).push<List<Currency>>(
            MaterialPageRoute(
              builder: (_) => CurrencyPickerScreen(initial: ring),
            ),
          );
          if (picked != null && context.mounted) {
            notifier.setSelectedCurrencies(picked);
          }
          return;
        }
        final i = ring.indexOf(currency);
        // If the active currency was removed from the ring (e.g. cleared by an
        // external mutation), snap to the first ring entry rather than wrap
        // around index -1.
        final base = i < 0 ? 0 : i;
        final next = ring[(base + direction) % ring.length];
        AppHaptics.selection();
        notifier.setCurrency(next);
      },
      chartData: chartRenderData,
      chartWindowStartMs: chartWindowStartMs,
      chartWindowEndMs: chartWindowEndMs,
      allHistoryEmpty: allHistory.isEmpty,
      usesAllHistory: usesAllHistory,
      loading: intradayLoading,
      onRange: (r) {
        _hover.value = null;
        app.setBtcRange(r);
        if (_needsData(app)) _maybeFetchIntraday(r);
      },
      onHover: (p) {
        if (_hover.value?.t == p?.t) return;
        _hover.value = p;
        if (p != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastHoverHapticMs >= 90) {
            _lastHoverHapticMs = now;
            AppHaptics.selection();
          }
        }
      },
      onRetry: () {
        AppHaptics.light();
        context.read<LivePriceController>().restartStream();
        _maybeFetchIntraday(app.btcRange, force: true);
      },
      stacksLocked: stacksLocked,
      stacksAuthMode: app.stacksAuthMode,
      showConverterButton: app.showConverterButton,
      onOpenSettings: widget.onOpenSettings,
      onOpenConverter: widget.onOpenConverter,
    );

    // Per-widget renderers for the reorderable home-widgets list. Each one
    // returns a list of children so its caller can interleave SizedBox gaps
    // without nesting Columns.
    List<Widget> stacksBlock() {
      return [
        if (stacks.isNotEmpty)
          HomeStackList(
            stacks: stacks,
            currency: currency,
            btcRate: rate,
            bitcoinDisplayMode: app.bitcoinDisplayMode,
            rangePillData: _memoAllHistoryConverted,
            // showTotal already implies stacks.length >= 2, so the total is
            // always the last row of a non-empty group.
            totalCard: showTotal
                ? _totalCard(context, app, totalSats, currency, rate)
                : null,
            totalSats: showTotal ? totalSats : null,
          ),
        if (stacks.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: AddStackButton(onTap: widget.onAddStack),
          ),
        ],
      ];
    }

    Widget? mempoolBlock() => app.showMempool ? const MempoolCard() : null;

    Widget? hashrateBlock() =>
        app.showHashrate ? const HashrateCard() : null;

List<Widget> lockedStacksBlock() => [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: StacksLockedCard(onTap: () => _attemptUnlock(context)),
          ),
        ];

    // Build one content tree regardless of lock state — only the stacks slot
    // swaps between locked/unlocked children. Splitting this into two Columns
    // with distinct keys would force Flutter to discard and rebuild every
    // sibling subtree (mempool, hashrate) on each unlock, which re-runs their
    // first-frame setup (e.g. MempoolCard's post-frame jumpTo to recenter the
    // divider) and produces a visible flicker.
    List<Widget> buildOrderedWidgets() {
      final result = <Widget>[];
      for (var i = 0; i < app.homeWidgetOrder.length; i++) {
        final hw = app.homeWidgetOrder[i];
        final List<Widget> children;
        switch (hw) {
          case HomeWidget.stacks:
            children = stacksLocked ? lockedStacksBlock() : stacksBlock();
          case HomeWidget.mempoolFees:
            final block = mempoolBlock();
            children = block == null ? const [] : [block];
          case HomeWidget.networkHashrate:
            final block = hashrateBlock();
            children = block == null ? const [] : [block];
        }
        if (children.isEmpty) continue;
        if (result.isNotEmpty) {
          result.add(const SizedBox(height: AppSpacing.lg));
        }
        result.addAll(children);
      }
      return result;
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...buildOrderedWidgets(),
        const SizedBox(height: 64),
      ],
    );

    // Hairline lives inside the pinned-header slab (anchored to its bottom
    // edge) so it shares the slab's transform during overscroll. Drawing it
    // as a fixed-Y overlay outside the scroll view caused it to stay put
    // while the rest of the header drifted up on overscroll bounce — the
    // line then cut through the mempool pills below.
    final measuredHeader = MeasureSize(
      onChange: _onHeaderMeasured,
      child: ColoredBox(
        color: cs.surfaceContainerLow,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            buildHeader(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 1,
              child: ScrollHairlinePainter(strength: _headerHairline),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_headerHeight != null)
              SliverPersistentHeader(
                pinned: true,
                delegate: PinnedHeaderDelegate(
                  height: _headerHeight!,
                  child: measuredHeader,
                ),
              )
            else
              SliverToBoxAdapter(child: measuredHeader),
            SliverPadding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              sliver: SliverToBoxAdapter(
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalCard(
    BuildContext context,
    AppStateNotifier app,
    int totalSats,
    Currency currency,
    double? rate,
  ) {
    final l10n = AppLocalizations.of(context);
    return Builder(
      builder: (cardContext) => StackCard(
        name: l10n.totalCardName,
        sats: totalSats,
        currency: currency,
        btcRate: rate,
        bitcoinDisplayMode: app.bitcoinDisplayMode,
        position: StackCardPosition.last,
        onTap: () {
          AppHaptics.light();
          _showTotalMenu(cardContext, app);
        },
      ),
    );
  }

  Future<void> _showTotalMenu(BuildContext iconContext, AppStateNotifier app) async {
    final theme = Theme.of(iconContext);
    final cs = theme.colorScheme;
    final didHide = await showModalBottomSheet<bool>(
      context: iconContext,
      backgroundColor: theme.brightness == Brightness.dark
          ? cs.surfaceContainerHigh
          : cs.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MenuSheetHeader(l10n.totalCardName),
                MenuActionGroup(
                  children: [
                    MenuActionTile(
                      leading: const Icon(Icons.visibility_off_outlined),
                      label: l10n.totalMenuHide,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (didHide ?? false) {
      app.setShowPortfolio(false);
    }
  }

  Future<void> _attemptUnlock(BuildContext context) async {
    final mode = context.read<AppStateNotifier>().stacksAuthMode;
    final lock = context.read<StacksLockController>();
    if (mode == StacksAuthMode.off) {
      lock.unlock();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (mode == StacksAuthMode.device) {
      final orch = context.read<StacksUnlockOrchestrator>();
      final app = context.read<AppStateNotifier>();
      var outcome = await orch.unlockWithDevice();
      if (outcome == UnlockOutcome.wrongCredential &&
          !app.stacksEncryptedAtRest) {
        outcome = await orch.migrateOrInitDeviceMode();
      }
      if (!mounted) return;
      switch (outcome) {
        case UnlockOutcome.success:
          AppHaptics.medium();
          lock.unlock();
        case UnlockOutcome.wrongCredential:
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.snackAuthenticationFailed)),
          );
        case UnlockOutcome.corruptBlob:
          _handleCorruptStacks(messenger, l10n);
      }
      return;
    }
    // mode == pin
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => const PinEntryScreen.verify(),
      ),
    );
    if (!mounted) return;
    if (isPinCorruptResult(result)) {
      _handleCorruptStacks(messenger, l10n);
      return;
    }
    if (result == true) {
      AppHaptics.medium();
      lock.unlock();
    }
  }

  void _handleCorruptStacks(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
  ) {
    // The on-disk envelope failed its MAC check. The data cannot be recovered
    // — the only path forward is wiping wraps and stacks so the user can set
    // up the lock again from a clean state. We surface this here as a snack
    // bar; the destructive reset itself lives in Settings → Reset stacks lock
    // so the user has to make a deliberate choice.
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.snackStacksCorrupted)),
    );
  }
}

