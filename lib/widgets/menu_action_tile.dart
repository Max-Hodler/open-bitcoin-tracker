import 'package:flutter/material.dart';

import '../services/app_haptics.dart';
import '../theme/theme.dart';

class MenuActionTile extends StatelessWidget {
  const MenuActionTile({
    super.key,
    this.leading,
    required this.label,
    required this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final Widget? leading;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : cs.onSurface;
    final radius = BorderRadius.circular(AppSpacing.radius);
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(color: cs.surface, borderRadius: radius),
        child: InkWell(
          onTap: () {
            AppHaptics.selection();
            onTap();
          },
          borderRadius: radius,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                if (leading != null) ...[
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: IconTheme.merge(
                        data: IconThemeData(color: color, size: 22),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(color: color),
                          child: leading!,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.body.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  IconTheme.merge(
                    data: IconThemeData(color: color, size: 22),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: color),
                      child: trailing!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MenuSheetHeader extends StatelessWidget {
  const MenuSheetHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Opacity(
          opacity: 0.92,
          child: Text(
            label,
            style: AppTypography.label.copyWith(
              fontSize: 18,
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
