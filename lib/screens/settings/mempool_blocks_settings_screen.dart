import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import 'settings_widgets.dart';

class MempoolBlocksSettingsScreen extends StatelessWidget {
  const MempoolBlocksSettingsScreen({super.key});

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
          l10n.settingsMempoolBlocksTitle,
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
                SettingsToggleTile(
                  label: l10n.settingsMempoolBlocksVisible,
                  value: app.showMempool,
                  enabled: true,
                  onChanged: app.setShowMempool,
                ),
                SettingsToggleTile(
                  label: l10n.settingsMempoolBlocksReverseOrder,
                  value: app.mempoolBlocksReversed,
                  enabled: app.showMempool,
                  onChanged: app.setMempoolBlocksReversed,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
