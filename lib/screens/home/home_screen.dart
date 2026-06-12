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
import '../../widgets/menu_action_tile.dart';
import '../../widgets/scroll_hairline.dart';
import '../../widgets/stack_card.dart';
import '../new_stack_screens.dart';
import '../pin_entry_screen.dart';
import '../settings/settings_dialogs.dart';
import '../settings/stacks_settings_screen.dart';
import 'header/home_header.dart';
import 'header/home_header_section.dart';
import 'widgets/hashrate_card.dart';
import 'widgets/home_buttons.dart';
import 'widgets/home_hint_card.dart';
import 'widgets/locked_stacks_skeleton.dart';
import 'widgets/mempool_card.dart';
import 'widgets/stacks_widget.dart';

enum _TotalMenuAction { hide, settings, add }

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
  final ScrollController _scrollCtrl = ScrollController();
  // 0..1 hairline strength below the pinned header, derived from scroll
  // offset. Ramped over the first 24px of scroll so the line eases in
  // instead of popping; rebuilding only the line keeps the rest static.
  final ValueNotifier<double> _headerHairline = ValueNotifier(0);
  bool _prevNeedsData = true;

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
      stacksLocked: stacksLocked,
      stacksAuthMode: app.stacksAuthMode,
      onRange: (r) {
        app.setBtcRange(r);
        if (_needsData(app)) _maybeFetchIntraday(r);
      },
      onRetry: () {
        AppHaptics.light();
        context.read<LivePriceController>().restartStream();
        _maybeFetchIntraday(app.btcRange, force: true);
      },
      onOpenSettings: widget.onOpenSettings,
      onOpenConverter: widget.onOpenConverter,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._buildOrderedWidgets(context, app),
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
      // Vertical swipes that start on the header slab must not drive the
      // scroll view (or its overscroll stretch) — only the widget area below
      // scrolls the page. The deepest recognizer wins the arena tie, so this
      // no-op drag handler beats the CustomScrollView's; taps and the chart's
      // raw-pointer scrubbing are unaffected.
      child: GestureDetector(
        onVerticalDragUpdate: (_) {},
        child: ColoredBox(
          color: cs.surfaceContainerLow,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              headerSection,
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
      ),
    );

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      floatingActionButton: AddStackButton(onTap: _onAddStackTap),
      bottomNavigationBar: stacksLocked
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                child: UnlockStacksButton(
                  onTap: () => _attemptUnlock(context),
                ),
              ),
            )
          : null,
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
              if (stacks.isEmpty && !stacksLocked)
                const SliverFillRemaining(hasScrollBody: false)
              else if (stacksLocked)
                SliverToBoxAdapter(
                  child: LockedStacksSkeleton(
                    stackCount: app.lockedStackCount,
                    showTotal: app.showPortfolio && app.lockedStackCount >= 2,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
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
        case HomeWidget.mempoolFees:
          children = app.showMempool ? const [MempoolCard()] : const [];
        case HomeWidget.networkHashrate:
          children = app.showHashrate ? const [HashrateCard()] : const [];
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
    final l10n = AppLocalizations.of(context);
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
          // showTotal already implies stacks.length >= 2, so the total is
          // always the last row of a non-empty group.
          totalCard: showTotal
              ? _totalCard(context, app, totalSats, currency)
              : null,
          totalSats: showTotal ? totalSats : null,
        ),
      // One-time hint below the stack list: the swipe-to-reveal-pills
      // gesture. Stays until dismissed (persisted), regardless of how many
      // stacks exist.
      if (stacks.isNotEmpty && !app.changePillsHintDismissed) ...[
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: HomeHintCard(
            message: l10n.homeChangePillsHint,
            onDismiss: () =>
                context.read<AppStateNotifier>().dismissChangePillsHint(),
          ),
        ),
      ],
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
    final action = await showModalBottomSheet<_TotalMenuAction>(
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
                      onTap: () =>
                          Navigator.of(ctx).pop(_TotalMenuAction.hide),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                MenuActionGroup(
                  children: [
                    MenuActionTile(
                      leading: const Icon(Icons.settings_outlined),
                      label: l10n.stackMenuStacksSettings,
                      onTap: () =>
                          Navigator.of(ctx).pop(_TotalMenuAction.settings),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                MenuActionGroup(
                  children: [
                    MenuActionTile(
                      leading: const Icon(Icons.add),
                      label: l10n.homeAddStack,
                      onTap: () =>
                          Navigator.of(ctx).pop(_TotalMenuAction.add),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!iconContext.mounted) return;
    switch (action) {
      case _TotalMenuAction.hide:
        app.setShowPortfolio(false);
      case _TotalMenuAction.settings:
        await Navigator.of(iconContext).push(MaterialPageRoute<void>(
          builder: (_) => const StacksSettingsScreen(),
        ));
      case _TotalMenuAction.add:
        await Navigator.of(iconContext).push(MaterialPageRoute<void>(
          builder: (_) => const NewStackAmountScreen(),
        ));
      case null:
        break;
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
    // Unlock and haptic already fired in PinEntryScreen._handleVerify so
    // the home screen updates during the pop animation. Nothing to do here.
  }

  Future<void> _onAddStackTap() async {
    final app = context.read<AppStateNotifier>();
    final picked = await showBitcoinUnitDialog(context, app.btcDisplayMode);
    if (!mounted || picked == null) return;
    app.setBitcoinDisplayMode(picked);
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

