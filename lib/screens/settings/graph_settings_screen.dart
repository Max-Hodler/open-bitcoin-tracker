import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import 'settings_widgets.dart';

class GraphSettingsScreen extends StatelessWidget {
  const GraphSettingsScreen({super.key});

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
          l10n.settingsGraphTitle,
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
            SettingsGroup(
              children: [
                SettingsSegmentedTile(
                  label: l10n.settingsChartHeight,
                  options: [
                    l10n.settingsChartHeightCompact,
                    l10n.settingsChartHeightNormal,
                    l10n.settingsChartHeightTall,
                    l10n.settingsChartHeightXl,
                  ],
                  selectedIndex: app.chartHeight.index,
                  enabled: true,
                  onChanged: (i) => app.setChartHeight(ChartHeight.values[i]),
                ),
                SettingsSegmentedTile(
                  label: l10n.settingsScale,
                  options: [l10n.settingsScaleLinear, l10n.settingsScaleLog],
                  selectedIndex: app.logScale ? 1 : 0,
                  enabled: true,
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
