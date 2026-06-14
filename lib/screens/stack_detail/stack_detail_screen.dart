import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../data/fiat.dart';
import '../../data/sats.dart';
import '../../data/app_enums.dart';
import '../../data/stack.dart' as model;
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/stack_actions.dart';
import '../../widgets/stack_avatar.dart';
import '../edit_stack_screens.dart';
import 'future_value_slider.dart';

// "Worth back then" lookbacks, in years. All-time is appended separately.
const List<int> _kLookbackYears = [1, 3, 5];

/// Per-stack detail view: what the stack was worth at past dates and an
/// interactive "what if BTC reaches X" projection. Opened by tapping a stack
/// card on the home screen.
class StackDetailScreen extends StatefulWidget {
  const StackDetailScreen({super.key, required this.stackId});

  final String stackId;

  @override
  State<StackDetailScreen> createState() => _StackDetailScreenState();
}

class _StackDetailScreenState extends State<StackDetailScreen> {
  // Resolve the live stack from the notifier so an amount/name/avatar edit made
  // from the overflow menu reflects here on return without a manual refresh.
  model.Stack? _stackOf(AppStateNotifier app) {
    for (final s in app.stacks) {
      if (s.id == widget.stackId) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
        centerTitle: true,
        title: Text(
          stack.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
            onPressed: () => _showStackMenu(context, stack),
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
          _Header(stack: stack, currency: currency),
          const SizedBox(height: AppSpacing.xl),
          _PastValuesSection(currency: currency, btcAmount: btcAmount),
          const SizedBox(height: AppSpacing.xl),
          _FutureSection(currency: currency, btcAmount: btcAmount),
        ],
      ),
    );
  }

  Future<void> _showStackMenu(BuildContext context, model.Stack stack) async {
    final action = await showStackActionsSheet(context, stack.name);
    if (!context.mounted || action == null) return;
    switch (action) {
      case StackAction.edit:
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EditStackAmountScreen(stackId: stack.id),
        ));
      case StackAction.rename:
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EditStackNameScreen(stackId: stack.id),
        ));
      case StackAction.delete:
        final confirm = await showDeleteStackDialog(context);
        if (confirm == true && context.mounted) {
          context.read<AppStateNotifier>().removeStack(stack.id);
          // The build's null-stack guard pops us back home.
        }
    }
  }
}

/// Stack avatar + name + current fiat value and BTC amount.
class _Header extends StatelessWidget {
  const _Header({required this.stack, required this.currency});

  final model.Stack stack;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final liveRate = context.select<LivePriceController, double?>(
          (c) => c.rates.forCurrency(currency),
        ) ??
        0;
    final value = Sats.toFiat(stack.sats, liveRate);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        StackAvatar(
          name: stack.name,
          imageData: stack.imageData,
          colorKey: stack.colorKey,
          size: 56,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatFiat(value, currency, decimalsUnder10: true).full,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.display.copyWith(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: cs.onSurface,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatBtcAmount(stack.sats,
                    hidden: stack.isHidden, mode: BtcDisplayMode.btc),
                style: AppTypography.body.copyWith(
                  fontSize: 15,
                  color: cs.onSurfaceVariant,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Worth back then" — static rows mapping past dates to the stack's value
/// then. Pulled from the full converted all-history series via binary search.
class _PastValuesSection extends StatelessWidget {
  const _PastValuesSection({required this.currency, required this.btcAmount});

  final Currency currency;
  final double btcAmount;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LivePriceController>();
    final usdRate = controller.rates.usd ?? 0;
    final currentPrice = controller.rates.forCurrency(currency) ?? 0;
    final usdToCurrency = usdRate > 0 ? currentPrice / usdRate : 1.0;
    final history = controller.convertedAllHistory(
      currency: currency,
      usdToCurrencyFallback: usdToCurrency,
    );

    if (history.length < 2) return const SizedBox.shrink();

    final now = DateTime.now();
    final firstT = DateTime.fromMillisecondsSinceEpoch(history.first.t);
    final yearsOfHistory = now.year - firstT.year;
    final locale = Localizations.localeOf(context).toString();
    final dateFmt = DateFormat.yMMMd(locale);

    final rows = <_PastRow>[];
    for (final y in _kLookbackYears) {
      if (y > yearsOfHistory) continue;
      final at = DateTime(now.year - y, now.month, now.day);
      final price = _priceAt(history, at.millisecondsSinceEpoch);
      if (price == null) continue;
      rows.add(_PastRow(
        label: '$y ${y == 1 ? 'year' : 'years'} ago',
        sublabel: dateFmt.format(at),
        value: price * btcAmount,
      ));
    }
    // All-time: the very first data point.
    rows.add(_PastRow(
      label: 'All-time',
      sublabel: dateFmt.format(firstT),
      value: history.first.price * btcAmount,
    ));

    return _Section(
      title: 'Worth back then',
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const _RowDivider(),
            _ValueRow(
              label: rows[i].label,
              sublabel: rows[i].sublabel,
              value: rows[i].value,
              currency: currency,
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
  const _FutureSection({required this.currency, required this.btcAmount});

  final Currency currency;
  final double btcAmount;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LivePriceController>();
    final currentPrice = controller.rates.forCurrency(currency) ?? 0;
    final floor = currentPrice > 0 ? currentPrice : 100000.0;
    final ceiling = _ceilingFor(floor);
    final initial = _initialFor(floor, ceiling);

    return _Section(
      title: 'If Bitcoin reaches…',
      child: FutureValueSlider(
        btcAmount: btcAmount,
        currency: currency,
        minPrice: floor,
        maxPrice: ceiling,
        initialPrice: initial,
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

  // Start the thumb a few× above today so the projection is immediately
  // interesting rather than parked at break-even.
  static double _initialFor(double floor, double ceiling) =>
      (floor * 3).clamp(floor, ceiling);
}

// ---- shared building blocks ----

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            title,
            style: AppTypography.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
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
          Text(
            formatFiat(value, currency, decimalsUnder10: true).full,
            style: AppTypography.body.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
              color: cs.onSurface.withValues(alpha: 0.9),
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
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
