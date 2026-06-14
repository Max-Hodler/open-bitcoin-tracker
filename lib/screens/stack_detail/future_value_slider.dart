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
/// The track is log-scaled between [minPrice] and [maxPrice] so the cheap end
/// (just above today's price) gets as much travel as the expensive end, rather
/// than being crushed into the first few pixels.
class FutureValueSlider extends StatefulWidget {
  const FutureValueSlider({
    super.key,
    required this.btcAmount,
    required this.currency,
    required this.minPrice,
    required this.maxPrice,
    required this.initialPrice,
    this.onPriceSelected,
  });

  /// The stack's size in BTC (sats / 1e8). Projected value is price * this.
  final double btcAmount;
  final Currency currency;

  /// Track bounds, in the active currency. [minPrice] is typically today's
  /// price (you can't go below where we already are); [maxPrice] is the dream.
  final double minPrice;
  final double maxPrice;

  /// Where the thumb starts — usually the next round number above today.
  final double initialPrice;

  /// Fired once when the user finishes a drag, with the BTC price the thumb
  /// landed on. Used to persist the projection so it's restored on revisit.
  final ValueChanged<double>? onPriceSelected;

  @override
  State<FutureValueSlider> createState() => _FutureValueSliderState();
}

class _FutureValueSliderState extends State<FutureValueSlider> {
  // Position along the track in [0, 1]; mapped to a price via the log curve.
  late double _t;
  int _lastHapticStep = -1;

  @override
  void initState() {
    super.initState();
    _t = _priceToT(widget.initialPrice);
  }

  @override
  void didUpdateWidget(covariant FutureValueSlider old) {
    super.didUpdateWidget(old);
    // Currency switch / amount edit rescales the bounds; keep the thumb where it
    // is proportionally rather than snapping it.
    if (old.minPrice != widget.minPrice || old.maxPrice != widget.maxPrice) {
      _t = _t.clamp(0.0, 1.0);
    }
  }

  double get _logMin => math.log(math.max(widget.minPrice, 1));
  double get _logMax => math.log(math.max(widget.maxPrice, widget.minPrice + 1));

  double _priceToT(double price) {
    final p = price.clamp(widget.minPrice, widget.maxPrice);
    return ((math.log(p) - _logMin) / (_logMax - _logMin)).clamp(0.0, 1.0);
  }

  double get _price => math.exp(_logMin + _t * (_logMax - _logMin));

  void _setT(double t) {
    final clamped = t.clamp(0.0, 1.0);
    if (clamped == _t) return;
    setState(() => _t = clamped);
    // A light tick every ~10% of travel so the drag has texture without
    // buzzing continuously.
    final step = (_t * 10).round();
    if (step != _lastHapticStep) {
      _lastHapticStep = step;
      AppHaptics.selection();
    }
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
            value: _t,
            onChanged: _setT,
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

