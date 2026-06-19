import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollCtrl = ScrollController();
  // 0..1 hairline strength below the pinned header, derived from scroll
  // offset. Ramped over the first 24px of scroll so the line eases in
  // instead of popping; rebuilding only the line keeps the rest static.
  final ValueNotifier<double> _headerHairline = ValueNotifier(0);
  bool _prevNeedsData = true;
  bool? _appliedLandscape;

  double? _headerHeight;
  double? _stacksTitleHeight;
  // Header height minus the chart area's current pixel height — i.e. the price
  // row, spacers and range bar, which never change height. Derived from each
  // measurement so the pinned-header box can be sized as chrome + the *target*
  // chart height instantly, instead of chasing the chart's animated size one
  // frame behind. Without this the box lagged the growing chart by a frame,
  // which clipped the range bar (and shuffled the price) mid-animation.
  double? _headerChrome;

  // Animates the SliverPersistentHeader box height in sync with the
  // AnimatedContainer inside HomeHeader so the ClipRect never clips
  // the RangeBar during a height transition.
  double? _animatedChartPx;
  AnimationController? _chartHeightCtrl;
  Animation<double>? _chartHeightAnim;

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
      final chartPx = context.read<AppStateNotifier>().chartHeight.px;
      // While the chart-height animation is running, the AnimatedContainer
      // reports intermediate sizes on every frame, which would corrupt
      // _headerChrome (= header - chartPx) with a mid-animation height.
      // Skip the chrome update until the animation settles; the tween already
      // keeps the sliver box correctly sized during the transition.
      final animating = _chartHeightCtrl?.isAnimating ?? false;
      setState(() {
        _headerHeight = size.height;
        if (!animating) {
          // Capture the non-chart chrome so the build can reserve the box at
          // chrome + target chart height without waiting for the chart's
          // animation to finish.
          _headerChrome = size.height - chartPx;
        }
      });
      // A header-height change (e.g. toggling the chart in settings) can
      // shrink the scrollable's max extent and clamp the scroll offset
      // without firing the controller's listener in time, leaving the
      // hairline stuck at its pre-toggle alpha. Resync from the current
      // offset so the line matches the post-layout scroll state.
      _onScroll();
    });
  }

  bool _needsData(AppStateNotifier app) => app.showChart;

  void _applySystemUI({required bool landscape}) {
    if (_appliedLandscape == landscape) return;
    _appliedLandscape = landscape;
    if (landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void initState() {
    super.initState();
    final initialPx = context.read<AppStateNotifier>().chartHeight.px;
    _animatedChartPx = initialPx;
    _chartHeightCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..value = 1.0;
    _chartHeightAnim = Tween<double>(begin: initialPx, end: initialPx).animate(
      CurvedAnimation(parent: _chartHeightCtrl!, curve: Curves.easeInOutCubic),
    );
    _chartHeightCtrl!.addListener(() {
      if (!mounted) return;
      setState(() {
        // When the animation completes, sync _headerChrome from the last
        // measured header height so it reflects the final settled size.
        if (_chartHeightCtrl!.isCompleted && _headerHeight != null) {
          _headerChrome = _headerHeight! - _animatedChartPx!;
        }
      });
    });
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
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    _applySystemUI(landscape: isLandscape);
    final app = context.read<AppStateNotifier>();
    final nowNeeds = _needsData(app) || isLandscape;
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
    _chartHeightCtrl?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

    final newChartPx = app.chartHeight.px;
    if (_animatedChartPx != null &&
        newChartPx != _animatedChartPx &&
        _chartHeightCtrl != null &&
        _chartHeightAnim != null) {
      final fromPx = _chartHeightAnim!.value;
      _chartHeightAnim = Tween<double>(begin: fromPx, end: newChartPx).animate(
        CurvedAnimation(parent: _chartHeightCtrl!, curve: Curves.easeInOutCubic),
      );
      _animatedChartPx = newChartPx;
      _chartHeightCtrl!
        ..value = 0.0
        ..forward();
    }

    final lock = context.watch<StacksLockController>();
    final stacksLocked = lock.isLocked;
    final cs = Theme.of(context).colorScheme;
    final stacks = app.stacks;

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    // In landscape the chart is always shown (stacks are hidden, chart fills
    // the screen) regardless of the user's showChart setting.
    final effectiveShowChart = app.showChart || isLandscape;

    // All live-price subscriptions live inside HomeHeaderSection (and the
    // per-card fiat amounts down in the stack list), so a price tick rebuilds
    // the header slab and those leaves — not this build or the scroll body.
    final headerSection = HomeHeaderSection(
      range: app.btcRange,
      currency: app.currency,
      selectedCurrencies: app.selectedCurrencies,
      showChart: effectiveShowChart,
      onRange: (r) {
        app.setBtcRange(r);
        if (effectiveShowChart) _maybeFetchIntraday(r);
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
                  IgnorePointer(
                    ignoring: stacksLocked,
                    child: Opacity(
                      opacity: stacksLocked ? 0.35 : 1.0,
                      child: AddStackIconButton(onTap: _onAddStackTap),
                    ),
                  ),
                  // The lock/unlock control sits to the right of the add button
                  // and shares its styling. It appears only when stack-lock
                  // auth is enabled; when locked, it's the sole control (add and
                  // the overflow menu are hidden until the stacks are unlocked).
                  if (app.stacksAuthMode != StacksAuthMode.off) ...[
                    const SizedBox(width: 20),
                    StackLockIconButton(
                      locked: stacksLocked,
                      // Greyed out only in the unlocked, zero-stacks case where
                      // there's nothing to lock. While locked the button must
                      // always stay live — it's the sole way back in, and the
                      // decrypted `stacks` list is empty under lock so checking
                      // it here would trap the user out of their own data.
                      enabled: stacksLocked || stacks.isNotEmpty,
                      tooltip: stacksLocked
                          ? AppLocalizations.of(context).homeUnlockStacks
                          : AppLocalizations.of(context).settingsLockStacks,
                      onTap: stacksLocked
                          ? () => _attemptUnlock(context)
                          : () => context
                                .read<StacksLockController>()
                                .lockNow(),
                    ),
                  ],
                  // The overflow menu offers actions that need at least one
                  // stack (portfolio total, reorder) plus the lock settings
                  // entry, so it's hidden — along with its leading spacer —
                  // only in the unlocked, zero-stacks state. While locked it
                  // stays visible: lock settings is the one action that still
                  // applies, and it's the user's way to those settings without
                  // first unlocking.
                  if (stacks.isNotEmpty || stacksLocked) ...[
                    const SizedBox(width: 20),
                    const StacksOverflowButton(),
                  ],
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
        // In landscape full-screen the chart and its controls flow behind the
        // display cutout (front camera) — don't reserve the left/right safe
        // insets that would otherwise push content off the cutout edge. The
        // top inset is also gone since immersive mode hides the status bar.
        top: !isLandscape,
        left: !isLandscape,
        right: !isLandscape,
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
                    // In landscape the header fills the full viewport height.
                    // constrained:true skips the OverflowBox so the Column
                    // inside HomeHeader gets tight constraints and Expanded
                    // can distribute the remaining space to the chart.
                    // In portrait, use chrome + animated chart height so the
                    // box is full-size before the chart starts animating.
                    height: isLandscape
                        ? MediaQuery.sizeOf(context).height -
                            MediaQuery.paddingOf(context).top
                        : _headerChrome != null && _chartHeightAnim != null
                            ? _headerChrome! + _chartHeightAnim!.value
                            : _headerHeight!,
                    constrained: isLandscape,
                    child: measuredHeader,
                  ),
                )
              else
                SliverToBoxAdapter(child: measuredHeader),
              if (!isLandscape) ...[
                if (stacks.isNotEmpty || (stacksLocked && app.lockedStackCount > 0)) ...[
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
                ],
                if (stacksLocked && app.lockedStackCount > 0)
                  SliverPadding(
                    padding: stacksAreaPadding,
                    sliver: SliverToBoxAdapter(
                      child: LockedStacksSkeleton(
                        stackCount: app.lockedStackCount,
                        showTotal: app.showPortfolio && app.lockedStackCount >= 2,
                        onTap: () => _attemptUnlock(context),
                      ),
                    ),
                  )
                else if (stacks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Align(
                      alignment: const Alignment(0, -0.2),
                      child: FilledButton(
                        onPressed: _onAddStackTap,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.surfaceContainer,
                          foregroundColor: cs.onSurfaceVariant,
                          minimumSize: const Size(0, 64),
                          textStyle: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radius),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl,
                            vertical: AppSpacing.md,
                          ),
                        ),
                        child: Text(AppLocalizations.of(context).homeAddStack),
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

  void _onAddStackTap() {
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

