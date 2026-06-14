import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'stack_avatar.dart';

/// A single draggable row used in reorder lists. [overflow] defaults to
/// [TextOverflow.ellipsis]; pass [TextOverflow.visible] when the caller wants
/// the label to expand freely (the widget-reorder list).
class ReorderRow extends StatelessWidget {
  const ReorderRow({
    super.key,
    required this.index,
    required this.label,
    this.imageData,
    this.colorKey,
    this.overflow = TextOverflow.ellipsis,
  });

  final int index;
  final String label;
  final String? imageData;
  final String? colorKey;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            StackAvatar(
              name: label,
              imageData: imageData,
              colorKey: colorKey,
              size: 32,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
                overflow: overflow,
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Icon(
                  Icons.drag_handle,
                  size: 24,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drag proxy that lifts the row with a drop shadow while it's being dragged.
class ReorderRowDragProxy extends StatelessWidget {
  const ReorderRowDragProxy({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15 * animation.value),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
