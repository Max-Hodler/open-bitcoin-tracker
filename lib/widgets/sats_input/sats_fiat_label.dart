import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../data/sats.dart';
import '../../format/fiat.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';

/// Live fiat readout that sits below [SatsInputDisplay]. While the user types,
/// converts the current sats / BTC raw value to the selected fiat using the
/// live BTC price; on empty input falls back to a localized hint string.
class SatsFiatLabel extends StatelessWidget {
  const SatsFiatLabel({super.key, required this.input, required this.mode});

  final String input;
  final BtcDisplayMode mode;

  @override
  Widget build(BuildContext context) {
    final currency = context.select<AppStateNotifier, Currency>((a) => a.currency);
    final rate = context.select<LivePriceController, double?>(
          (c) => c.rates.forCurrency(currency),
        ) ??
        0;
    final btcValue = mode == BtcDisplayMode.btc
        ? (double.tryParse(input) ?? 0)
        : (int.tryParse(input) ?? 0) / Sats.perBtc;
    final fiatValue = rate == 0 ? 0.0 : btcValue * rate;
    final symbol = currencySymbols[currency] ?? r'$';
    final showHint = input.isEmpty;
    final l10n = AppLocalizations.of(context);
    final label = showHint
        ? (mode == BtcDisplayMode.btc
            ? l10n.satsInputUnitHintBtc
            : l10n.satsInputUnitHint)
        : rate == 0
            ? ''
            : symbolAfterAmount
                ? '${formatDerivedFiatValue(fiatValue)}$symbol'
                : '$symbol${formatDerivedFiatValue(fiatValue)}';

    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 24,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: AppTypography.body.copyWith(
            fontSize: 18,
            color: cs.onSurfaceVariant,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
