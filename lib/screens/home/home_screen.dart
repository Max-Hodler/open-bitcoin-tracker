import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../services/stacks_unlock_orchestrator.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/avatar_sheet.dart';
import '../../widgets/scroll_hairline.dart';
import '../../widgets/stack_card.dart';
import '../pin_entry_screen.dart';
import '../settings/settings_dialogs.dart';
import 'header/home_header.dart';
import 'header/home_header_section.dart';
import 'widgets/home_buttons.dart';
import 'widgets/locked_stacks_skeleton.dart';
import 'widgets/stacks_widget.dart';
import '../stack_detail/total_detail_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onAddStack,
    this.onOpenConverter,
  });

  final VoidCallback? onAddStack;
  final VoidCallback? onOpenConverter;

  @override
  State<HomeScreen> createState() => _HomeScreenState();

}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  // 0..1 hairline strength below the pinned header, derived from scroll
  // offset. Ramped over the first 24px of scroll so the line eases in
  // instead of popping; rebuilding only the line keeps the rest static.
  final ValueNotifier<double> _headerHairline = ValueNotifier(0);
  bool _prevNeedsData = true;

  double? _headerHeight;
  double? _stacksTitleHeight;

  void _onStacksTitleMeasured(Size size) {
    if (size.height == _stacksTitleHeight) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _stacksTitleHeight = size.height);
    });
  }

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
    final app = context.watch<AppStateNotifier>();
    final lock = context.watch<StacksLockController>();
    final stacksLocked = lock.isLocked;
    final cs = Theme.of(context).colorScheme;
    final stacks = app.stacks;

    // All live-price subscriptions live inside HomeHeaderSection (and the
    // per-card fiat amounts down in the stack list), so a price tick rebuilds
    // the header slab and those leaves — not this build or the scroll body.
    final headerSection = HomeHeaderSection(
      range: app.btcRange,
      currency: app.currency,
      selectedCurrencies: app.selectedCurrencies,
      showChart: app.showChart,
      onRange: (r) {
        app.setBtcRange(r);
        if (_needsData(app)) _maybeFetchIntraday(r);
      },
      onRetry: () {
        AppHaptics.light();
        context.read<LivePriceController>().restartStream();
        _maybeFetchIntraday(app.btcRange, force: true);
      },
      onOpenConverter: widget.onOpenConverter,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildOrderedWidgets(context, app),
    );

    // The "Stacks" section title pins below the header and stays put while the
    // cards scroll underneath. Always shown — including the first-run empty
    // state, where it sits above the "add a stack" hint.
    final stacksTitle = MeasureSize(
      onChange: _onStacksTitleMeasured,
      child: ColoredBox(
        color: cs.surfaceContainerLow,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.md,
                top: AppSpacing.lg,
                bottom: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Stacks',
                      style: AppTypography.body.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // The lock/unlock control sits to the left of the add button
                  // and shares its styling. It appears only when stack-lock
                  // auth is enabled; when locked, it's the sole control (add and
                  // the overflow menu are hidden until the stacks are unlocked).
                  if (app.stacksAuthMode != StacksAuthMode.off) ...[
                    StackLockIconButton(
                      locked: stacksLocked,
                      tooltip: stacksLocked
                          ? AppLocalizations.of(context).homeUnlockStacks
                          : AppLocalizations.of(context).settingsLockStacks,
                      onTap: stacksLocked
                          ? () => _attemptUnlock(context)
                          : () => context
                                .read<StacksLockController>()
                                .lockNow(),
                    ),
                    const SizedBox(width: 20),
                  ],
                  IgnorePointer(
                    ignoring: stacksLocked,
                    child: Opacity(
                      opacity: stacksLocked ? 0.35 : 1.0,
                      child: Row(
                        children: [
                          AddStackIconButton(onTap: _onAddStackTap),
                          const SizedBox(width: 20),
                          const StacksOverflowButton(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

    // Bottom padding for the stacks area — just the gap below the last card.
    // (The lock/unlock control now lives in the title row, so no
    // floating-action-button clearance is reserved here anymore.)
    const stacksAreaPadding = EdgeInsets.only(bottom: AppSpacing.xl);

    // The scroll hairline lives at the bottom edge of the pinned "Stacks"
    // title (see below) — the lowest pinned element — so it reads as the
    // divider between the title and the cards scrolling under it, not below
    // the range-selector bar.
    final measuredHeader = MeasureSize(
      onChange: _onHeaderMeasured,
      // Vertical swipes that start on the header slab must not drive the
      // scroll view (or its overscroll stretch) — only the widget area below
      // scrolls the page. The deepest recognizer wins the arena tie, so this
      // no-op drag handler beats the CustomScrollView's; taps and the chart's
      // raw-pointer scrubbing are unaffected.
      child: GestureDetector(
        onVerticalDragUpdate: (_) {},
        child: ColoredBox(
          color: cs.surfaceContainerLow,
          child: headerSection,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: SafeArea(
        bottom: false,
        // Resync the hairline when the scrollable's extents change without a
        // scroll — toggling a home widget off in settings can shrink the
        // content below the fold without firing the controller's listener,
        // which would leave the line stuck at its pre-toggle alpha. The
        // framework dispatches this notification (post-frame) exactly when
        // the metrics change, so no per-build callback is needed.
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _onScroll();
            return false;
          },
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
              if (_stacksTitleHeight != null)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: PinnedHeaderDelegate(
                    height: _stacksTitleHeight!,
                    child: stacksTitle,
                  ),
                )
              else
                SliverToBoxAdapter(child: stacksTitle),
              if (stacks.isEmpty && !stacksLocked && !app.hasEverAddedStack)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: Builder(
                        builder: (context) {
                          final cs = Theme.of(context).colorScheme;
                          final style = AppTypography.body.copyWith(
                            fontSize: 15,
                            color: cs.onSurfaceVariant,
                          );
                          final parts = AppLocalizations.of(context)
                              .homeEmptyStacksHint
                              .split('@+');
                          return Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: parts.first),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Icon(
                                    Icons.add,
                                    size: 26,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                if (parts.length > 1)
                                  TextSpan(text: parts[1]),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            style: style,
                          );
                        },
                      ),
                    ),
                  ),
                )
              else if (stacksLocked && app.lockedStackCount > 0)
                SliverPadding(
                  padding: stacksAreaPadding,
                  sliver: SliverToBoxAdapter(
                    child: LockedStacksSkeleton(
                      stackCount: app.lockedStackCount,
                      showTotal: app.showPortfolio && app.lockedStackCount >= 2,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: stacksAreaPadding,
                  sliver: SliverToBoxAdapter(
                    child: content,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Per-widget renderers for the reorderable home-widgets list. Each block
  /// contributes a list of children so this method can interleave SizedBox
  /// gaps without nesting Columns.
  List<Widget> _buildOrderedWidgets(BuildContext context, AppStateNotifier app) {
    final result = <Widget>[];
    for (var i = 0; i < app.homeWidgetOrder.length; i++) {
      final hw = app.homeWidgetOrder[i];
      final List<Widget> children;
      switch (hw) {
        case HomeWidget.stacks:
          children = _stacksBlock(context, app);
      }
      if (children.isEmpty) continue;
      if (result.isNotEmpty) {
        result.add(const SizedBox(height: AppSpacing.lg));
      }
      result.addAll(children);
    }
    return result;
  }

  List<Widget> _stacksBlock(BuildContext context, AppStateNotifier app) {
    final stacks = app.stacks;
    final currency = app.currency;
    final showTotal = app.showPortfolio && stacks.length >= 2;
    final totalSats = stacks.fold<int>(0, (sum, s) => sum + s.sats);
    return [
      if (stacks.isNotEmpty)
        HomeStackList(
          stacks: stacks,
          currency: currency,
          btcDisplayMode: app.btcDisplayMode,
          totalCard: showTotal
              ? _totalCard(context, app, totalSats, currency)
              : null,
        ),
    ];
  }

  Widget _totalCard(
    BuildContext context,
    AppStateNotifier app,
    int totalSats,
    Currency currency,
  ) {
    final l10n = AppLocalizations.of(context);
    return Builder(
      // Selecting the rate here (not in the screen build) confines the
      // per-tick rebuild to this card's subtree.
      builder: (cardContext) => StackCard(
        name: l10n.totalCardName,
        sats: totalSats,
        currency: currency,
        btcRate: cardContext.select<LivePriceController, double?>(
          (c) => c.rates.forCurrency(currency),
        ),
        btcDisplayMode: app.btcDisplayMode,
        imageData: app.state.totalImageData,
        colorKey: app.state.totalColorKey ?? 'grey',
        position: StackCardPosition.last,
        onTap: () {
          AppHaptics.light();
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const TotalDetailScreen(),
            ),
          );
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
      currentColorKey: app.state.totalColorKey ?? 'grey',
      onColorSet: (key) => app.setTotalColorKey(key ?? 'orange'),
      onImageSet: app.setTotalImageData,
      onImageCleared: () => app.setTotalImageData(null),
    );
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
    // Unlock and haptic already fired in PinEntryScreen._handleVerify so
    // the home screen updates during the pop animation. Nothing to do here.
  }

  Future<void> _onAddStackTap() async {
    final app = context.read<AppStateNotifier>();
    if (app.stacks.isEmpty) {
      final picked = await showBitcoinUnitDialog(context, app.btcDisplayMode);
      if (!mounted || picked == null) return;
      app.setBitcoinDisplayMode(picked);
    }
    widget.onAddStack?.call();
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

