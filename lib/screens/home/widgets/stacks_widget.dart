import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_enums.dart';
import '../../../data/sats.dart';
import '../../../data/stack.dart' as model;
import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';
import '../../../widgets/menu_action_tile.dart';
import '../../../widgets/stack_card.dart';
import '../../edit_stack_screens.dart';
import '../../new_stack_screens.dart';
import '../header/area_chart.dart';
import 'home_buttons.dart';
import 'range_pills_row.dart';

enum _StackMenuAction { edit, rename, add, delete }

class ReorderableStackList extends StatelessWidget {
  const ReorderableStackList({
    super.key,
    required this.stacks,
    required this.currency,
    required this.btcRate,
    required this.bitcoinDisplayMode,
    required this.rangePillData,
    required this.onReorder,
  });

  final List<model.Stack> stacks;
  final Currency currency;
  final double? btcRate;
  final BtcDisplayMode bitcoinDisplayMode;
  final List<PricePoint> rangePillData;
  final void Function(int, int) onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      proxyDecorator: (child, index, animation) =>
          _StackDragProxy(animation: animation, child: child),
      onReorderStart: (_) => AppHaptics.medium(),
      onReorder: (oldIndex, newIndex) {
        AppHaptics.medium();
        onReorder(oldIndex, newIndex);
      },
      itemCount: stacks.length,
      itemBuilder: (context, index) {
        final stack = stacks[index];
        return _SwipeableStackCard(
          key: ValueKey(stack.id),
          index: index,
          stack: stack,
          currency: currency,
          btcRate: btcRate,
          bitcoinDisplayMode: bitcoinDisplayMode,
          rangePillData: rangePillData,
          priceScale: stack.sats / Sats.perBtc,
          isLast: index == stacks.length - 1,
        );
      },
    );
  }
}

class _StackDragProxy extends StatefulWidget {
  const _StackDragProxy({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_StackDragProxy> createState() => _StackDragProxyState();
}

class _StackDragProxyState extends State<_StackDragProxy>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 70),
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _syncFromParent();
    widget.animation.addStatusListener(_onParentStatus);
  }

  void _onParentStatus(AnimationStatus status) => _syncFromParent();

  void _syncFromParent() {
    switch (widget.animation.status) {
      case AnimationStatus.forward:
      case AnimationStatus.completed:
        _controller.forward();
      case AnimationStatus.reverse:
      case AnimationStatus.dismissed:
        _controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onParentStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, _) => Transform.scale(
        scale: 1.0 + 0.03 * _curved.value,
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15 * _curved.value),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}


class _SwipeableStackCard extends StatefulWidget {
  const _SwipeableStackCard({
    super.key,
    required this.index,
    required this.stack,
    required this.currency,
    required this.btcRate,
    required this.bitcoinDisplayMode,
    required this.rangePillData,
    required this.priceScale,
    required this.isLast,
  });

  final int index;
  final model.Stack stack;
  final Currency currency;
  final double? btcRate;
  final BtcDisplayMode bitcoinDisplayMode;
  final List<PricePoint> rangePillData;
  final double priceScale;
  final bool isLast;

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
                MenuActionTile(
                  leading: const Text(
                    '₿',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  label: l10n.stackMenuUpdateAmount,
                  onTap: () => Navigator.of(ctx).pop(_StackMenuAction.edit),
                ),
                const SizedBox(height: AppSpacing.xs),
                MenuActionTile(
                  leading: const Icon(Icons.edit_outlined),
                  label: l10n.stackMenuChangeName,
                  onTap: () => Navigator.of(ctx).pop(_StackMenuAction.rename),
                ),
                const SizedBox(height: AppSpacing.xs),
                MenuActionTile(
                  leading: const Icon(Icons.delete_outline),
                  label: l10n.stackMenuDelete,
                  destructive: true,
                  onTap: () => Navigator.of(ctx).pop(_StackMenuAction.delete),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                  ),
                ),
                MenuActionTile(
                  leading: const Icon(Icons.add),
                  label: l10n.homeAddStack,
                  onTap: () => Navigator.of(ctx).pop(_StackMenuAction.add),
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
      case _StackMenuAction.delete:
        final confirm = await _showDeleteDialog(iconContext);
        if (confirm == true && iconContext.mounted) {
          iconContext.read<AppStateNotifier>().removeStack(widget.stack.id);
        }
      case null:
        break;
    }
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
        onTap: () {
          AppHaptics.light();
          _showStackMenu(cardContext);
        },
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: widget.isLast ? 0 : AppSpacing.sm),
      child: ReorderableDelayedDragStartListener(
        index: widget.index,
        child: RangePillsRow(
          card: card,
          rangePillData: widget.rangePillData,
          priceScale: widget.priceScale,
          currency: widget.currency,
        ),
      ),
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
