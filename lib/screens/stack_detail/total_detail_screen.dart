import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/fiat.dart';
import '../../data/sats.dart';
import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/stack_avatar.dart';
import 'future_value_slider.dart';
import 'stack_detail_shared.dart';

/// Detail view for the aggregate portfolio total — shows what the combined
/// portfolio was worth at past dates and an interactive future-value projection.
/// Opened by tapping the total card on the home screen.
class TotalDetailScreen extends StatelessWidget {
  const TotalDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final app = context.watch<AppStateNotifier>();
    final currency = app.currency;
    final totalSats = app.stacks.fold<int>(0, (sum, s) => sum + s.sats);
    final btcAmount = totalSats / Sats.perBtc;
    final btcDisplayMode = app.btcDisplayMode;

    final initial = app.state.totalProjectedPriceCurrency == currency.code
        ? app.state.totalProjectedPrice
        : null;

    final liveRate = context.select<LivePriceController, double?>(
          (c) => c.rates.forCurrency(currency),
        ) ??
        0;
    final value = Sats.toFiat(totalSats, liveRate);

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
        title: Row(
          children: [
            StackAvatar(
              name: l10n.totalCardName,
              imageData: app.state.totalImageData,
              colorKey: app.state.totalColorKey ?? 'grey',
              size: 36,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.totalCardName,
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl * 2,
        ),
        children: [
          _TotalHeader(
            totalSats: totalSats,
            value: value,
            currency: currency,
            btcDisplayMode: btcDisplayMode,
          ),
          const SizedBox(height: AppSpacing.xl),
          PastValuesSection(currency: currency, btcAmount: btcAmount),
          const SizedBox(height: AppSpacing.xl),
          DetailSection(
            verticalPadding: AppSpacing.lg,
            child: FutureValueSlider(
              key: ValueKey('total|$initial'),
              btcAmount: btcAmount,
              currency: currency,
              initialPrice: initial,
              onPriceSelected: (price) {
                context
                    .read<AppStateNotifier>()
                    .setTotalProjectedPrice(price, currency.code);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalHeader extends StatelessWidget {
  const _TotalHeader({
    required this.totalSats,
    required this.value,
    required this.currency,
    required this.btcDisplayMode,
  });

  final int totalSats;
  final double value;
  final Currency currency;
  final BtcDisplayMode btcDisplayMode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: AppSpacing.sm),
        BtcAmountDisplay(
          sats: totalSats,
          mode: btcDisplayMode,
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
