import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../theme/theme.dart';

class HomeButton extends StatelessWidget {
  const HomeButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.height = 52,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: InkWell(
          onTap: onTap == null ? null : () {
            AppHaptics.light();
            onTap!();
          },
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                icon,
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    style: AppTypography.body.copyWith(
                      fontSize: 16,
                      color: cs.onSurface.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddStackButton extends StatelessWidget {
  const AddStackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HomeButton(
      icon: Icon(Icons.add, size: 22, color: cs.onSurface.withValues(alpha: 0.85)),
      label: AppLocalizations.of(context).homeAddAStack,
      onTap: onTap,
    );
  }
}


class ConverterIconButton extends StatelessWidget {
  const ConverterIconButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 47,
          child: Transform.flip(
            flipX: true,
            child: Icon(
              Icons.swap_vert,
              size: 26,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class OverflowButton extends StatelessWidget {
  const OverflowButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 47,
          child: Icon(
            Icons.more_horiz,
            size: 24,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class LockNowButton extends StatelessWidget {
  const LockNowButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 47,
          padding: const EdgeInsets.only(left: 3),
          child: Icon(
            Icons.lock_outline,
            size: 22,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
