import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../../api/api.dart';
import '../../../data/data.dart' hide Stack;
import '../../../l10n/generated/app_localizations.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../widgets/home_buttons.dart';
import '../widgets/retry_button.dart';
import 'area_chart.dart';
import 'current_price.dart';
import 'range_bar.dart';

/// Reports its child's size via [onChange] on every layout pass.
/// Used to track header height without resorting to a GlobalKey on the
/// header itself (which causes duplicate-key errors when the header is
/// rendered in two places for measurement + display).
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, required Widget super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  // ignore: library_private_types_in_public_api
  void updateRenderObject(BuildContext context, _MeasureSizeRenderObject renderObject) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize != newSize) {
      _oldSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
    }
  }
}

class PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const PinnedHeaderDelegate({
    required this.height,
    required this.child,
    this.constrained = false,
  });

  final double height;
  final Widget child;
  // When true, skips the OverflowBox so children receive tight height
  // constraints (needed for Expanded children in landscape mode).
  final bool constrained;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    if (constrained) {
      // No OverflowBox — give the child a tight height equal to the sliver
      // box so that Expanded children can distribute the space correctly.
      return SizedBox(height: height, child: child);
    }
    return ClipRect(
      child: OverflowBox(
        minHeight: 0,
        maxHeight: double.infinity,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(PinnedHeaderDelegate old) =>
      old.height != height || old.child != child || old.constrained != constrained;
}

class HomeHeader extends StatefulWidget {
  const HomeHeader({
    super.key,
    required this.failed,
    required this.showChart,
    required this.currentPrice,
    required this.hover,
    required this.lastFetchedAt,
    required this.range,
    required this.currency,
    required this.selectedCurrencies,
    required this.chartColor,
    required this.rangePct,
    required this.rangeAbsDiff,
    required this.rollDirection,
    required this.showSwipeHint,
    required this.currencyEverSwiped,
    required this.onPriceTap,
    required this.onGraphSettingsTap,
    required this.onCurrencySwipe,
    required this.onDismissSwipeHint,
    required this.chartData,
    required this.chartWindowStartMs,
    required this.chartWindowEndMs,
    required this.allHistoryEmpty,
    required this.usesAllHistory,
    required this.loading,
    required this.onRange,
    required this.onHover,
    required this.onRetry,
    this.onOpenConverter,
  });

  final bool failed;
  final bool showChart;
  final double? currentPrice;
  final ValueListenable<PricePoint?> hover;
  final DateTime? lastFetchedAt;
  final BtcRange range;
  final Currency currency;
  final List<Currency> selectedCurrencies;
  final Color chartColor;
  final double? rangePct;
  final double? rangeAbsDiff;
  final int rollDirection;
  final bool showSwipeHint;
  final bool currencyEverSwiped;
  final VoidCallback onPriceTap;
  // Tapped when the trailing settings (sliders) button on the range bar is
  // pressed. Opens the graph settings page (the range bar sits under the chart).
  final VoidCallback onGraphSettingsTap;
  final ValueChanged<int> onCurrencySwipe;
  final VoidCallback onDismissSwipeHint;
  final List<PricePoint> chartData;
  final int chartWindowStartMs;
  final int chartWindowEndMs;
  final bool allHistoryEmpty;
  final bool usesAllHistory;
  final bool loading;
  final ValueChanged<BtcRange> onRange;
  final ValueChanged<PricePoint?> onHover;
  final VoidCallback onRetry;
  final VoidCallback? onOpenConverter;
  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  // Latches to true the first time the user selects a non-All range while the
  // swipe-chip hint hasn't been dismissed yet. Once set it never clears, so
  // tapping back to All — or opening a full-screen page — does NOT hide the
  // tip. Only a vertical swipe on the pill (which calls dismissSwipeChipHint)
  // removes it.
  bool _hintTriggered = false;

  @override
  Widget build(BuildContext context) {
    final logScale = context.select<AppStateNotifier, bool>((a) => a.logScale);
    final chartHeight = context.select<AppStateNotifier, ChartHeight>((a) => a.chartHeight);
    final buttonsRow = OverflowButton(onOpenConverter: widget.onOpenConverter);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final priceRow = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      child: CurrentPrice(
        price: widget.currentPrice,
        hover: widget.hover,
        lastFetchedAt: widget.lastFetchedAt,
        range: widget.range,
        currency: widget.currency,
        selectedCurrencies: widget.selectedCurrencies,
        rangePct: widget.rangePct,
        rangeAbsDiff: widget.rangeAbsDiff,
        rollDirection: widget.rollDirection,
        showSwipeHint: widget.showSwipeHint,
        onPriceTap: widget.onPriceTap,
        onCurrencySwipe: widget.onCurrencySwipe,
        onDismissSwipeHint: widget.onDismissSwipeHint,
        chartColor: widget.chartColor,
        showChart: widget.showChart,
        trailing: buttonsRow,
      ),
    );

    // In landscape always show the chart+range bar regardless of the setting —
    // the stacks are hidden, so the chart fills the screen.
    if (!widget.showChart && !isLandscape) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [priceRow],
      );
    }

    final rangeBar = RangeBar(
      range: widget.range,
      chartColor: widget.chartColor,
      onRange: widget.onRange,
      onSettings: widget.onGraphSettingsTap,
    );

    if (isLandscape) {
      // 16px breathing room on all sides — but the graph stays edge to edge.
      // The padding wraps the price row (top + sides) and the range bar
      // (bottom + sides) while the chart Expanded fills the gap untouched.
      const pad = 16.0;
      return LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(pad * 2, pad, pad * 2, 0),
                child: priceRow,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: _buildChartArea(context, logScale: logScale),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildChipHint(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(pad, 0, pad, 4),
                child: rangeBar,
              ),
            ],
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        priceRow,
        const SizedBox(height: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              height: chartHeight.px,
              child: _buildChartArea(context, logScale: logScale),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildChipHint(context),
            ),
          ],
        ),
        rangeBar,
      ],
    );
  }

  Widget _buildChipHint(BuildContext context) {
    final swipeHintDismissed = context.select<AppStateNotifier, bool>(
        (a) => a.swipeChipHintDismissed);
    // Latch: only engage once the user has swiped the currency AND taps a
    // non-All range. Once latched it stays true for the session.
    if (widget.range != BtcRange.all && !swipeHintDismissed) {
      _hintTriggered = true;
    }
    final String? message;
    if (_hintTriggered && !swipeHintDismissed && widget.range != BtcRange.all) {
      message = AppLocalizations.of(context).homeSwipeChipHint;
    } else {
      message = null;
    }
    if (message == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(AppSpacing.md),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: AppTypography.body.copyWith(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartArea(BuildContext context, {required bool logScale}) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final loading =
        widget.usesAllHistory ? widget.allHistoryEmpty : widget.loading;

    final Widget child;
    if (loading) {
      child = Center(
        key: const ValueKey('loading'),
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: p.bitcoinOrange,
          ),
        ),
      );
    } else if (widget.failed) {
      child = Center(
        key: const ValueKey('failed'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).chartErrorTitle,
              style: AppTypography.body.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ChartRetryButton(onTap: widget.onRetry),
          ],
        ),
      );
    } else if (widget.chartData.length < 2) {
      child = const SizedBox.shrink(key: ValueKey('empty'));
    } else {
      child = AreaChart(
        // Two stable buckets — 'long' (all-history camera) and 'short'
        // (intraday) — rather than a per-range key. Keeping the key stable
        // *within* a bucket means switching between short ranges (2D → 3D,
        // 1W → 2W) reuses the same AreaChart instance, so its didUpdateWidget
        // zoom tween fires and the window animates exactly like the long-range
        // ranges do, instead of the AnimatedSwitcher hard-swapping a fresh
        // chart with no "from" state. Long↔short still swaps (different bucket)
        // since those datasets live on different scales and a fade reads better
        // there than a cross-scale pan.
        key: ValueKey(widget.usesAllHistory ? 'long' : 'short'),
        data: widget.chartData,
        windowStartMs: widget.chartWindowStartMs,
        windowEndMs: widget.chartWindowEndMs,
        color: widget.chartColor,
        logScale: logScale,
        rangeKey: widget.range,
        onHover: widget.onHover,
      );
    }

    return AnimatedSwitcher(
      duration: AppSpacing.motionDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

