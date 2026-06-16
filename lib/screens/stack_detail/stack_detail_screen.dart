import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/fiat.dart';
import '../../data/sats.dart';
import '../../data/app_enums.dart';
import '../../data/stack.dart' as model;
import '../../l10n/generated/app_localizations.dart';
import '../../screens/settings/stacks_settings_actions.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/stack_actions.dart';
import '../../widgets/stack_avatar.dart';
import '../edit_stack_screens.dart';
import 'future_value_slider.dart';
import 'stack_detail_shared.dart';


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
        if (!mounted) return;
        final confirm = await showDeleteStackDialog(context);
        if (!mounted) return;
        if (confirm == true) {
          final app = context.read<AppStateNotifier>();
          final wasLast = app.stacks.length == 1;
          app.removeStack(stack.id);
          // Deleting the final stack auto-disables the lock, mirroring a manual
          // turn-off — there's nothing left to protect, and the user shouldn't
          // be greeted by a lock screen guarding an empty list next launch.
          if (wasLast && mounted) {
            await StacksSettingsActions.disableLockForEmptyStacks(context, app);
          }
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
          PastValuesSection(currency: currency, btcAmount: btcAmount),
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
    final btcDisplayMode = context.select<AppStateNotifier, BtcDisplayMode>(
      (app) => app.state.btcDisplayMode,
    );
    final value = Sats.toFiat(stack.sats, liveRate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: AppSpacing.sm),
        GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => EditStackAmountScreen(stackId: stackId),
          )),
          child: Text(
            formatBtcAmount(stack.sats,
                hidden: stack.isHidden, mode: btcDisplayMode, tight: true),
            textAlign: TextAlign.center,
            style: AppTypography.display.copyWith(
              fontSize: 44,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              color: context.palette.bitcoinOrange,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          formatFiat(value, currency, decimalsUnder10: true).tight,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.body.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: cs.onSurfaceVariant,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
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
    final initial = savedPrice;

    return DetailSection(
      verticalPadding: AppSpacing.lg,
      // Rebuild the slider's initial position when the restored price changes
      // (currency switch restoring a different saved value) so it re-seeds.
      child: FutureValueSlider(
        key: ValueKey('$stackId|$initial'),
        btcAmount: btcAmount,
        currency: currency,
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
}

