import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../api/api.dart';
import '../../../../format/fiat.dart' show intFormatter;
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../services/app_haptics.dart';
import '../../../../state/state.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/theme.dart';
import '../mempool_block_sheet.dart';

/// Styling kind for a single block in the strip. Visual only — content kind
/// (label/sheet kind) is independent via [BlockBox.contentAsProjected].
enum BlockKind { projected, mined }

/// Width of the dashed divider that separates projected from mined blocks.
const double kMempoolDividerWidth = AppSpacing.sm;

/// Horizontal padding inside the scroll viewport so the leftmost-projected and
/// the mempool.space link block don't sit flush against the screen edges when
/// the user scrolls to either extreme.
const double kMempoolStripPadding = AppSpacing.md;

class BlockBox extends StatelessWidget {
  const BlockBox({
    super.key,
    required this.block,
    required this.kind,
    required this.width,
    required this.displayIndex,
    required this.projectedCount,
    required this.contentAsProjected,
    this.minedFraction = 0,
  });

  final MempoolBlock block;
  // Styling kind: projected → cs.surface fill; mined → cs.surfaceContainer
  // fill (or transparent + outline in dark mode).
  final BlockKind kind;
  final double width;
  // Position in the rendered strip — used to build the
  // /mempool-block/{feeIndex} URL for projected blocks. Unused for mined.
  final int displayIndex;
  final int projectedCount;
  // Content kind: label/fee formatting and sheet kind. Decoupled from
  // styling because the crossing slot lands on mined styling at slide-end
  // but its block data (and what the user sees during the slide) is
  // projected.
  final bool contentAsProjected;
  // Fraction of the box to paint with mined colors during a slide (right
  // side of the split). 0 → entire box paints projected (the crossing slot's
  // kindAtTarget is mined, so without this override it would flash mined for
  // a frame before the slide makes minedFraction > 0); (0, 1) → split with
  // the painter; 1 isn't a separate case because kindAtTarget = mined for
  // the crossing slot, so the styling lands on mined naturally and the
  // painter is skipped.
  final double minedFraction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // The crossing slot's [kind] is `mined` so its styling lands correctly
    // at slide-end. While the slide hasn't actually started crossing
    // (minedFraction == 0), force projected styling so the box doesn't
    // flash mined for one frame before the gradient takes over. Once
    // minedFraction >= 1 the block has fully crossed and should paint as
    // mined — using `contentAsProjected` to gate this would also flash
    // projected at the end of the slide.
    final isProjectedStyle = kind == BlockKind.projected ||
        (contentAsProjected && minedFraction == 0);
    final isDark = cs.brightness == Brightness.dark;
    // Projected blocks fill with surfaceContainer in light mode and the
    // palette's recessed surface in dark mode — one step below the lifted
    // button surfaces so they read as "below" the mined blocks. No outline
    // needed; the fill itself provides the contrast.
    final minedColor = cs.surface;
    final projectedFillColor =
        context.palette.recessedSurface ?? cs.surfaceContainer;
    final boxColor = isProjectedStyle ? projectedFillColor : minedColor;
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textPrimary.withValues(alpha: 0.78);
    final l10n = AppLocalizations.of(context);

    // Block height for mined, ETA for projected — rendered inside the box.
    final String? label = contentAsProjected
        ? l10n.mempoolBlockEta(block.etaMinutes ?? 0)
        : (block.height != null ? intFormatter.format(block.height) : null);

    final isSplit = minedFraction > 0 && minedFraction < 1;
    final radius = BorderRadius.circular(AppSpacing.radius);
    // Two-stop gradient with both stops at the same fraction = a hard
    // vertical split between the projected and mined fills as the block
    // crosses the divider.
    final splitX = 1 - minedFraction;

    return Material(
      color: isSplit ? Colors.transparent : boxColor,
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: Stack(
        children: [
          if (isSplit)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [projectedFillColor, projectedFillColor, minedColor, minedColor],
                    stops: [0, splitX, splitX, 1],
                  ),
                ),
              ),
            ),
          InkWell(
            borderRadius: radius,
            onTap: () {
              AppHaptics.selection();
              showMempoolBlockSheet(
                context,
                block: block,
                kind: contentAsProjected
                    ? MempoolBlockKind.projected
                    : MempoolBlockKind.mined,
                displayIndex: displayIndex,
                projectedCount: projectedCount,
              );
            },
            // Debug-only: long-pressing a block triggers the simulate-mined
            // animation. Attached to the InkWell rather than the strip so the
            // deeper-in-tree recognizer wins over the surrounding scroll.
            onLongPress: kDebugMode
                ? () {
                    AppHaptics.selection();
                    context.read<MempoolController>().debugSimulateNewBlock();
                  }
                : null,
            child: SizedBox(
              width: width,
              height: width,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (label != null)
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textHeightBehavior: const TextHeightBehavior(
                          applyHeightToFirstAscent: false,
                        ),
                        style: AppTypography.body.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 1.1,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    // Match the stack card's inter-line gap; the box height
                    // is sized to fit two 16pt lines plus this exact gap.
                    if (label != null) const SizedBox(height: 12),
                    _feeLine(
                      value: block.medianFeeSatVb != null
                          ? _formatSatVb(block.medianFeeSatVb!)
                          : '—',
                      textColor: textColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feeLine({required String value, required Color textColor}) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.body.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
    );
  }
}

class LinkBlock extends StatelessWidget {
  const LinkBlock({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textPrimary.withValues(alpha: 0.78);
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: () async {
          AppHaptics.selection();
          await launchUrl(
            Uri.parse('https://mempool.space/'),
            mode: LaunchMode.externalApplication,
          );
        },
        child: SizedBox(
          width: width,
          height: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'mempool',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    height: 1.2,
                  ),
                ),
                Text(
                  '.space',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: textColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BlockSkeleton extends StatelessWidget {
  const BlockSkeleton({super.key, required this.width, required this.kind});

  final double width;
  // Match the loaded-strip fills so nothing visually shifts when data arrives:
  // projected (left of divider) gets the recessed surface; mined (right) gets
  // cs.surface. Mirrors the fill logic in BlockBox.build.
  final BlockKind kind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = kind == BlockKind.projected
        ? (context.palette.recessedSurface ?? cs.surfaceContainer)
        : cs.surface;
    return Container(
      width: width,
      height: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
    );
  }
}

class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: kMempoolDividerWidth,
      height: height,
      child: CustomPaint(
        painter: _DashedLinePainter(
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Fade the dashes at the top and bottom edges to match the chart's hover
    // line (area_chart.dart): transparent at 0%/100%, full color between
    // 15%–85%.
    final shader = ui.Gradient.linear(
      Offset(0, 0),
      Offset(0, size.height),
      [
        color.withValues(alpha: 0),
        color,
        color,
        color.withValues(alpha: 0),
      ],
      const [0.0, 0.15, 0.85, 1.0],
    );
    final paint = Paint()
      ..shader = shader
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dashHeight = 4.0;
    const dashGap = 4.0;
    var y = 0.0;
    final x = size.width / 2;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dashHeight), paint);
      y += dashHeight + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

String _formatSatVb(double v) {
  if (v >= 100) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
