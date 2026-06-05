import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../theme/theme.dart';

/// A one-time teaching hint shown below the stack list: an info-styled card
/// with [message] and a "Got it" button. [onDismiss] persists the dismissal so
/// the hint never returns. Shared by the swipe-to-reveal and tap-to-add hints
/// so they stay visually identical.
class HomeHintCard extends StatelessWidget {
  const HomeHintCard({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.body.copyWith(
                      fontSize: 14,
                      height: 1.35,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  AppHaptics.light();
                  onDismiss();
                },
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.bitcoinOrange,
                  textStyle: AppTypography.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(l10n.homeChangePillsHintDismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
