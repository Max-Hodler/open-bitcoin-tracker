import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/api.dart';
import '../../../data/app_enums.dart';
import '../../../data/sats.dart';
import '../../../data/stack.dart' as model;
import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../../widgets/avatar_sheet.dart';
import '../../../widgets/menu_action_tile.dart';
import '../../../widgets/stack_card.dart' show StackCard, StackCardPosition;
import '../../edit_stack_screens.dart';
import '../../new_stack_screens.dart';
import '../../settings/reorder_stacks_screen.dart';
import 'range_pills_row.dart';

enum _StackMenuAction { edit, rename, delete }

class HomeStackList extends StatelessWidget {
  const HomeStackList({
    super.key,
    required this.stacks,
    required this.currency,
    required this.btcDisplayMode,
    this.totalCard,
    this.totalSats,
    this.totalAtTop = false,
  });

  final List<model.Stack> stacks;
  final Currency currency;
  final BtcDisplayMode btcDisplayMode;
  // When non-null, the portfolio total renders as the first or last row of the
  // same group as the stack cards (controlled by [totalAtTop]), sharing its
  // divider and corner rounding. [totalSats] drives the row's range-pill price
  // scaling.
  final Widget? totalCard;
  final int? totalSats;
  final bool totalAtTop;

  @override
  Widget build(BuildContext context) {
    // Rebuild only when the daily series refreshes (rare) or FX history
    // finishes loading (once per launch) — never on a live price tick, so the
    // pill rows below keep a stable data identity across ticks.
    context.select<LivePriceController, List<HistoryPoint>>(
      (c) => c.allHistory,
    );
    context.select<LivePriceController, bool>((c) => c.fxHistory != null);
    final controller = context.read<LivePriceController>();
    final rates = controller.rates;
    final usd = rates.usd ?? 0;
    final current = rates.forCurrency(currency) ?? 0;
    // The live "now" point is deliberately not appended here: the pills look
    // up prices >= 1 year back, so the tail point can never be a lookup
    // result, and leaving it off keeps this list's identity stable.
    final rangePillData = controller.convertedAllHistory(
      currency: currency,
      usdToCurrencyFallback: usd > 0 ? current / usd : 1.0,
    );
    final hasTotal = totalCard != null;
    final rowCount = stacks.length + (hasTotal ? 1 : 0);

    Widget totalRow(StackCardPosition position, bool isLast) => _GroupedCardRow(
          card: totalCard!,
          rangePillData: rangePillData,
          priceScale: (totalSats ?? 0) / Sats.perBtc,
          currency: currency,
          position: position,
          isLast: isLast,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTotal && totalAtTop)
          totalRow(
            stacks.isEmpty ? StackCardPosition.only : StackCardPosition.first,
            stacks.isEmpty,
          ),
        for (var i = 0; i < stacks.length; i++)
          _SwipeableStackCard(
            key: ValueKey(stacks[i].id),
            stack: stacks[i],
            currency: currency,
            btcDisplayMode: btcDisplayMode,
            rangePillData: rangePillData,
            priceScale: stacks[i].sats / Sats.perBtc,
            // isFirst: true only when this stack is the very first row of the
            // group — suppressed when the total card sits above it.
            isFirst: i == 0 && !(hasTotal && totalAtTop),
            // isLast: true only when this stack is the very last row — suppressed
            // when the total card sits below it.
            isLast: i == stacks.length - 1 && !(hasTotal && !totalAtTop),
            canReorder: stacks.length > 1,
          ),
        if (hasTotal && !totalAtTop)
          totalRow(StackCardPosition.last, true),
      ],
    );
  }
}

class _SwipeableStackCard extends StatefulWidget {
  const _SwipeableStackCard({
    super.key,
    required this.stack,
    required this.currency,
    required this.btcDisplayMode,
    required this.rangePillData,
    required this.priceScale,
    required this.isFirst,
    required this.isLast,
    required this.canReorder,
  });

  final model.Stack stack;
  final Currency currency;
  final BtcDisplayMode btcDisplayMode;
  final List<PricePoint> rangePillData;
  final double priceScale;
  final bool isFirst;
  final bool isLast;
  // Reordering is meaningless with a single stack, so the long-press gesture
  // that opens the reorder screen is suppressed unless there are >= 2 stacks.
  final bool canReorder;

  @override
  State<_SwipeableStackCard> createState() => _SwipeableStackCardState();
}

class _SwipeableStackCardState extends State<_SwipeableStackCard> {
  Future<void> _showStackMenu(BuildContext iconContext) async {
    final theme = Theme.of(iconContext);
    final cs = theme.colorScheme;
    final action = await showModalBottomSheet<_StackMenuAction>(
      context: iconContext,
      backgroundColor: theme.brightness == Brightness.dark
          ? cs.surfaceContainerHigh
          : cs.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MenuSheetHeader(widget.stack.name),
                MenuActionGroup(
                  children: [
                    MenuActionTile(
                      leading: const Text(
                        '₿',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      label: l10n.stackMenuUpdateAmount,
                      onTap: () =>
                          Navigator.of(ctx).pop(_StackMenuAction.edit),
                    ),
                    MenuActionTile(
                      leading: const Icon(Icons.edit_outlined),
                      label: l10n.stackMenuChangeName,
                      onTap: () =>
                          Navigator.of(ctx).pop(_StackMenuAction.rename),
                    ),
                    MenuActionTile(
                      leading: const Icon(Icons.delete_outline),
                      label: l10n.stackMenuDelete,
                      destructive: true,
                      onTap: () =>
                          Navigator.of(ctx).pop(_StackMenuAction.delete),
                    ),
                  ],
                ),

              ],
            ),
          ),
        );
      },
    );
    if (!iconContext.mounted) return;
    switch (action) {
      case _StackMenuAction.edit:
        await Navigator.of(iconContext).push(MaterialPageRoute<void>(
          builder: (_) => EditStackAmountScreen(stackId: widget.stack.id),
        ));
      case _StackMenuAction.rename:
        await Navigator.of(iconContext).push(MaterialPageRoute<void>(
          builder: (_) => EditStackNameScreen(stackId: widget.stack.id),
        ));

      case _StackMenuAction.delete:
        final confirm = await _showDeleteDialog(iconContext);
        if (confirm == true && iconContext.mounted) {
          iconContext.read<AppStateNotifier>().removeStack(widget.stack.id);
        }
      case null:
        break;
    }
  }

  Future<void> _showAvatarSheet(BuildContext iconContext) {
    final app = iconContext.read<AppStateNotifier>();
    final stackId = widget.stack.id;
    return showAvatarSheet(
      iconContext,
      title: widget.stack.name,
      currentImageData: widget.stack.imageData,
      currentColorKey: widget.stack.colorKey,
      onColorSet: (key) => app.updateStack(
        stackId,
        (s) => key == null
            ? s.copyWith(clearColor: true)
            : s.copyWith(colorKey: key),
      ),
      onImageSet: (base64) => app.updateStack(
        stackId,
        (s) => s.copyWith(imageData: base64),
      ),
      onImageCleared: () => app.updateStack(
        stackId,
        (s) => s.copyWith(clearImage: true),
      ),
    );
  }

  Future<bool?> _showDeleteDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierColor: appDialogBarrierColor(context),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.dialogDeleteStackTitle, textAlign: TextAlign.center, style: AppTypography.title.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.dialogDeleteStackBody, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      AppHaptics.light();
                      Navigator.of(ctx).pop(true);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: Colors.white,
                      textStyle: AppTypography.title.copyWith(fontWeight: FontWeight.w500),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
                    ),
                    child: Text(l10n.dialogDeleteStackConfirm),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      AppHaptics.light();
                      Navigator.of(ctx).pop(false);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.outlineVariant,
                      foregroundColor: cs.onSurface,
                      textStyle: AppTypography.title.copyWith(fontWeight: FontWeight.w500),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
                    ),
                    child: Text(l10n.buttonCancel),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  StackCardPosition get _position {
    if (widget.isFirst && widget.isLast) return StackCardPosition.only;
    if (widget.isFirst) return StackCardPosition.first;
    if (widget.isLast) return StackCardPosition.last;
    return StackCardPosition.middle;
  }

  @override
  Widget build(BuildContext context) {
    final card = Builder(
      // Selecting the rate here (not further up) confines the per-tick
      // rebuild to this card's subtree — the surrounding pill row and its
      // layout-measurement machinery never see the tick.
      builder: (cardContext) => StackCard(
        name: widget.stack.name,
        sats: widget.stack.sats,
        currency: widget.currency,
        btcRate: cardContext.select<LivePriceController, double?>(
          (c) => c.rates.forCurrency(widget.currency),
        ),
        btcDisplayMode: widget.btcDisplayMode,
        isHidden: widget.stack.isHidden,
        imageData: widget.stack.imageData,
        colorKey: widget.stack.colorKey,
        position: _position,
        onTap: () {
          AppHaptics.light();
          _showStackMenu(cardContext);
        },
        onLongPress: widget.canReorder
            ? () {
                AppHaptics.medium();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReorderStacksScreen(),
                  ),
                );
              }
            : null,
        onAvatarTap: () {
          AppHaptics.light();
          _showAvatarSheet(cardContext);
        },
      ),
    );
    return _GroupedCardRow(
      card: card,
      rangePillData: widget.rangePillData,
      priceScale: widget.priceScale,
      currency: widget.currency,
      position: _position,
      isLast: widget.isLast,
    );
  }
}

/// One row of the stacks group: a [RangePillsRow] plus the hairline divider
/// drawn below it (omitted on the last row, which has a rounded bottom edge
/// instead). Shared by stack cards and the trailing portfolio-total card so
/// both render identically inside the same group.
class _GroupedCardRow extends StatelessWidget {
  const _GroupedCardRow({
    required this.card,
    required this.rangePillData,
    required this.priceScale,
    required this.currency,
    required this.position,
    required this.isLast,
  });

  final Widget card;
  final List<PricePoint> rangePillData;
  final double priceScale;
  final Currency currency;
  final StackCardPosition position;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RangePillsRow(
          card: card,
          rangePillData: rangePillData,
          priceScale: priceScale,
          currency: currency,
          position: position,
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant,
          ),
      ],
    );
  }
}


