import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../api/api.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../../widgets/expandable_card.dart';
import '../header/area_chart.dart';
import 'hashrate_range_bar.dart';
import 'retry_button.dart';

/// Network hashrate card on the home screen. Polls the mempool.space hashrate
/// endpoint via [HashrateController] and displays the current EH/s value plus
/// a signed percent change vs the oldest sample in the active window. Tapping
/// the row expands an inline chart and pill bar; tapping again collapses it.
/// Until the user has ever expanded the card the row's range is the 3d
/// window; once they have, the row keeps reading whichever pill is currently
/// selected (e.g. `+14.2% 1Y`) — the selection persists across collapse.
class HashrateCard extends StatefulWidget {
  const HashrateCard({super.key});

  @override
  State<HashrateCard> createState() => _HashrateCardState();
}

class _HashrateCardState extends State<HashrateCard>
    with
        SingleTickerProviderStateMixin,
        ExpandableCardStateMixin<HashrateCard> {
  // Subscribe lazily in didChangeDependencies — initState can't context.read
  // safely. Cache the controller so dispose() doesn't need a context lookup,
  // which would assert "looking up a deactivated widget's ancestor is unsafe".
  HashrateController? _controller;

  // Range the row + chart display. Seeded from AppStateNotifier in
  // didChangeDependencies so the user's last selection survives app restart;
  // the field initializer below is only the pre-mount placeholder.
  HashrateRange _chartRange = HashrateRange.y1;
  // Scrubbed point on the chart. Drives the EH/s value and delta in the row
  // via ValueListenableBuilder so dragging doesn't rebuild the chart itself
  // (which would interrupt fl_chart's touch tracking).
  final ValueNotifier<HashratePoint?> _hover = ValueNotifier(null);
  // Throttle for the scrub-haptic. Mirrors the price card's 90ms cap so a
  // single drag doesn't fire dozens of selection ticks per second.
  int _lastHoverHapticMs = 0;

  // Last (range, snapshot) pair we actually rendered the row against. When
  // the user picks a new pill the new range's snapshot is null until the
  // fetch lands; rather than blank the whole card we keep displaying these
  // until a real snapshot for the active range arrives. Updated in build()
  // each time a fresh snapshot is available.
  HashrateRange? _displayedRowRange;
  HashrateSnapshot? _displayedRowSnapshot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final controller = context.read<HashrateController>()..addSubscriber();
    _controller = controller;
    _chartRange = context.read<AppStateNotifier>().hashrateRange;
    // Tell the controller which range we'll display first; without this it
    // would fetch its own default (d3) on cold start, so the row's _chartRange
    // would never trigger a fetch and the spinner would spin forever.
    // Deferred to a microtask so the synchronous notifyListeners inside
    // setActiveRange doesn't fire during this widget's build phase
    // (didChangeDependencies runs as part of mount).
    scheduleMicrotask(() {
      if (!mounted) return;
      controller.setActiveRange(_chartRange);
    });
  }

  @override
  void dispose() {
    _hover.dispose();
    _controller?.removeSubscriber();
    super.dispose();
  }

  void _toggleExpanded() {
    AppHaptics.selection();
    setExpanded(!isExpanded);
    _hover.value = null;
    // After the first expansion the row keeps reading from _chartRange, so we
    // keep polling that range even when collapsed — its snapshot drives the
    // collapsed delta and we want it fresh.
    _controller?.setActiveRange(_chartRange);
  }

  void _onRangeChanged(HashrateRange range) {
    if (range == _chartRange) return;
    setState(() => _chartRange = range);
    _hover.value = null;
    _controller?.setActiveRange(range);
    context.read<AppStateNotifier>().setHashrateRange(range);
  }

  void _onChartHover(HashratePoint? point) {
    if (_hover.value?.timestampMs == point?.timestampMs) return;
    _hover.value = point;
    if (point == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastHoverHapticMs < 90) return;
    _lastHoverHapticMs = now;
    AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    // The row always tracks _chartRange — both collapsed and expanded — so
    // picking "All" persists visibly in the collapsed row instead of falling
    // back to a different default.
    final targetRowRange = _chartRange;
    final chartRange = _chartRange;
    // Selector dedupes rebuilds: the controller notifies on every fetch
    // start/finish across all ranges (incl. background polls of ranges this
    // widget doesn't display), but we only care about the values below.
    // Equality on _ViewModel filters out the rest, sparing the fl_chart
    // subtree from rebuilding on unrelated notifies.
    final vm = context.select<HashrateController, _ViewModel>(
      (c) => _ViewModel(
        targetRowSnapshot: c.snapshotFor(targetRowRange),
        targetRowFailed: c.didFail(targetRowRange),
        chartSnapshot: c.snapshotFor(chartRange),
        chartLoading: c.isLoading(chartRange),
        chartFailed: c.didFail(chartRange),
      ),
    );

    // Cache the freshest snapshot we've seen for the row, so a range switch
    // doesn't blank the card while the new range fetches. The displayed
    // pair (range + snapshot) lags the target until new data lands.
    if (vm.targetRowSnapshot != null) {
      _displayedRowRange = targetRowRange;
      _displayedRowSnapshot = vm.targetRowSnapshot;
    }
    final rowSnapshot = _displayedRowSnapshot;
    final rowRange = _displayedRowRange ?? targetRowRange;

    // Error-out only when the *target* range has failed AND we have nothing
    // displayable at all (no fallback from a previously-loaded range).
    final fullyFailed = vm.targetRowFailed && rowSnapshot == null;

    final Widget body;
    if (fullyFailed) {
      body = _ErrorBody(
        onRetry: () =>
            context.read<HashrateController>().refetchRange(targetRowRange),
      );
    } else if (rowSnapshot == null) {
      // Cold start, no snapshot anywhere yet — show the slim skeleton.
      body = const _LoadingBody();
    } else {
      body = _Content(
        snapshot: rowSnapshot,
        rowRange: rowRange,
        expansionMounted: expansionMounted,
        expandAnimation: expandCurve,
        chartRange: chartRange,
        chartSnapshot: vm.chartSnapshot,
        chartLoading: vm.chartLoading,
        chartFailed: vm.chartFailed,
        hover: _hover,
        onChartHover: _onChartHover,
        onTapRow: _toggleExpanded,
        onRangeChanged: _onRangeChanged,
        onRetryChart: () =>
            context.read<HashrateController>().refetchRange(chartRange),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: body,
    );
  }
}

@immutable
class _ViewModel {
  const _ViewModel({
    required this.targetRowSnapshot,
    required this.targetRowFailed,
    required this.chartSnapshot,
    required this.chartLoading,
    required this.chartFailed,
  });

  final HashrateSnapshot? targetRowSnapshot;
  final bool targetRowFailed;
  final HashrateSnapshot? chartSnapshot;
  final bool chartLoading;
  final bool chartFailed;

  @override
  bool operator ==(Object other) =>
      other is _ViewModel &&
      identical(targetRowSnapshot, other.targetRowSnapshot) &&
      targetRowFailed == other.targetRowFailed &&
      identical(chartSnapshot, other.chartSnapshot) &&
      chartLoading == other.chartLoading &&
      chartFailed == other.chartFailed;

  @override
  int get hashCode => Object.hash(
        identityHashCode(targetRowSnapshot),
        targetRowFailed,
        identityHashCode(chartSnapshot),
        chartLoading,
        chartFailed,
      );
}

class _Content extends StatelessWidget {
  const _Content({
    required this.snapshot,
    required this.rowRange,
    required this.expansionMounted,
    required this.expandAnimation,
    required this.chartRange,
    required this.chartSnapshot,
    required this.chartLoading,
    required this.chartFailed,
    required this.hover,
    required this.onChartHover,
    required this.onTapRow,
    required this.onRangeChanged,
    required this.onRetryChart,
  });

  final HashrateSnapshot snapshot;
  final HashrateRange rowRange;
  // True for the entire duration of the expansion animation in either
  // direction — set immediately on expand, cleared only after the collapse
  // animation completes. Lets the chart subtree stay in the tree while the
  // SizeTransition shrinks, so the chart gets clipped instead of unmounted.
  final bool expansionMounted;
  // Curved animation driving the SizeTransition. value=0 → fully collapsed,
  // 1 → fully expanded. Owned by the parent state so the CurvedAnimation
  // (and its listener on the underlying controller) is allocated once, not
  // per rebuild.
  final Animation<double> expandAnimation;
  final HashrateRange chartRange;
  final HashrateSnapshot? chartSnapshot;
  final bool chartLoading;
  final bool chartFailed;
  final ValueNotifier<HashratePoint?> hover;
  final ValueChanged<HashratePoint?> onChartHover;
  final VoidCallback onTapRow;
  final ValueChanged<HashrateRange> onRangeChanged;
  final VoidCallback onRetryChart;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTapRow,
            child: ValueListenableBuilder<HashratePoint?>(
              valueListenable: hover,
              builder: (context, hovered, _) => _Row(
                snapshot: snapshot,
                rowRange: rowRange,
                hovered: hovered,
                expandAnimation: expandAnimation,
              ),
            ),
          ),
          // Render the expandable subtree throughout the open and close
          // animations. SizeTransition animates this section's height
          // between 0 and its intrinsic size (row + chart + pills), clipping
          // the chart smoothly as the parent shrinks.
          if (expansionMounted)
            SizeTransition(
              sizeFactor: expandAnimation,
              axisAlignment: -1, // anchor to top → chart slides up out of view
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 120,
                    child: _ChartArea(
                      range: chartRange,
                      snapshot: chartSnapshot,
                      loading: chartLoading,
                      failed: chartFailed,
                      onHover: onChartHover,
                      onRetry: onRetryChart,
                    ),
                  ),
                  HashrateRangeBar(
                    range: chartRange,
                    onRange: onRangeChanged,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.snapshot,
    required this.rowRange,
    required this.hovered,
    required this.expandAnimation,
  });

  final HashrateSnapshot snapshot;
  final HashrateRange rowRange;
  // When non-null the user is scrubbing the chart: the EH/s value on line 1
  // tracks the hovered point and line 2 shows the hovered timestamp. The
  // parenthetical delta is a label for the whole window and stays put — it
  // would be misleading to recompute it against an arbitrary midpoint.
  final HashratePoint? hovered;
  // Curved animation that drives the second-line reveal underneath the EH/s
  // value. Cached on the parent state so the curve isn't re-allocated per
  // rebuild. Grows the subtitle row in sync with the chart expanding below,
  // so collapsed rows show only the value line.
  final Animation<double> expandAnimation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final l10n = AppLocalizations.of(context);

    final displayEhs = hovered?.hashrateEHs ?? snapshot.currentHashrateEHs;
    final delta = snapshot.deltaPercent;
    final hoverLabel = hovered != null
        ? _formatHoverLabel(hovered!.timestampMs, rowRange)
        : null;

    final valueStyle = AppTypography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: cs.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${_formatEhs(displayEhs)} ${l10n.hashrateUnit}',
                style: valueStyle,
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    if (delta != null) ...[
                      TextSpan(
                        text: _formatSignedPct(delta),
                        style: TextStyle(
                          color: delta >= 0 ? p.priceUp : p.priceDown,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const TextSpan(text: ' '),
                    ],
                    TextSpan(text: _rangeSuffix(context, rowRange)),
                  ],
                ),
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: cs.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          SizeTransition(
            sizeFactor: expandAnimation,
            axisAlignment: -1,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              // Empty string when not scrubbing keeps the column height stable
              // — same pattern the price chart's subtitle uses.
              child: Text(
                hoverLabel ?? '',
                style: AppTypography.body.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartArea extends StatelessWidget {
  const _ChartArea({
    required this.range,
    required this.snapshot,
    required this.loading,
    required this.failed,
    required this.onHover,
    required this.onRetry,
  });

  final HashrateRange range;
  final HashrateSnapshot? snapshot;
  final bool loading;
  final bool failed;
  final ValueChanged<HashratePoint?> onHover;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;

    final points = snapshot?.points ?? const <HashratePoint>[];
    final hasData = points.length >= 2;

    if (!hasData && loading) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: p.bitcoinOrange,
          ),
        ),
      );
    }
    if (!hasData && failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).hashrateError,
              style: AppTypography.body.copyWith(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ChartRetryButton(onTap: onRetry),
          ],
        ),
      );
    }
    if (!hasData) {
      return const SizedBox.shrink();
    }

    final delta = snapshot!.deltaPercent ?? 0;
    final color = delta >= 0 ? p.priceUp : p.priceDown;
    final pricePoints = _pricePointsFor(snapshot!);

    return AreaChart(
      key: ValueKey('hashrate-${range.name}'),
      data: pricePoints,
      windowStartMs: pricePoints.first.t,
      windowEndMs: pricePoints.last.t,
      color: color,
      logScale: false,
      rangeKey: range,
      // fl_chart hands us back a PricePoint whose `t` is the original
      // timestampMs; the snapshot's lazy index makes this an O(1) lookup
      // even on the All range (~6K samples).
      onHover: (pp) =>
          onHover(pp == null ? null : snapshot!.byTimestamp[pp.t]),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    return Container(
      height: _hashrateCardHeight(context),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: p.bitcoinOrange,
        ),
      ),
    );
  }
}

// Card content is a single 16pt row inside 14px vertical padding. Measure the
// active line height under the system text scaler so the loading skeleton
// matches the populated card exactly.
double _hashrateCardHeight(BuildContext context) {
  const verticalPadding = 14.0;
  final scaler = MediaQuery.textScalerOf(context);
  final style = AppTypography.body.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );
  final painter = TextPainter(
    text: TextSpan(text: 'Ag', style: style),
    textDirection: ui.TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  return verticalPadding * 2 + painter.size.height;
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                AppLocalizations.of(context).hashrateError,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            ChartRetryButton(onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

// Memoizes the HashratePoint→PricePoint conversion per-snapshot. The chart
// rebuilds on every parent notify (every hover update, every poll tick); the
// All range carries ~6K samples so re-allocating that list each rebuild is
// wasteful. Snapshots are immutable and replaced on each fetch, so the Expando
// holds at most a handful of entries before old snapshots get GC'd.
final Expando<List<PricePoint>> _pricePointsCache = Expando('hashratePricePoints');

List<PricePoint> _pricePointsFor(HashrateSnapshot snapshot) {
  final cached = _pricePointsCache[snapshot];
  if (cached != null) return cached;
  final list = [
    for (final pt in snapshot.points) PricePoint(pt.timestampMs, pt.hashrateEHs),
  ];
  _pricePointsCache[snapshot] = list;
  return list;
}

// Network hashrate sits comfortably under 1000 EH/s for now (~977 in early
// 2026), so 1 decimal place reads cleanly. Above 1000 we drop decimals to
// keep the display compact — the threshold may eventually be crossed.
String _formatEhs(double v) {
  final locale = Intl.defaultLocale;
  final pattern = v >= 1000 ? '#,##0' : '#,##0.0';
  return NumberFormat(pattern, locale).format(v);
}

// Sign-prefixed percent. Small magnitudes get one decimal; once the number
// crosses 1,000% we switch to a compact suffix (K/M/B/T/Q) so very long
// windows — the All range reaches into the 10^15 % territory because
// hashrate was a fraction of 1 EH/s in 2009 — still fit on one line.
String _formatSignedPct(double pct) {
  final sign = pct < 0 ? '-' : '+';
  final abs = pct.abs();
  final locale = Intl.defaultLocale;
  if (abs < 1000) {
    return '$sign${NumberFormat('#,##0.0', locale).format(abs)}%';
  }
  const units = ['K', 'M', 'B', 'T', 'Q'];
  var scaled = abs / 1000;
  var idx = 0;
  while (scaled >= 1000 && idx < units.length - 1) {
    scaled /= 1000;
    idx++;
  }
  // Below 100 we keep one decimal ("+9.4K%"); at and above we drop it because
  // the suffix already conveys magnitude and the integer part is now ≥3 digits
  // ("+125K%", "+1,060T%"). Grouping separators apply once the scaled value
  // crosses 1,000 in the topmost unit (Q), e.g. very-large All-range values.
  final pattern = scaled >= 100 ? '#,##0' : '#,##0.0';
  final body = NumberFormat(pattern, locale).format(scaled);
  return '$sign$body${units[idx]}%';
}

// Mempool's hashrate API returns daily samples for every range except `3d`,
// which is sub-daily. So `d3` shows month-day plus time of day; longer ranges
// show a full date. Mirrors the price chart's hover-label rule.
String _formatHoverLabel(int ms, HashrateRange range) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  switch (range) {
    case HashrateRange.d3:
      return '${DateFormat.MMMd().format(d)}, ${DateFormat.Hm().format(d)}';
    case HashrateRange.m1:
    case HashrateRange.m6:
    case HashrateRange.y1:
    case HashrateRange.y5:
    case HashrateRange.y10:
    case HashrateRange.all:
      return DateFormat.yMMMd().format(d);
  }
}

// 3D doesn't have an l10n entry of its own (it's a hashrate-specific bucket
// that no other widget exposes), so it stays hard-coded. Every other label
// reuses the price-card pill strings so the row and the chart pills stay
// consistent — and translated — across locales.
String _rangeSuffix(BuildContext context, HashrateRange r) {
  final l10n = AppLocalizations.of(context);
  return switch (r) {
    HashrateRange.d3 => '3D',
    HashrateRange.m1 => l10n.rangePill1M,
    HashrateRange.m6 => l10n.rangePill6M,
    HashrateRange.y1 => l10n.rangePill1Y,
    HashrateRange.y5 => l10n.rangePill5Y,
    HashrateRange.y10 => l10n.rangePill10Y,
    HashrateRange.all => l10n.rangePillAll,
  };
}
