import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_enums.dart';
import '../../../data/stack.dart' as model;
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../widgets/avatar_sheet.dart';
import '../../../widgets/stack_card.dart' show StackCard, StackCardPosition;
import '../../settings/reorder_stacks_screen.dart';
import '../../stack_detail/stack_detail_screen.dart';

class HomeStackList extends StatelessWidget {
  const HomeStackList({
    super.key,
    required this.stacks,
    required this.currency,
    required this.btcDisplayMode,
    this.totalCard,
  });

  final List<model.Stack> stacks;
  final Currency currency;
  final BtcDisplayMode btcDisplayMode;
  // When non-null, the portfolio total renders as the first row of the same
  // group as the stack cards, sharing its divider and corner rounding.
  final Widget? totalCard;

  @override
  Widget build(BuildContext context) {
    final hasTotal = totalCard != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTotal)
          _GroupedCardRow(
            card: totalCard!,
            position: stacks.isEmpty
                ? StackCardPosition.only
                : StackCardPosition.first,
            isLast: stacks.isEmpty,
          ),
        for (var i = 0; i < stacks.length; i++)
          _StackCardRow(
            key: ValueKey(stacks[i].id),
            stack: stacks[i],
            currency: currency,
            btcDisplayMode: btcDisplayMode,
            isFirst: i == 0 && !hasTotal,
            isLast: i == stacks.length - 1,
            canReorder: stacks.length > 1,
          ),
      ],
    );
  }
}

class _StackCardRow extends StatefulWidget {
  const _StackCardRow({
    super.key,
    required this.stack,
    required this.currency,
    required this.btcDisplayMode,
    required this.isFirst,
    required this.isLast,
    required this.canReorder,
  });

  final model.Stack stack;
  final Currency currency;
  final BtcDisplayMode btcDisplayMode;
  final bool isFirst;
  final bool isLast;
  // Reordering is meaningless with a single stack, so the long-press gesture
  // that opens the reorder screen is suppressed unless there are >= 2 stacks.
  final bool canReorder;

  @override
  State<_StackCardRow> createState() => _StackCardRowState();
}

class _StackCardRowState extends State<_StackCardRow> {
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

  StackCardPosition get _position {
    if (widget.isFirst && widget.isLast) return StackCardPosition.only;
    if (widget.isFirst) return StackCardPosition.first;
    if (widget.isLast) return StackCardPosition.last;
    return StackCardPosition.middle;
  }

  @override
  Widget build(BuildContext context) {
    final card = Builder(
      // Selecting the rate here (not further up) confines the per-tick rebuild
      // to this card's subtree.
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
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => StackDetailScreen(stackId: widget.stack.id),
            ),
          );
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
      position: _position,
      isLast: widget.isLast,
    );
  }
}

/// One row of the stacks group: a stack card plus the hairline divider drawn
/// below it (omitted on the last row, which has a rounded bottom edge instead).
/// Shared by stack cards and the trailing portfolio-total card so both render
/// identically inside the same group.
class _GroupedCardRow extends StatelessWidget {
  const _GroupedCardRow({
    required this.card,
    required this.position,
    required this.isLast,
  });

  final Widget card;
  final StackCardPosition position;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: cs.surfaceContainerLow),
          child: card,
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
