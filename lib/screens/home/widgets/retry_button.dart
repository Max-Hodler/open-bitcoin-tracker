import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../theme/theme.dart';

class ChartRetryButton extends StatelessWidget {
  const ChartRetryButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: p.bitcoinOrange,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 18, color: cs.onPrimary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                AppLocalizations.of(context).chartErrorRetry,
                style: AppTypography.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
