import 'package:flutter/foundation.dart';

import '../../../../api/api.dart';
import '../../../../theme/theme.dart';
import 'block_visuals.dart';

/// Render-state for one slot in a slide. Each slot represents a block that
/// will animate from [initialIndex] to [targetIndex]. The slot's left edge
/// is interpolated from the slide controller's value.
///
/// For the crossing slot (rightmost-projected becoming first-mined),
/// [kindAtTarget] is mined — that's the styling the slot lands on at
/// fraction = 1 — but [block] carries the projected data the user sees
/// during the slide (no mined height yet), so content is rendered as
/// projected for the whole slide. [crossesDivider] keeps that projected
/// content rendering until the slide completes.
class BlockStripSlot {
  BlockStripSlot({
    required this.key,
    required this.block,
    required this.initialIndex,
    required this.targetIndex,
    required this.kindAtTarget,
    required this.crossesDivider,
  });

  final ValueKey<String> key;
  final MempoolBlock block;
  final int initialIndex;
  final int targetIndex;
  final BlockKind kindAtTarget;
  final bool crossesDivider;
}

/// Pure: scroll offset that puts the divider at the horizontal center of the
/// viewport. Lifted out of [_BlockStripState] so the math is independently
/// readable and testable.
///
/// The divider sits between the rightmost-projected block and the first mined
/// block. Its left-edge position inside the scroll content is:
///   projectedShown * (boxSize + AppSpacing.sm) - AppSpacing.sm / 2
/// We then offset by kMempoolStripPadding (the scrollable's leading padding)
/// and target the divider's center (left + kMempoolDividerWidth / 2) at
/// viewportWidth / 2.
double calculateDividerCenterScrollOffset({
  required int projectedShown,
  required double viewportWidth,
  required double boxSize,
}) {
  final dividerLeft =
      projectedShown * (boxSize + AppSpacing.sm) - AppSpacing.sm / 2;
  return kMempoolStripPadding +
      dividerLeft +
      kMempoolDividerWidth / 2 -
      viewportWidth / 2;
}
