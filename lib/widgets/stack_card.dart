import 'package:flutter/material.dart';

import '../data/app_enums.dart';
import '../data/sats.dart';
import '../format/fiat.dart';
import '../theme/theme.dart';

/// Where this card sits in a vertical group, used to decide which corners
/// to round so a series of cards reads as one grouped surface with hairline
/// dividers between rows.
enum StackCardPosition { only, first, middle, last }

class StackCard extends StatelessWidget {
  const StackCard({
    super.key,
    required this.name,
    required this.sats,
    required this.currency,
    required this.btcRate,
    required this.bitcoinDisplayMode,
    this.isHidden = false,
    this.onTap,
    this.position = StackCardPosition.only,
  });

  final String name;
  final int sats;
  final Currency currency;
  final double? btcRate;
  final BtcDisplayMode bitcoinDisplayMode;
  final bool isHidden;
  final VoidCallback? onTap;
  final StackCardPosition position;

  @override
  Widget build(BuildContext context) {
    const horizontalPadding = 20.0;
    final cs = Theme.of(context).colorScheme;
    final r = const Radius.circular(AppSpacing.radiusLarge);
    final BorderRadius borderRadius;
    switch (position) {
      case StackCardPosition.only:
        borderRadius = BorderRadius.all(r);
      case StackCardPosition.first:
        borderRadius = BorderRadius.only(topLeft: r, topRight: r);
      case StackCardPosition.last:
        borderRadius = BorderRadius.only(bottomLeft: r, bottomRight: r);
      case StackCardPosition.middle:
        borderRadius = BorderRadius.zero;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    fontSize: 16,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatBtcAmount(
                          sats,
                          hidden: isHidden,
                          mode: bitcoinDisplayMode,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.3,
                          color: cs.onSurface.withValues(alpha: 0.85),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _FiatValue(
                      sats: sats,
                      currency: currency,
                      btcRate: btcRate,
                      isHidden: isHidden,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FiatValue extends StatelessWidget {
  const _FiatValue({
    required this.sats,
    required this.currency,
    required this.btcRate,
    required this.isHidden,
  });

  final int sats;
  final Currency currency;
  final double? btcRate;
  final bool isHidden;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final symbol = currencySymbols[currency] ?? r'$';
    final style = AppTypography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.3,
      color: cs.onSurface.withValues(alpha: 0.85),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (isHidden) {
      final hidden = symbolAfterAmount ? '**** $symbol' : '$symbol ****';
      return Text(hidden, style: style);
    }
    final rate = btcRate ?? 0;
    final value = Sats.toFiat(sats, rate);
    final formatted = formatFiat(value, currency, decimalsUnder10: true);
    return Text(formatted.full, style: style);
  }
}
