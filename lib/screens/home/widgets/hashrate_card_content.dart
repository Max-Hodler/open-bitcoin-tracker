import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/api.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/theme.dart';
import '../header/area_chart.dart';
import 'hashrate_range_bar.dart';
import 'retry_button.dart';

@immutable
class HashrateCardViewModel {
  const HashrateCardViewModel({
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
      other is HashrateCardViewModel &&
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

class HashrateCardContent extends StatelessWidget {
  const HashrateCardContent({
    super.key,
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
  final bool expansionMounted;
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
              builder: (context, hovered, _) => HashrateRow(
                snapshot: snapshot,
                rowRange: rowRange,
                hovered: hovered,
                expandAnimation: expandAnimation,
              ),
            ),
          ),
          if (expansionMounted)
            SizeTransition(
              sizeFactor: expandAnimation,
              axisAlignment: -1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 120,
                    child: HashrateChartArea(
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

class HashrateRow extends StatelessWidget {
  const HashrateRow({
    super.key,
    required this.snapshot,
    required this.rowRange,
    required this.hovered,
    required this.expandAnimation,
  });

  final HashrateSnapshot snapshot;
  final HashrateRange rowRange;
  final HashratePoint? hovered;
  final Animation<double> expandAnimation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final l10n = AppLocalizations.of(context);

    final displayEhs = hovered?.hashrateEHs ?? snapshot.currentHashrateEHs;
    final delta = snapshot.deltaPercent;
    final hoverLabel = hovered != null
        ? formatHashrateHoverLabel(hovered!.timestampMs, rowRange)
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
          Text(
            l10n.hashrateWidgetTitle,
            style: AppTypography.body.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${formatHashrateEhs(displayEhs)} ${l10n.hashrateUnit}',
                style: valueStyle,
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    if (delta != null) ...[
                      TextSpan(
                        text: formatHashrateSignedPct(delta),
                        style: TextStyle(
                          color: p.bitcoinOrange,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const TextSpan(text: ' '),
                    ],
                    TextSpan(text: hashrateRangeSuffix(context, rowRange)),
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

class HashrateChartArea extends StatelessWidget {
  const HashrateChartArea({
    super.key,
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

    final pricePoints = pricePointsForHashrate(snapshot!);

    return AreaChart(
      key: ValueKey('hashrate-${range.name}'),
      data: pricePoints,
      windowStartMs: pricePoints.first.t,
      windowEndMs: pricePoints.last.t,
      color: p.bitcoinOrange,
      logScale: false,
      rangeKey: range,
      onHover: (pp) =>
          onHover(pp == null ? null : snapshot!.byTimestamp[pp.t]),
    );
  }
}

class HashrateLoadingBody extends StatelessWidget {
  const HashrateLoadingBody({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    return Container(
      height: hashrateCardHeight(context),
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

double hashrateCardHeight(BuildContext context) {
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
  final lineHeight = painter.size.height;
  painter.dispose();
  return verticalPadding * 2 + lineHeight;
}

class HashrateErrorBody extends StatelessWidget {
  const HashrateErrorBody({super.key, required this.onRetry});

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

final Expando<List<PricePoint>> _pricePointsCache = Expando('hashratePricePoints');

List<PricePoint> pricePointsForHashrate(HashrateSnapshot snapshot) {
  final cached = _pricePointsCache[snapshot];
  if (cached != null) return cached;
  final list = [
    for (final pt in snapshot.points) PricePoint(pt.timestampMs, pt.hashrateEHs),
  ];
  _pricePointsCache[snapshot] = list;
  return list;
}

final Map<(String, String?), NumberFormat> _numberFormats = {};

NumberFormat _numberFormat(String pattern) {
  final locale = Intl.defaultLocale;
  return _numberFormats[(pattern, locale)] ??= NumberFormat(pattern, locale);
}

final Map<(String, String?), DateFormat> _dateFormats = {};

DateFormat _dateFormat(String skeleton, DateFormat Function() create) =>
    _dateFormats[(skeleton, Intl.defaultLocale)] ??= create();

String formatHashrateEhs(double v) {
  final pattern = v >= 1000 ? '#,##0' : '#,##0.0';
  return _numberFormat(pattern).format(v);
}

String formatHashrateSignedPct(double pct) {
  final sign = pct < 0 ? '-' : '+';
  final abs = pct.abs();
  if (abs < 1000) {
    return '$sign${_numberFormat('#,##0.0').format(abs)}%';
  }
  const units = ['K', 'M', 'B', 'T', 'Q'];
  var scaled = abs / 1000;
  var idx = 0;
  while (scaled >= 1000 && idx < units.length - 1) {
    scaled /= 1000;
    idx++;
  }
  final pattern = scaled >= 100 ? '#,##0' : '#,##0.0';
  final body = _numberFormat(pattern).format(scaled);
  return '$sign$body${units[idx]}%';
}

String formatHashrateHoverLabel(int ms, HashrateRange range) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  switch (range) {
    case HashrateRange.d3:
      return '${_dateFormat('MMMd', DateFormat.MMMd).format(d)}, '
          '${_dateFormat('Hm', DateFormat.Hm).format(d)}';
    case HashrateRange.m1:
    case HashrateRange.m6:
    case HashrateRange.y1:
    case HashrateRange.y5:
    case HashrateRange.y10:
    case HashrateRange.all:
      return _dateFormat('yMMMd', DateFormat.yMMMd).format(d);
  }
}

String hashrateRangeSuffix(BuildContext context, HashrateRange r) {
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
