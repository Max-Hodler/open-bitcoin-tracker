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
import 'home_buttons.dart';
import 'range_pills_row.dart';

enum _StackMenuAction { edit, rename, add, reorder, delete }

class HomeStackList extends StatelessWidget {
  const HomeStackList({
    super.key,
    required this.stacks,
    required this.currency,
    required this.btcRate,
    required this.bitcoinDisplayMode,
    required this.rangePillData,
    required this.showAvatars,
    this.totalCard,
    this.totalSats,
  });

  final List<model.Stack> stacks;
  final Currency currency;
  final double? btcRate;
  final BtcDisplayMode bitcoinDisplayMode;
  final List<PricePoint> rangePillData;
  final bool showAvatars;
  // When non-null, the portfolio total renders as the final row of the same
  // group as the stack cards, sharing its divider and corner rounding so it
  // reads as just another stack rather than a detached card. [totalSats]
  // drives the row's range-pill price scaling.
  final Widget? totalCard;
  final int? totalSats;

  @override
  Widget build(BuildContext context) {
    final hasTotal = totalCard != null;
    final rowCount = stacks.length + (hasTotal ? 1 : 0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < stacks.length; i++)
          _SwipeableStackCard(
            key: ValueKey(stacks[i].id),
            stack: stacks[i],
            currency: currency,
            btcRate: btcRate,
            bitcoinDisplayMode: bitcoinDisplayMode,
            rangePillData: rangePillData,
            priceScale: stacks[i].sats / Sats.perBtc,
            isFirst: i == 0,
            isLast: i == rowCount - 1,
            showAvatar: showAvatars,
          ),
        if (hasTotal)
          _GroupedCardRow(
            card: totalCard!,
            rangePillData: rangePillData,
            priceScale: (totalSats ?? 0) / Sats.perBtc,
            currency: currency,
            // The total only renders alongside >= 2 stacks, so it is always
            // the last row of a non-empty group, never a standalone card.
            position: StackCardPosition.last,
            isLast: true,
          ),
      ],
    );
  }
}

class _SwipeableStackCard extends StatefulWidget {
  const _SwipeableStackCard({
    super.key,
    required this.stack,
    required this.currency,
    required this.btcRate,
    required this.bitcoinDisplayMode,
    required this.rangePillData,
    required this.priceScale,
    required this.isFirst,
    required this.isLast,
    required this.showAvatar,
  });

  final model.Stack stack;
  final Currency currency;
  final double? btcRate;
  final BtcDisplayMode bitcoinDisplayMode;
  final List<PricePoint> rangePillData;
  final double priceScale;
  final bool isFirst;
  final bool isLast;
  final bool showAvatar;

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
        final hasMultipleStacks =
            ctx.read<AppStateNotifier>().stacks.length > 1;
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
                const SizedBox(height: AppSpacing.md),
                MenuActionGroup(
                  children: [
                    MenuActionTile(
                      leading: const Icon(Icons.add),
                      label: l10n.homeAddStack,
                      onTap: () =>
                          Navigator.of(ctx).pop(_StackMenuAction.add),
                    ),
                    if (hasMultipleStacks)
                      MenuActionTile(
                        leading: const Icon(Icons.swap_vert),
                        label: l10n.settingsReorderStacks,
                        onTap: () =>
                            Navigator.of(ctx).pop(_StackMenuAction.reorder),
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
      case _StackMenuAction.add:
        await Navigator.of(iconContext).push(MaterialPageRoute<void>(
          builder: (_) => const NewStackAmountScreen(),
        ));
      case _StackMenuAction.reorder:
        await Navigator.of(iconContext).push(MaterialPageRoute<void>(
          builder: (_) => const ReorderStacksScreen(),
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
      builder: (cardContext) => StackCard(
        name: widget.stack.name,
        sats: widget.stack.sats,
        currency: widget.currency,
        btcRate: widget.btcRate,
        bitcoinDisplayMode: widget.bitcoinDisplayMode,
        isHidden: widget.stack.isHidden,
        imageData: widget.stack.imageData,
        colorKey: widget.stack.colorKey,
        showAvatar: widget.showAvatar,
        position: _position,
        onTap: () {
          AppHaptics.light();
          _showStackMenu(cardContext);
        },
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
          ColoredBox(
            color: cs.surface,
            child: Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant,
            ),
          ),
      ],
    );
  }
}

class StacksLockedCard extends StatelessWidget {
  const StacksLockedCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HomeButton(
      icon: Icon(Icons.lock_outline, size: 22, color: cs.onSurfaceVariant),
      label: AppLocalizations.of(context).homeUnlockStacks,
      onTap: onTap,
      height: AppSpacing.stackCardHeight + AppSpacing.lg,
    );
  }
}

