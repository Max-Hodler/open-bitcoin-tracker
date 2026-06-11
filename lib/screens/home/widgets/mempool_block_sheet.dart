import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/api.dart';
import '../../../data/app_enums.dart';
import '../../../data/fiat.dart' show formatBtcAmount, intFormatter;
import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../../widgets/menu_action_tile.dart';

enum MempoolBlockKind { projected, mined }

/// Show the bottom sheet with details for a single mempool block. The
/// `displayIndex` is the strip index of a projected block (0 = leftmost,
/// longest ETA), used to build the `/mempool-block/{index}` deep link —
/// mempool.space's pending-block URL takes the array index from
/// `/v1/fees/mempool-blocks`, which is `(projectedCount - 1) - displayIndex`.
/// For mined blocks `displayIndex` is unused.
Future<void> showMempoolBlockSheet(
  BuildContext context, {
  required MempoolBlock block,
  required MempoolBlockKind kind,
  required int displayIndex,
  required int projectedCount,
}) async {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.brightness == Brightness.dark
        ? cs.surfaceContainerHigh
        : cs.surfaceContainerLow,
    showDragHandle: true,
    // Default cap is ~50% of screen height; mined-block content (header +
    // 4 detail rows + action tile) overflows on shorter devices, so let the
    // sheet grow naturally and let SingleChildScrollView handle the rest.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _MempoolBlockSheet(
      block: block,
      kind: kind,
      displayIndex: displayIndex,
      projectedCount: projectedCount,
    ),
  );
}

class _MempoolBlockSheet extends StatelessWidget {
  const _MempoolBlockSheet({
    required this.block,
    required this.kind,
    required this.displayIndex,
    required this.projectedCount,
  });

  final MempoolBlock block;
  final MempoolBlockKind kind;
  final int displayIndex;
  final int projectedCount;

  String? _viewUrl() {
    if (kind == MempoolBlockKind.mined) {
      // The hash comes from the network and is interpolated into a launched
      // URL — accept only a canonical 64-char hex block hash.
      final h = block.hash;
      if (h == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(h)) return null;
      return 'https://mempool.space/block/$h';
    }
    // projected: mempool.space uses the fee-priority array index
    // (0 = highest priority = next block). Display index 0 is the leftmost
    // (lowest priority) block in our strip, so reverse it.
    final feeIdx = (projectedCount - 1) - displayIndex;
    if (feeIdx < 0) return null;
    return 'https://mempool.space/mempool-block/$feeIdx';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isMined = kind == MempoolBlockKind.mined;

    final title = isMined
        ? (block.height != null
            ? l10n.mempoolSheetMinedTitle(intFormatter.format(block.height))
            : l10n.mempoolSheetProjectedTitle)
        : l10n.mempoolSheetProjectedTitle;

    final subtitle = isMined
        ? (block.timestamp != null
            ? l10n.mempoolSheetMinedAgo(_minutesSince(block.timestamp!))
            : null)
        : l10n.mempoolSheetProjectedEta(block.etaMinutes ?? 0);

    final url = _viewUrl();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MenuSheetHeader(title),
            if (subtitle != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  subtitle,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            _DetailRows(
              block: block,
              isMined: isMined,
              l10n: l10n,
              btcDisplayMode:
                  context.watch<AppStateNotifier>().btcDisplayMode,
            ),
            if (url != null) ...[
              const SizedBox(height: AppSpacing.md),
              MenuActionTile(
                trailing: const Icon(Icons.open_in_new),
                label: l10n.mempoolSheetViewOnMempoolSpace,
                onTap: () async {
                  AppHaptics.selection();
                  Navigator.of(context).pop();
                  await launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({
    required this.block,
    required this.isMined,
    required this.l10n,
    required this.btcDisplayMode,
  });

  final MempoolBlock block;
  final bool isMined;
  final AppLocalizations l10n;
  final BtcDisplayMode btcDisplayMode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <_KV>[];

    if (block.medianFeeSatVb != null) {
      rows.add(_KV(
        label: l10n.mempoolSheetFee,
        value: '${_formatSatVb(block.medianFeeSatVb!)} ${l10n.mempoolUnit}',
      ));
    }
    final fr = block.feeRangeSatVb;
    if (fr != null) {
      rows.add(_KV(
        label: l10n.mempoolSheetFeeRange,
        value: l10n.mempoolSheetFeeRangeValue(
          _formatSatVb(fr.min),
          _formatSatVb(fr.max),
          l10n.mempoolUnit,
        ),
      ));
    }
    rows.add(_KV(
      label: l10n.mempoolSheetTransactions,
      value: intFormatter.format(block.txCount),
    ));
    if (block.totalFeesSats != null) {
      rows.add(_KV(
        label: l10n.mempoolSheetTotalFees,
        value: formatBtcAmount(
          block.totalFeesSats!,
          mode: btcDisplayMode,
        ),
      ));
    }
    // No inner card: rows sit directly on the sheet background so the
    // dividers read like the settings-screen / scroll-hairline lines instead
    // of as hard rules inside a brighter container.
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant,
            ),
          _DetailRow(kv: rows[i]),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.kv});

  final _KV kv;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              kv.label,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            kv.value,
            style: AppTypography.body.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _KV {
  const _KV({required this.label, required this.value});
  final String label;
  final String value;
}

int _minutesSince(DateTime t) {
  final diff = DateTime.now().toUtc().difference(t);
  final m = diff.inMinutes;
  return m < 0 ? 0 : m;
}

String _formatSatVb(double v) {
  if (v >= 100) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
