import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../data/fiat.dart';
import '../../data/sats.dart';
import '../../data/app_enums.dart';
import '../../data/stack.dart' as model;
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/stack_actions.dart';
import '../../widgets/stack_avatar.dart';
import '../edit_stack_screens.dart';
import 'future_value_slider.dart';


/// Per-stack detail view: what the stack was worth at past dates and an
/// interactive "what if BTC reaches X" projection. Opened by tapping a stack
/// card on the home screen.
class StackDetailScreen extends StatefulWidget {
  const StackDetailScreen({super.key, required this.stackId});

  final String stackId;

  @override
  State<StackDetailScreen> createState() => _StackDetailScreenState();
}

enum _StackAction { edit, rename, delete }

class _StackDetailScreenState extends State<StackDetailScreen> {
  final _menuKey = GlobalKey<PopupMenuButtonState<_StackAction>>();

  // Resolve the live stack from the notifier so an amount/name/avatar edit made
  // from the overflow menu reflects here on return without a manual refresh.
  model.Stack? _stackOf(AppStateNotifier app) {
    for (final s in app.stacks) {
      if (s.id == widget.stackId) return s;
    }
    return null;
  }

  Future<void> _handleAction(_StackAction action, model.Stack stack) async {
    switch (action) {
      case _StackAction.edit:
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EditStackAmountScreen(stackId: stack.id),
        ));
      case _StackAction.rename:
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EditStackNameScreen(stackId: stack.id),
        ));
      case _StackAction.delete:
        final confirm = await showDeleteStackDialog(context);
        if (confirm == true && context.mounted) {
          context.read<AppStateNotifier>().removeStack(stack.id);
          // The build's null-stack guard pops us back home.
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final app = context.watch<AppStateNotifier>();
    final stack = _stackOf(app);

    // The stack was deleted out from under us (e.g. via the overflow menu) —
    // bail back to the previous screen on the next frame.
    if (stack == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final currency = app.currency;
    final btcAmount = stack.sats / Sats.perBtc;
    final itemStyle = AppTypography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: cs.onSurface,
    );

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(
          color: cs.onSurfaceVariant,
          onPressed: () {
            AppHaptics.light();
            Navigator.of(context).maybePop();
          },
        ),
        centerTitle: false,
        titleSpacing: AppSpacing.xs,
        title: GestureDetector(
          onTap: () => _handleAction(_StackAction.rename, stack),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              StackAvatar(
                name: stack.name,
                imageData: stack.imageData,
                colorKey: stack.colorKey,
                size: 36,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  stack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.title.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: PopupMenuButton<_StackAction>(
              key: _menuKey,
              onOpened: AppHaptics.light,
              onSelected: (action) => _handleAction(action, stack),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48),
              popUpAnimationStyle:
                  const AnimationStyle(duration: Duration(milliseconds: 120)),
              offset: const Offset(0, 56),
              color: cs.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
              ),
              child: IconButton(
                onPressed: () => _menuKey.currentState?.showButtonMenu(),
                icon: const Icon(Icons.more_vert),
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
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: _StackAction.edit,
                  child: Row(children: [
                    Icon(Icons.currency_bitcoin, size: 20, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(l10n.stackMenuUpdateAmount, style: itemStyle),
                  ]),
                ),
                PopupMenuItem(
                  value: _StackAction.rename,
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 20, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(l10n.stackMenuChangeName, style: itemStyle),
                  ]),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _StackAction.delete,
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 20, color: cs.error),
                    const SizedBox(width: 12),
                    Text(l10n.stackMenuDelete,
                        style: itemStyle.copyWith(color: cs.error)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl * 2,
        ),
        children: [
          _Header(stack: stack, currency: currency, stackId: stack.id),
          const SizedBox(height: AppSpacing.xl),
          _PastValuesSection(currency: currency, btcAmount: btcAmount),
          const SizedBox(height: AppSpacing.xl),
          _FutureSection(
            stackId: stack.id,
            currency: currency,
            btcAmount: btcAmount,
            savedPrice: stack.projectedPriceCurrency == currency.code
                ? stack.projectedPrice
                : null,
          ),
        ],
      ),
    );
  }
}

/// Stack avatar + name + current fiat value and BTC amount.
class _Header extends StatelessWidget {
  const _Header({
    required this.stack,
    required this.currency,
    required this.stackId,
  });

  final model.Stack stack;
  final Currency currency;
  final String stackId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final liveRate = context.select<LivePriceController, double?>(
          (c) => c.rates.forCurrency(currency),
        ) ??
        0;
    final value = Sats.toFiat(stack.sats, liveRate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => EditStackAmountScreen(stackId: stackId),
          )),
          child: Text(
            formatBtcAmount(stack.sats,
                hidden: stack.isHidden, mode: BtcDisplayMode.btc),
            style: AppTypography.display.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: context.palette.bitcoinOrange,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatFiat(value, currency, decimalsUnder10: true).full,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body.copyWith(
            fontSize: 30,
            color: cs.onSurface,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// "Worth back then" — static rows mapping past dates to the stack's value
/// then. Pulled from the full converted all-history series via binary search.
class _PastValuesSection extends StatefulWidget {
  const _PastValuesSection({required this.currency, required this.btcAmount});

  final Currency currency;
  final double btcAmount;

  @override
  State<_PastValuesSection> createState() => _PastValuesSectionState();
}

const int _kDefaultRows = 5;

class _PastValuesSectionState extends State<_PastValuesSection> {
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
    final firstT = DateTime.fromMillisecondsSinceEpoch(history.first.t);
    final yearsOfHistory = now.year - firstT.year;
    final locale = Localizations.localeOf(context).toString();
    final dateFmt = DateFormat.yMMMd(locale);

    final allRows = <_PastRow>[];
    for (var y = 1; y <= yearsOfHistory; y++) {
      final at = DateTime(now.year - y, now.month, now.day);
      final price = _priceAt(history, at.millisecondsSinceEpoch);
      if (price == null) continue;
      allRows.add(_PastRow(
        label: l10n.stackDetailYearAgo(y),
        sublabel: dateFmt.format(at),
        value: price * widget.btcAmount,
      ));
    }
    // All-time: the very first data point.
    allRows.add(_PastRow(
      label: l10n.stackDetailAllTime,
      sublabel: dateFmt.format(firstT),
      value: history.first.price * widget.btcAmount,
    ));

    final needsToggle = allRows.length > _kDefaultRows;
    final alwaysRows =
        needsToggle ? allRows.take(_kDefaultRows).toList() : allRows;
    final extraRows = needsToggle ? allRows.skip(_kDefaultRows).toList() : <_PastRow>[];

    return _Section(
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
            if (i > 0) const _RowDivider(),
            _ValueRow(
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
            const _RowDivider(),
            InkWell(
              onTap: () {
                AppHaptics.light();
                setState(() => _expanded = !_expanded);
              },
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.expand_more,
                    size: 24,
                    color: cs.onSurfaceVariant,
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
            const _RowDivider(),
            _ValueRow(
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

/// "If Bitcoin reaches…" — the interactive future-value projection.
class _FutureSection extends StatelessWidget {
  const _FutureSection({
    required this.stackId,
    required this.currency,
    required this.btcAmount,
    required this.savedPrice,
  });

  final String stackId;
  final Currency currency;
  final double btcAmount;

  /// The last BTC price the user parked the slider on for this stack in the
  /// active currency, or null to fall back to the 1M default.
  final double? savedPrice;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LivePriceController>();
    final currentPrice = controller.rates.forCurrency(currency) ?? 0;
    final floor = currentPrice > 0 ? currentPrice : 100000.0;
    final ceiling = _ceilingFor(floor);
    final initial = savedPrice ?? _initialFor(floor, ceiling, btcAmount);

    return _Section(
      verticalPadding: AppSpacing.lg,
      // Rebuild the slider's initial position when the restored price or the
      // bounds change (currency switch, amount edit) so it re-seeds correctly.
      child: FutureValueSlider(
        key: ValueKey('$stackId|$initial|$floor|$ceiling'),
        btcAmount: btcAmount,
        currency: currency,
        minPrice: floor,
        maxPrice: ceiling,
        initialPrice: initial,
        onPriceSelected: (price) {
          context.read<AppStateNotifier>().updateStack(
                stackId,
                (s) => s.copyWith(
                  projectedPrice: price,
                  projectedPriceCurrency: currency.code,
                ),
              );
        },
      ),
    );
  }

  // ~20× today's price, rounded up to a clean power-of-ten-ish number.
  static double _ceilingFor(double floor) {
    final target = floor * 20;
    var mag = 1.0;
    while (mag * 10 <= target) {
      mag *= 10;
    }
    return (target / mag).ceilToDouble() * mag;
  }

  // Start the thumb at the BTC price where this stack would be worth 1M of the
  // selected fiat, clamped to the slider's bounds.
  static double _initialFor(double floor, double ceiling, double btcAmount) =>
      btcAmount > 0
          ? (1000000.0 / btcAmount).clamp(floor, ceiling)
          : (floor * 3).clamp(floor, ceiling);
}

// ---- shared building blocks ----

class _Section extends StatelessWidget {
  const _Section({
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

class _ValueRow extends StatelessWidget {
  const _ValueRow({
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
    // The currency symbol sits in its own fixed-width, muted slot so the symbols
    // line up vertically across rows and the digits run flush against them —
    // turning a ragged column into a scannable one. Tabular figures (above)
    // keep digit widths constant so the right-aligned amounts also align.
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

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
