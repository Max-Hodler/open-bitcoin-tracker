import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import 'settings_widgets.dart';
import 'currency_picker_screen.dart';

class BtcPriceSettingsScreen extends StatelessWidget {
  const BtcPriceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateNotifier>();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: cs.onSurfaceVariant),
        centerTitle: true,
        title: Text(
          l10n.settingsBtcPriceTitle,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: ScrollHairline(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl * 2,
          ),
          children: [
            _SectionHeader(label: l10n.settingsPriceTickerSection),
            SettingsGroup(
              children: [
                SettingsPickerTile(
                  label: l10n.settingsCurrencies,
                  value: '',
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
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader(label: l10n.settingsChartSection),
            SettingsGroup(
              children: [
                SettingsToggleTile(
                  label: l10n.settingsChart,
                  value: app.showChart,
                  enabled: true,
                  onChanged: app.setShowChart,
                ),
                SettingsSegmentedTile(
                  label: l10n.settingsChartHeight,
                  options: [
                    l10n.settingsChartHeightCompact,
                    l10n.settingsChartHeightNormal,
                    l10n.settingsChartHeightTall,
                  ],
                  selectedIndex: app.chartHeight.index,
                  enabled: app.showChart,
                  onChanged: (i) => app.setChartHeight(ChartHeight.values[i]),
                ),
                SettingsSegmentedTile(
                  label: l10n.settingsScale,
                  options: [l10n.settingsScaleLinear, l10n.settingsScaleLog],
                  selectedIndex: app.logScale ? 1 : 0,
                  enabled: app.showChart,
                  onChanged: (i) => app.setLogScale(i == 1),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(
        label,
        style: AppTypography.body.copyWith(
          fontSize: 16,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
