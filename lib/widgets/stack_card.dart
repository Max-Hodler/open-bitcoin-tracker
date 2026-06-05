import 'package:flutter/material.dart';

import '../data/app_enums.dart';
import '../data/sats.dart';
import '../data/fiat.dart';
import '../theme/theme.dart';
import 'stack_avatar.dart';

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
    this.imageData,
    this.colorKey,
    this.onTap,
    this.onAvatarTap,
    this.position = StackCardPosition.only,
  });

  final String name;
  final int sats;
  final Currency currency;
  final double? btcRate;
  final BtcDisplayMode bitcoinDisplayMode;
  final bool isHidden;
  final String? imageData;
  final String? colorKey;
  final VoidCallback? onTap;
  final VoidCallback? onAvatarTap;
  final StackCardPosition position;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 20,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Opaque hit-test stops the tap bubbling up to the surrounding
              // InkWell, so the avatar opens the picker sheet while the rest
              // of the card still opens the stack menu.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAvatarTap,
                child: StackAvatar(
                  name: name,
                  imageData: imageData,
                  colorKey: colorKey,
                  onTap: onAvatarTap,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
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
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // BTC keeps its Expanded share so the fiat value stays
                        // pinned to the right. When the figure is too large to
                        // fit that share, the FittedBox scales it down rather
                        // than truncating with an ellipsis. centerLeft keeps it
                        // left-aligned within its slot.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                formatBtcAmount(
                                  sats,
                                  hidden: isHidden,
                                  mode: bitcoinDisplayMode,
                                ),
                                maxLines: 1,
                                style: AppTypography.body.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: -0.3,
                                  color: cs.onSurface.withValues(alpha: 0.85),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
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
            ],
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
