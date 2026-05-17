import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/app_enums.dart';
import '../../../format/fiat.dart';
import '../../../services/app_haptics.dart';
import '../../../theme/theme.dart';
import '../header/area_chart.dart';

class RangePillsRow extends StatefulWidget {
  const RangePillsRow({
    super.key,
    required this.card,
    required this.rangePillData,
    required this.priceScale,
    required this.currency,
  });

  final Widget card;
  final List<PricePoint> rangePillData;
  final double priceScale;
  final Currency currency;

  @override
  State<RangePillsRow> createState() => _RangePillsRowState();
}

// Minimum width of a range pill. Also used to compute the scroll-haptic stride
// (pill width + gap) — these must stay in sync, so it lives at file scope.
const double _kRangePillMinWidth = 112;

class _RangePillsRowState extends State<RangePillsRow> {
  final _scrollController = ScrollController();
  // Stride used to estimate when a range pill edge crosses the screen edge:
  // pill minWidth + AppSpacing.xs gap. Haptic fires each time the scroll offset
  // crosses an integer multiple of this.
  static const double _rangePillStride = _kRangePillMinWidth + AppSpacing.xs;
  int _lastHapticRangePillCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if (offset <= 0) {
      _lastHapticRangePillCount = 0;
      return;
    }
    final count = (offset / _rangePillStride).floor();
    if (count != _lastHapticRangePillCount) {
      _lastHapticRangePillCount = count;
      AppHaptics.selection();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rangePills = _StackRangePills(
      data: widget.rangePillData,
      priceScale: widget.priceScale,
      currency: widget.currency,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        const hPad = AppSpacing.md;
        final cardWidth = (fullWidth - hPad * 2).clamp(0.0, double.infinity);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          controller: _scrollController,
          reverse: true,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                rangePills,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: hPad),
                  child: SizedBox(width: cardWidth, child: widget.card),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StackRangePills extends StatelessWidget {
  const _StackRangePills({
    required this.data,
    required this.priceScale,
    required this.currency,
  });

  final List<PricePoint> data;
  final double priceScale;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return const SizedBox.shrink();
    final now = DateTime.now();
    final firstT = DateTime.fromMillisecondsSinceEpoch(data.first.t);
    final maxYearsBack = now.year - firstT.year -
        (_isBefore(now.month, now.day, firstT.month, firstT.day) ? 1 : 0);
    final dateFormat = DateFormat(
      "d MMM ''yy",
      Localizations.localeOf(context).toString(),
    );
    final offsets = [
      for (int y = maxYearsBack; y >= 1; y--)
        () {
          final at = DateTime(now.year - y, now.month, now.day,
              now.hour, now.minute, now.second, now.millisecond);
          return (label: dateFormat.format(at), atMs: at.millisecondsSinceEpoch);
        }(),
    ];
    if (offsets.isEmpty) return const SizedBox.shrink();
    final items = [
      for (final o in offsets)
        _RangePillData(label: o.label, pastPrice: _priceAt(o.atMs)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(width: AppSpacing.md),
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          _RangePill(item: items[i], currency: currency),
        ],
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  double? _priceAt(int targetMs) {
    if (data.isEmpty || targetMs <= data.first.t) return null;
    int lo = 0, hi = data.length - 1, best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (data[mid].t <= targetMs) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best >= 0 ? data[best].price * priceScale : null;
  }

  static bool _isBefore(int aMonth, int aDay, int bMonth, int bDay) =>
      aMonth < bMonth || (aMonth == bMonth && aDay < bDay);
}

class _RangePillData {
  const _RangePillData({required this.label, required this.pastPrice});

  final String label;
  final double? pastPrice;
}

class _RangePill extends StatelessWidget {
  const _RangePill({required this.item, required this.currency});

  final _RangePillData item;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final pastPrice = item.pastPrice;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _kRangePillMinWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.palette.recessedSurface ?? cs.surfaceContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                pastPrice == null
                    ? '—'
                    : formatFiat(pastPrice, currency, decimalsUnder10: true).full,
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.3,
                  color: pastPrice == null
                      ? cs.onSurfaceVariant
                      : cs.onSurface.withValues(alpha: 0.85),
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
