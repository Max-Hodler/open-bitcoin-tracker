import 'package:flutter/material.dart';

import '../../../api/api.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../theme/theme.dart';

// Pills shown in the hashrate widget's expanded view, in display order. Mirrors
// the slimmest meaningful subset of the price card's pill row but without the
// overflow slot — the API only exposes a fixed set of period buckets and we
// don't need a customizable "favorite year" the way the price card does.
const List<HashrateRange> _pills = [
  HashrateRange.d3,
  HashrateRange.m1,
  HashrateRange.m6,
  HashrateRange.y1,
  HashrateRange.y5,
  HashrateRange.y10,
  HashrateRange.all,
];

/// Slim pill row for the hashrate widget. Shares the visual language of the
/// price card's `RangeBar` — same font, weight bump on selection, 1px
/// underline, label-width floor so selecting a chip doesn't shift its
/// neighbors — but skips the overflow-slot machinery and the floating "+%"
/// label (the hashrate row above the chart already shows that delta).
class HashrateRangeBar extends StatelessWidget {
  const HashrateRangeBar({
    super.key,
    required this.range,
    required this.onRange,
  });

  final HashrateRange range;
  final ValueChanged<HashrateRange> onRange;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final boldStyle = AppTypography.body.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    return SizedBox(
      height: _chipHeight(textScaler),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPadding = AppSpacing.md;
          final innerMinWidth = constraints.maxWidth - horizontalPadding * 2;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: innerMinWidth),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final r in _pills)
                    _Pill(
                      label: _label(context, r),
                      selected: r == range,
                      minLabelWidth: _measureLabel(
                        context: context,
                        label: _label(context, r),
                        style: boldStyle,
                        textScaler: textScaler,
                      ),
                      onTap: () => onRange(r),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.minLabelWidth,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double minLabelWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.light();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.center,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: minLabelWidth + 1,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : null,
                    color: selected ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Container(
                height: 1,
                color: selected ? cs.onSurfaceVariant : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double _chipHeight(TextScaler textScaler) {
  // Sized to fit a 14pt label at 1.4 line height, floored at 24px (so the
  // chip stays touch-friendly at small system text), plus 16 vertical padding
  // + 3 spacer + 1px underline + 4px slack so sub-pixel rounding doesn't
  // overflow the column at large text scales.
  final labelRow = textScaler.scale(14) * 1.4;
  final base = labelRow < 24 ? 24.0 : labelRow;
  return base + 16 + 3 + 1 + 4;
}

double _measureLabel({
  required BuildContext context,
  required String label,
  required TextStyle style,
  required TextScaler textScaler,
}) {
  final tp = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    textScaler: textScaler,
  )..layout();
  final w = tp.size.width;
  tp.dispose();
  return w;
}

String _label(BuildContext context, HashrateRange r) {
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
