import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../services/stacks_unlock_orchestrator.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/avatar_sheet.dart';
import '../../widgets/menu_action_tile.dart';
import '../../widgets/scroll_hairline.dart';
import '../../widgets/stack_card.dart';
import '../pin_entry_screen.dart';
import '../settings_screen.dart';
import 'chart_slice.dart';
import 'header/home_header.dart';
import 'widgets/change_pills_hint.dart';
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

  // Cached range-window slice around the binary search in [ChartSlicer].
  // The two FX-conversion memos that used to live here moved onto
  // LivePriceController as convertedSeries / convertedAllHistory.
  final ChartSlicer _slicer = ChartSlicer();

  bool _needsData(AppStateNotifier app) => app.showChart;

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

  bool _isIntradayRange(BtcRange range) => range.isShortRange;

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

    final usesAllHistory = range.usesAllHistory;
    final allHistory = context.select<LivePriceController, List<HistoryPoint>>(
      (c) => c.allHistory,
    );
    // Subscribe to FX-history availability so the screen rebuilds (and the
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
    // `usdToCurrency` fallback if FX history hasn't loaded). The controller
    // owns the memo cache; calling these on every build is cheap.
    final priceController = context.read<LivePriceController>();
    final convertedSeries = priceController.convertedSeries(
      series: series,
      currency: currency,
      usdToCurrencyFallback: usdToCurrency,
    );
    final convertedAllHistoryBase = priceController.convertedAllHistory(
      currency: currency,
      usdToCurrencyFallback: usdToCurrency,
    );

    final List<PricePoint> chartData;
    if (currentPrice > 0 && !intradayStale) {
      chartData = [
        ...convertedSeries,
        PricePoint(DateTime.now().millisecondsSinceEpoch, currentPrice),
      ];
    } else {
      chartData = convertedSeries;
    }

    // Long-range chart rendering uses the full all-history curve so switching
    // between 3M–All animates the visible window as a camera zoom. The "now"
    // point is appended here rather than inside the memo so the cache doesn't
    // invalidate on every live tick.
    final convertedAllHistory = currentPrice > 0
        ? [
            ...convertedAllHistoryBase,
            PricePoint(DateTime.now().millisecondsSinceEpoch, currentPrice),
          ]
        : convertedAllHistoryBase;

    // The price chart, delta text and range-pill percentages are always
    // bitcoin orange — we no longer tint them green/red by direction.
    final chartColor = p.bitcoinOrange;
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

    HomeHeader buildHeader() => HomeHeader(
      failed: intradayFailed,
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
        if (notifier.cycleCurrency(direction)) {
          AppHaptics.selection();
          return;
        }
        // 0/1 currencies in the ring: nothing to cycle to. Open the picker so
        // the user can add another, then adopt their selection on return.
        final picked = await Navigator.of(context).push<List<Currency>>(
          MaterialPageRoute(
            builder: (_) => CurrencyPickerScreen(initial: notifier.selectedCurrencies),
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
            rangePillData: convertedAllHistory,
            // showTotal already implies stacks.length >= 2, so the total is
            // always the last row of a non-empty group.
            totalCard: showTotal
                ? _totalCard(context, app, totalSats, currency, rate)
                : null,
            totalSats: showTotal ? totalSats : null,
          ),
        // One-time hint, below the stack list, teaching the swipe-to-reveal
        // gesture for the range/change pills. Stays until the user dismisses
        // it (persisted), regardless of how many stacks they later add.
        if (stacks.isNotEmpty && !app.changePillsHintDismissed) ...[
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: ChangePillsHint(
              onDismiss: () => context
                  .read<AppStateNotifier>()
                  .dismissChangePillsHint(),
            ),
          ),
        ],
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
        imageData: app.state.totalImageData,
        colorKey: app.state.totalColorKey,
        position: StackCardPosition.last,
        onTap: () {
          AppHaptics.light();
          _showTotalMenu(cardContext, app);
        },
        onAvatarTap: () {
          AppHaptics.light();
          _showTotalAvatarSheet(cardContext, app);
        },
      ),
    );
  }

  Future<void> _showTotalAvatarSheet(
    BuildContext iconContext,
    AppStateNotifier app,
  ) {
    final l10n = AppLocalizations.of(iconContext);
    return showAvatarSheet(
      iconContext,
      title: l10n.totalCardName,
      currentImageData: app.state.totalImageData,
      currentColorKey: app.state.totalColorKey,
      onColorSet: app.setTotalColorKey,
      onImageSet: app.setTotalImageData,
      onImageCleared: () => app.setTotalImageData(null),
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

