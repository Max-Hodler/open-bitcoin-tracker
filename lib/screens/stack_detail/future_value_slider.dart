import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/app_enums.dart';
import '../../data/fiat.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../theme/theme.dart';

/// Per-currency stop ladders. Each list contains round BTC prices in the
/// named currency. Steps are chosen so:
///  - The finest step feels natural in that currency (100k for major Western
///    currencies, 10M for JPY which is ~150× the USD face value).
///  - The ceiling is roughly 10–15× today's BTC price, giving room to dream.
///  - CAD and AUD ceilings are 15M (BTC trades ~40% higher there than in USD).
const Map<Currency, List<double>> _ladders = {
  Currency.usd: [
    100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000,
    1000000, 2000000, 3000000, 4000000, 5000000, 6000000, 7000000, 8000000,
    9000000, 10000000,
  ],
  Currency.eur: [
    100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000,
    1000000, 2000000, 3000000, 4000000, 5000000, 6000000, 7000000, 8000000,
    9000000, 10000000,
  ],
  Currency.gbp: [
    100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000,
    1000000, 2000000, 3000000, 4000000, 5000000, 6000000, 7000000, 8000000,
    9000000, 10000000,
  ],
  Currency.chf: [
    100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000,
    1000000, 2000000, 3000000, 4000000, 5000000, 6000000, 7000000, 8000000,
    9000000, 10000000,
  ],
  Currency.cad: [
    100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000,
    1000000, 2000000, 3000000, 4000000, 5000000, 6000000, 7000000, 8000000,
    9000000, 10000000, 11000000, 12000000, 13000000, 14000000, 15000000,
  ],
  Currency.aud: [
    100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000,
    1000000, 2000000, 3000000, 4000000, 5000000, 6000000, 7000000, 8000000,
    9000000, 10000000, 11000000, 12000000, 13000000, 14000000, 15000000,
  ],
  Currency.jpy: [
    10000000, 20000000, 30000000, 40000000, 50000000, 60000000, 70000000,
    80000000, 90000000,
    100000000, 200000000, 300000000, 400000000, 500000000, 600000000,
    700000000, 800000000, 900000000, 1000000000, 1100000000, 1200000000,
    1300000000, 1400000000, 1500000000,
  ],
};

/// "If Bitcoin reaches X, this stack is worth Y" — a draggable BTC-price slider
/// that projects the stack's value live as the user drags.
///
/// The thumb snaps through a per-currency ladder of round prices so every stop
/// feels like a number a person would actually name in that currency.
class FutureValueSlider extends StatefulWidget {
  const FutureValueSlider({
    super.key,
    required this.btcAmount,
    required this.currency,
    required this.initialPrice,
    this.onPriceSelected,
  });

  /// The stack's size in BTC (sats / 1e8). Projected value is price * this.
  final double btcAmount;
  final Currency currency;

  /// Where the thumb starts. Snapped to the nearest ladder stop.
  /// Pass null to center the thumb (default when no saved projection exists).
  final double? initialPrice;

  /// Fired once when the user finishes a drag, with the BTC price the thumb
  /// landed on. Used to persist the projection so it's restored on revisit.
  final ValueChanged<double>? onPriceSelected;

  @override
  State<FutureValueSlider> createState() => _FutureValueSliderState();
}

class _FutureValueSliderState extends State<FutureValueSlider> {
  List<double> get _stops => _ladders[widget.currency] ?? _ladders[Currency.usd]!;

  late int _index;

  @override
  void initState() {
    super.initState();
    _index = _initialIndex();
  }

  @override
  void didUpdateWidget(FutureValueSlider old) {
    super.didUpdateWidget(old);
    if (old.currency != widget.currency || old.initialPrice != widget.initialPrice) {
      _index = _initialIndex();
    }
  }

  int _initialIndex() {
    final price = widget.initialPrice;
    if (price == null) return _stops.length ~/ 2;
    return _nearestStop(price);
  }

  int _nearestStop(double price) {
    final stops = _stops;
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < stops.length; i++) {
      final d = (stops[i] - price).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  double get _price => _stops[_index];

  void _setIndex(double raw) {
    final i = raw.round().clamp(0, _stops.length - 1);
    if (i == _index) return;
    setState(() => _index = i);
    AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    final stops = _stops;
    final price = _price;
    final value = price * widget.btcAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                l10n.stackDetailWhenBtcReaches,
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              formatFiat(price, widget.currency, decimalsUnder10: false).full,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: p.bitcoinOrange,
            inactiveTrackColor: cs.outlineVariant,
            thumbColor: p.bitcoinOrange,
            overlayColor: p.bitcoinOrange.withValues(alpha: 0.12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Slider(
            value: _index.toDouble(),
            min: 0,
            max: (stops.length - 1).toDouble(),
            divisions: math.max(stops.length - 1, 1),
            onChanged: _setIndex,
            onChangeEnd: (_) => widget.onPriceSelected?.call(_price),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            l10n.stackDetailWillBeWorth,
            style: AppTypography.body.copyWith(
              fontSize: 16,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: Text(
            formatFiat(value, widget.currency, decimalsUnder10: false).tight,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.title.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: cs.onSurface,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
