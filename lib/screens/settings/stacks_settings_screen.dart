import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import '../new_stack_screens.dart';
import 'settings_dialogs.dart';
import 'settings_widgets.dart';
import 'lock_stacks_settings_screen.dart';
import 'reorder_stacks_screen.dart';

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
                SettingsPickerTile(
                  label: l10n.settingsLockStacks,
                  value: authModeLabel(l10n, app.stacksAuthMode),
                  onTap: () {
                    if (app.stacksAuthMode == StacksAuthMode.off) {
                      // Skip the Lock-settings sub-screen when no mode is active —
                      // there's nothing to configure yet; jump straight to the
                      // mode picker.
                      LockStacksSettingsScreen.openModePicker(context, app);
                    } else {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const LockStacksSettingsScreen(),
                        ),
                      );
                    }
                  },
                  trailingIcon: app.stacksAuthMode == StacksAuthMode.off
                      ? Icons.unfold_more
                      : Icons.chevron_right,
                ),
                if (!lock.isLocked)
                  SettingsPickerTile(
                    label: l10n.settingsReorderStacks,
                    value: '',
                    enabled: app.stacks.isNotEmpty,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReorderStacksScreen(),
                      ),
                    ),
                    trailingIcon: Icons.chevron_right,
                  ),
                SettingsToggleTile(
                  label: l10n.settingsShowStackImages,
                  value: app.showStackImages,
                  enabled: true,
                  onChanged: (v) => app.setShowStackImages(v),
                ),
                if (canShowTotal)
                  SettingsToggleTile(
                    label: l10n.settingsPortfolioTotal,
                    value: app.showPortfolio,
                    enabled: true,
                    onChanged: (v) => app.setShowPortfolio(v),
                  ),
              ],
            ),
            if (!lock.isLocked) ...[
              const SizedBox(height: AppSpacing.lg),
              SettingsGroup(
                children: [
                  SettingsPickerTile(
                    label: l10n.homeAddStack,
                    value: '',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const NewStackAmountScreen(),
                      ),
                    ),
                    trailingIcon: Icons.add,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
