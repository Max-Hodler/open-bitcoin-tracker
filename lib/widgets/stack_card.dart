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
    required this.btcDisplayMode,
    this.isHidden = false,
    this.imageData,
    this.colorKey,
    this.onTap,
    this.onLongPress,
    this.onAvatarTap,
    this.position = StackCardPosition.only,
  });

  final String name;
  final int sats;
  final Currency currency;
  final double? btcRate;
  final BtcDisplayMode btcDisplayMode;
  final bool isHidden;
  final String? imageData;
  final String? colorKey;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onAvatarTap;
  final StackCardPosition position;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
                    _AmountsRow(
                      sats: sats,
                      currency: currency,
                      btcRate: btcRate,
                      btcDisplayMode: btcDisplayMode,
                      isHidden: isHidden,
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

class _AmountsRow extends StatelessWidget {
  const _AmountsRow({
    required this.sats,
    required this.currency,
    required this.btcRate,
    required this.btcDisplayMode,
    required this.isHidden,
  });

  final int sats;
  final Currency currency;
  final double? btcRate;
  final BtcDisplayMode btcDisplayMode;
  final bool isHidden;

  static const _gap = AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amountStyle = AppTypography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.3,
      color: cs.onSurface.withValues(alpha: 0.85),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final btc = Text(btcStr, maxLines: 1, style: amountStyle);
    final fiat = Text(fiatStr, maxLines: 1, style: amountStyle);

    // A LayoutBuilder would give us the exact slot width, but StackCard renders
    // inside intrinsic-sizing ancestors (the swipe row) that probe it for
    // intrinsic height, which LayoutBuilder forbids. So measure against the
    // text column's width derived from the screen instead.
    final scaler = MediaQuery.textScalerOf(context);
    final fitsOnOneLine = _width(btcStr, amountStyle, scaler) +
            _gap +
            _width(fiatStr, amountStyle, scaler) <=
        _columnWidth(context);

    // Side by side with the fiat value right-aligned while both fit; once a
    // large system font makes them overflow, stack them so each can grow.
    if (fitsOnOneLine) {
      return Row(
        children: [
          Expanded(child: btc),
          const SizedBox(width: _gap),
          fiat,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [btc, fiat],
    );
  }

  // Width of the text column to the right of the avatar: screen width minus the
  // card's horizontal padding (md per side), the avatar, and the avatar→text
  // gap (md). Mirrors the layout in StackCard.build.
  double _columnWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width -
      AppSpacing.md * 3 -
      StackAvatar.defaultSize;

  String get btcStr =>
      formatBtcAmount(sats, hidden: isHidden, mode: btcDisplayMode);

  String get fiatStr {
    if (isHidden) {
      final symbol = currencySymbols[currency] ?? r'$';
      return symbolAfterAmount ? '**** $symbol' : '$symbol ****';
    }
    final value = Sats.toFiat(sats, btcRate ?? 0);
    return formatFiat(value, currency, decimalsUnder10: true).full;
  }

  static double _width(String text, TextStyle style, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final width = tp.width;
    tp.dispose();
    return width;
  }
}

