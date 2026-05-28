import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import 'mempool/block_strip.dart';
import 'mempool/block_visuals.dart';
import 'retry_button.dart';

/// Network mempool card on the home screen. Subscribes to [MempoolController]
/// for snapshots and switches between three bodies based on fetch state:
/// loading skeleton, error retry, or [BlockStrip] when data is available.
class MempoolCard extends StatefulWidget {
  const MempoolCard({super.key});

  @override
  State<MempoolCard> createState() => _MempoolCardState();
}

class _MempoolCardState extends State<MempoolCard> {
  // Subscribe lazily in didChangeDependencies — initState can't context.read
  // safely. Cache the controller so dispose() doesn't need a context lookup,
  // which would assert "looking up a deactivated widget's ancestor is unsafe".
  MempoolController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = context.read<MempoolController>()..addSubscriber();
  }

  @override
  void dispose() {
    _controller?.removeSubscriber();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MempoolController>();
    final snapshot = controller.snapshot;
    final fullyFailed = controller.failed && snapshot == null;

    // Match StackCard's rendered height so the mempool blocks read as the
    // same visual unit. Square aspect, so width == height. Recomputed per
    // build to track text-scale changes.
    final boxSize = _blockBoxHeight(context);
    if (fullyFailed) return _ErrorBody(boxSize: boxSize);
    if (snapshot == null) {
      final reversed = context.select<AppStateNotifier, bool>(
        (a) => a.mempoolBlocksReversed,
      );
      final body = _LoadingBody(boxSize: boxSize, reversed: reversed);
      return reversed ? Transform.flip(flipX: true, child: body) : body;
    }
    return BlockStrip(snapshot: snapshot, boxSize: boxSize);
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.boxSize, this.reversed = false});

  final double boxSize;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    // Mirror the loaded strip's layout so nothing visually shifts when data
    // arrives: 2 projected slots, divider, 4 mined slots, link block — all
    // inside the same horizontal padding as the populated strip.
    const projectedShown = 2;
    const minedShown = 4;
    Widget counter(Widget child) =>
        reversed ? Transform.flip(flipX: true, child: child) : child;
    return SizedBox(
      height: boxSize,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: kMempoolStripPadding),
        child: Row(
          children: [
            for (var i = 0; i < projectedShown; i++) ...[
              BlockSkeleton(width: boxSize),
              if (i < projectedShown - 1) const SizedBox(width: AppSpacing.sm),
            ],
            const SizedBox(width: AppSpacing.sm / 2),
            DashedDivider(height: boxSize),
            const SizedBox(width: AppSpacing.sm / 2),
            for (var i = 0; i < minedShown; i++) ...[
              BlockSkeleton(width: boxSize),
              if (i < minedShown - 1) const SizedBox(width: AppSpacing.sm),
            ],
            const SizedBox(width: AppSpacing.sm),
            counter(LinkBlock(width: boxSize)),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.boxSize});

  final double boxSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: boxSize,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                AppLocalizations.of(context).mempoolError,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            ChartRetryButton(
              onTap: () =>
                  context.read<MempoolController>().restartStream(),
            ),
          ],
        ),
      ),
    );
  }
}

// Sized for the block's two-line content (height/ETA label + fee line) with
// vertical padding. Measures the line height with the active text scaler so
// the size tracks the system text-size setting.
double _blockBoxHeight(BuildContext context) {
  const verticalPadding = 10.0;
  // Matches the stack card's inter-line gap so the two cards read with the
  // same vertical rhythm.
  const innerGap = 12.0;
  final scaler = MediaQuery.textScalerOf(context);
  final style = AppTypography.body.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  final painter = TextPainter(
    text: TextSpan(text: 'Ag', style: style),
    textDirection: ui.TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final lineHeight = painter.size.height;
  return verticalPadding * 2 + lineHeight * 2 + innerGap;
}
