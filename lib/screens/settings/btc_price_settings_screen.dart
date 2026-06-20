import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import 'currency_picker_screen.dart';
import 'settings_widgets.dart';

class BtcPriceSettingsScreen extends StatelessWidget {
  const BtcPriceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateNotifier>();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final hPad = isLandscape ? 64.0 : AppSpacing.md;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56 + (hPad - AppSpacing.md),
        leading: Padding(
          padding: EdgeInsets.only(left: hPad - AppSpacing.md),
          child: BackButton(color: cs.onSurfaceVariant),
        ),
        centerTitle: true,
        titleSpacing: hPad,
        title: Text(
          l10n.settingsPriceTitle,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: ScrollHairline(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            hPad,
            AppSpacing.md,
            hPad,
            AppSpacing.xl * 2,
          ),
          children: [
            SettingsGroup(
              children: [
                SettingsPickerTile(
                  label: l10n.settingsCurrencies,
                  value: app.selectedCurrencies.map((c) => c.code).join(', '),
                  onTap: () => _openCurrencyPicker(context, app),
                  trailingIcon: Icons.chevron_right,
                ),
                SettingsPickerTile(
                  label: l10n.settingsLivePriceCadence,
                  value: _livePriceCadenceLabel(l10n, app.livePriceCadence),
                  onTap: () => _openLivePriceCadencePicker(context, app),
                  trailingIcon: Icons.unfold_more,
                ),
                SettingsToggleTile(
                  label: l10n.settingsPriceDelta,
                  value: app.showPriceDelta,
                  enabled: true,
                  onChanged: app.setShowPriceDelta,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openCurrencyPicker(
  BuildContext context,
  AppStateNotifier app,
) async {
  final picked = await Navigator.of(context).push<List<Currency>>(
    MaterialPageRoute(
      builder: (_) => CurrencyPickerScreen(initial: app.selectedCurrencies),
    ),
  );
  if (picked != null) app.setSelectedCurrencies(picked);
}

String _livePriceCadenceLabel(AppLocalizations l10n, LivePriceCadence c) {
  switch (c) {
    case LivePriceCadence.live:
      return l10n.livePriceCadenceLive;
    case LivePriceCadence.s5:
      return l10n.livePriceCadence5s;
    case LivePriceCadence.s15:
      return l10n.livePriceCadence15s;
  }
}

Future<void> _openLivePriceCadencePicker(
  BuildContext context,
  AppStateNotifier app,
) async {
  final picked =
      await _showLivePriceCadencePicker(context, app.livePriceCadence);
  if (picked != null) app.setLivePriceCadence(picked);
}

Future<LivePriceCadence?> _showLivePriceCadencePicker(
  BuildContext context,
  LivePriceCadence current,
) {
  return showDialog<LivePriceCadence>(
    context: context,
    barrierColor: appDialogBarrierColor(context),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return RadioGroup<LivePriceCadence>(
        groupValue: current,
        onChanged: (v) {
          AppHaptics.selection();
          Navigator.of(ctx).pop(v);
        },
        child: SimpleDialog(
          elevation: 24,
          shadowColor: Colors.black,
          title: Text(l10n.livePriceCadencePickerTitle),
          children: [
            for (final c in LivePriceCadence.values)
              RadioListTile<LivePriceCadence>(
                key: ValueKey('livePriceCadence-${c.code}'),
                title: Text(_livePriceCadenceLabel(l10n, c)),
                value: c,
              ),
          ],
        ),
      );
    },
  );
}
