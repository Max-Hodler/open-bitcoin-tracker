import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import 'settings_widgets.dart';
import 'stacks_settings_actions.dart';

class StacksSettingsScreen extends StatelessWidget {
  const StacksSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateNotifier>();
    final lock = context.watch<StacksLockController>();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final canShowTotal = app.stacks.length >= 2;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: cs.onSurfaceVariant),
        centerTitle: true,
        title: Text(
          l10n.settingsGroupPrivacy,
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
                if (!lock.isLocked && app.stacks.length > 1)
                  SettingsPickerTile(
                    label: l10n.settingsReorderStacks,
                    value: '',
                    enabled: true,
                    onTap: () => StacksSettingsActions.openReorder(context),
                    trailingIcon: Icons.chevron_right,
                  ),
                if (!lock.isLocked && canShowTotal)
                  SettingsToggleTile(
                    label: l10n.settingsPortfolioTotal,
                    value: app.showPortfolio,
                    enabled: true,
                    onChanged: (v) => app.setShowPortfolio(v),
                  ),
                SettingsPickerTile(
                  label: l10n.settingsLockStacksTitle,
                  value: '',
                  enabled: true,
                  onTap: () => StacksSettingsActions.openLockSettings(context),
                  trailingIcon: Icons.chevron_right,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
