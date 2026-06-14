import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/app_enums.dart';
import '../../data/fiat.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../theme/theme.dart';

/// "If Bitcoin reaches X, this stack is worth Y" — a draggable BTC-price slider
/// that projects the stack's value live as the user drags. Replaces the old
/// fixed ladder of milestone pills: one control instead of nineteen rows.
///
/// The thumb snaps through a fixed ladder of *round* prices — 100k, 200k … 1M
/// in 100k steps, then 1M, 2M … 10M in 1M steps — so every stop is a number a
/// person would actually pick (100k, 300k) instead of an arbitrary $137,492.
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

  /// Where the thumb starts — 100k by default, or a restored saved projection.
  /// Snapped to the nearest ladder stop.
  final double initialPrice;

  /// Fired once when the user finishes a drag, with the BTC price the thumb
  /// landed on. Used to persist the projection so it's restored on revisit.
  final ValueChanged<double>? onPriceSelected;

  @override
  State<FutureValueSlider> createState() => _FutureValueSliderState();
}

class _FutureValueSliderState extends State<FutureValueSlider> {
  /// Fixed ladder of round prices the thumb snaps through: 100k, 200k … 1M in
  /// 100k steps, then 1M, 2M … 10M in 1M steps. Deliberately independent of
  /// today's price — the projection always starts at 100k and runs to 10M.
  static final List<double> _stops = [
    for (var p = 100000.0; p < 1000000.0; p += 100000.0) p,
    for (var p = 1000000.0; p <= 10000000.0; p += 1000000.0) p,
  ];

  late int _index;

  @override
  void initState() {
    super.initState();
    _index = _nearestStop(widget.initialPrice);
  }

  int _nearestStop(double price) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < _stops.length; i++) {
      final d = (_stops[i] - price).abs();
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
    // One tick per stop crossed — the snapping itself gives the drag texture.
    AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final p = context.palette;
    final price = _price;
    final value = price * widget.btcAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.stackDetailWhenBtcReaches,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              formatFiat(price, widget.currency, decimalsUnder10: false).full,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
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
            max: (_stops.length - 1).toDouble(),
            divisions: math.max(_stops.length - 1, 1),
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
            formatFiat(value, widget.currency, decimalsUnder10: false).full,
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

