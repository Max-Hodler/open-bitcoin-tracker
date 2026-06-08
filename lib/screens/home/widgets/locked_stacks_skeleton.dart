import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/stack_card.dart' show StackCardPosition;

class LockedStacksSkeleton extends StatelessWidget {
  const LockedStacksSkeleton({
    super.key,
    required this.stackCount,
  });

  final int stackCount;

  // Shows at least one row so there's always something visible.
  int get _rowCount => stackCount.clamp(1, 20);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = _rowCount;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
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
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.position});

  final StackCardPosition position;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shimmer = cs.onSurface.withValues(alpha: 0.08);
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
                // Amount bar.
                Container(
                  height: 13,
                  width: 140,
                  decoration: BoxDecoration(
                    color: shimmer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
