import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/stack_card.dart' show StackCardPosition;

class LockedStacksSkeleton extends StatelessWidget {
  const LockedStacksSkeleton({
    super.key,
    required this.stackCount,
    this.showTotal = false,
    this.onTap,
  });

  final int stackCount;
  // When true, an extra ghost row is appended for the portfolio total card.
  final bool showTotal;
  // Tapping anywhere on the skeleton triggers the unlock flow, the same as
  // tapping the lock button.
  final VoidCallback? onTap;

  // Shows at least one row so there's always something visible.
  int get _rowCount => stackCount.clamp(1, 20) + (showTotal ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = _rowCount;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          _SkeletonRow(
            position: count == 1
                ? StackCardPosition.only
                : i == 0
                    ? StackCardPosition.first
                    : i == count - 1
                        ? StackCardPosition.last
                        : StackCardPosition.middle,
          ),
          if (i < count - 1)
            Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant,
            ),
        ],
      ],
    );
    if (onTap == null) return column;
    // Opaque so taps land on the row padding and the gaps between rows too.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: column,
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.position});

  final StackCardPosition position;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Higher-contrast than the page background so the placeholder bars read
    // clearly, without giving the row itself a background of its own.
    final shimmer = cs.onSurface.withValues(alpha: 0.16);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 20,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar placeholder.
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: shimmer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name bar.
                Container(
                  height: 14,
                  width: 90,
                  decoration: BoxDecoration(
                    color: shimmer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                // Amounts row: btc bar left, fiat bar right.
                Row(
                  children: [
                    Container(
                      height: 13,
                      width: 140,
                      decoration: BoxDecoration(
                        color: shimmer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 13,
                      width: 72,
                      decoration: BoxDecoration(
                        color: shimmer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
