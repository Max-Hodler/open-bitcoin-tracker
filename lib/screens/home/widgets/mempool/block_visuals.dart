import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../api/api.dart';
import '../../../../data/fiat.dart' show intFormatter;
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../services/app_haptics.dart';
import '../../../../state/state.dart';
import '../../../../theme/theme.dart';
import '../mempool_block_sheet.dart';

/// Which side of the divider a slide slot lands on. Projected and mined
/// blocks share the same fill, so this no longer affects styling — it only
/// marks a slot's target so the strip knows when a block has crossed.
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
    required this.width,
    required this.displayIndex,
    required this.projectedCount,
    required this.contentAsProjected,
  });

  final MempoolBlock block;
  final double width;
  // Position in the rendered strip — used to build the
  // /mempool-block/{feeIndex} URL for projected blocks. Unused for mined.
  final int displayIndex;
  final int projectedCount;
  // Content kind: label/fee formatting and sheet kind. The crossing slot
  // renders projected content (ETA) during the slide even though it lands as
  // a mined block, because its block data has no mined height yet.
  final bool contentAsProjected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textPrimary.withValues(alpha: 0.78);
    final l10n = AppLocalizations.of(context);

    // Block height for mined, ETA for projected — rendered inside the box.
    final String? label = contentAsProjected
        ? l10n.mempoolBlockEta(block.etaMinutes ?? 0)
        : (block.height != null ? intFormatter.format(block.height) : null);

    final radius = BorderRadius.circular(AppSpacing.radius);

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: InkWell(
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
  const BlockSkeleton({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: width,
      decoration: BoxDecoration(
        color: cs.surface,
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
      const Offset(0, 0),
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
