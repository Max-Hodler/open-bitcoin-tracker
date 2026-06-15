import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../data/app_enums.dart';
import '../../data/fiat.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';

/// Rounded card container used by both the per-stack and total detail screens.
class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    this.title,
    this.verticalPadding = AppSpacing.sm,
    this.bottomPadding,
    required this.child,
  });
  final String? title;
  final double verticalPadding;
  final double? bottomPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              title!,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        Container(
          padding: EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: verticalPadding,
            bottom: bottomPadding ?? verticalPadding,
          ),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// "Worth back then" rows — shared by per-stack and total detail screens.
class PastValuesSection extends StatefulWidget {
  const PastValuesSection({
    super.key,
    required this.currency,
    required this.btcAmount,
  });

  final Currency currency;
  final double btcAmount;

  @override
  State<PastValuesSection> createState() => _PastValuesSectionState();
}

const int _kDefaultRows = 4;

class _PastValuesSectionState extends State<PastValuesSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final controller = context.watch<LivePriceController>();
    final usdRate = controller.rates.usd ?? 0;
    final currentPrice = controller.rates.forCurrency(widget.currency) ?? 0;
    final usdToCurrency = usdRate > 0 ? currentPrice / usdRate : 1.0;
    final history = controller.convertedAllHistory(
      currency: widget.currency,
      usdToCurrencyFallback: usdToCurrency,
    );

    if (history.length < 2) return const SizedBox.shrink();

    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toString();
    final dateFmt = DateFormat.yMMMd(locale);

    final allRows = <_PastRow>[];
    for (var y = 1; now.year - y >= 2009; y++) {
      final at = DateTime(now.year - y, now.month, now.day);
      final price = _priceAt(history, at.millisecondsSinceEpoch);
      allRows.add(_PastRow(
        label: l10n.stackDetailYearAgo(y),
        sublabel: dateFmt.format(at),
        value: (price ?? 0) * widget.btcAmount,
      ));
    }

    final needsToggle = allRows.length > _kDefaultRows;
    final alwaysRows =
        needsToggle ? allRows.take(_kDefaultRows).toList() : allRows;
    final extraRows =
        needsToggle ? allRows.skip(_kDefaultRows).toList() : <_PastRow>[];

    return DetailSection(
      verticalPadding: AppSpacing.lg,
      bottomPadding: AppSpacing.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              l10n.stackDetailWorthBackThen,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < alwaysRows.length; i++) ...[
            if (i > 0) const DetailRowDivider(),
            DetailValueRow(
              label: alwaysRows[i].label,
              sublabel: alwaysRows[i].sublabel,
              value: alwaysRows[i].value,
              currency: widget.currency,
            ),
          ],
          if (needsToggle) ...[
            _ExpandableRows(
              expanded: _expanded,
              rows: extraRows,
              currency: widget.currency,
            ),
            const DetailRowDivider(),
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Center(
                child: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOut,
                  child: IconButton(
                    onPressed: () {
                      AppHaptics.light();
                      setState(() => _expanded = !_expanded);
                    },
                    icon: const Icon(Icons.expand_more),
                    iconSize: 22,
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.surface,
                      foregroundColor: cs.onSurfaceVariant,
                      shadowColor: Colors.black.withValues(alpha: 0.12),
                      elevation: 1.5,
                      fixedSize: const Size(36, 36),
                      minimumSize: const Size(36, 36),
                      maximumSize: const Size(36, 36),
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static double? _priceAt(List<PricePoint> data, int targetMs) {
    if (data.isEmpty || targetMs <= data.first.t) return null;
    int lo = 0, hi = data.length - 1, best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (data[mid].t <= targetMs) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best >= 0 ? data[best].price : null;
  }
}

class _ExpandableRows extends StatefulWidget {
  const _ExpandableRows({
    required this.expanded,
    required this.rows,
    required this.currency,
  });

  final bool expanded;
  final List<_PastRow> rows;
  final Currency currency;

  @override
  State<_ExpandableRows> createState() => _ExpandableRowsState();
}

class _ExpandableRowsState extends State<_ExpandableRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _size;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: widget.expanded ? 1.0 : 0.0,
    );
    _size = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(_ExpandableRows old) {
    super.didUpdateWidget(old);
    if (widget.expanded != old.expanded) {
      widget.expanded ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _size,
      axisAlignment: -1,
      child: Column(
        children: [
          for (var i = 0; i < widget.rows.length; i++) ...[
            const DetailRowDivider(),
            DetailValueRow(
              label: widget.rows[i].label,
              sublabel: widget.rows[i].sublabel,
              value: widget.rows[i].value,
              currency: widget.currency,
            ),
          ],
        ],
      ),
    );
  }
}

class _PastRow {
  const _PastRow({
    required this.label,
    required this.sublabel,
    required this.value,
  });
  final String label;
  final String sublabel;
  final double value;
}

class DetailValueRow extends StatelessWidget {
  const DetailValueRow({
    super.key,
    required this.label,
    required this.sublabel,
    required this.value,
    required this.currency,
  });

  final String label;
  final String sublabel;
  final double value;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = formatFiat(value, currency, decimalsUnder10: true);
    final amountStyle = AppTypography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.3,
      color: cs.onSurface.withValues(alpha: 0.9),
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final symbol = Text(
      fmt.symbol,
      style: amountStyle.copyWith(color: cs.onSurfaceVariant),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.body.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sublabel,
                  style: AppTypography.label.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (symbolAfterAmount) ...[
            Text(fmt.amount, textAlign: TextAlign.right, style: amountStyle),
            const SizedBox(width: 4),
            symbol,
          ] else ...[
            symbol,
            const SizedBox(width: 4),
            Text(fmt.amount, textAlign: TextAlign.right, style: amountStyle),
          ],
        ],
      ),
    );
  }
}

class DetailRowDivider extends StatelessWidget {
  const DetailRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
