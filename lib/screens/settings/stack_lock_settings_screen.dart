import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import 'settings_dialogs.dart';
import 'settings_widgets.dart';
import 'stacks_settings_actions.dart';

/// Dedicated screen for the stack-lock controls (enable, auth type, re-lock
/// timeout, change/reset PIN). Reached from the home overflow menu's "Lock
/// stacks" entry and from the Stacks settings screen. All actions delegate to
/// [StacksSettingsActions] so the encryption-sensitive transitions stay in one
/// place.
class StackLockSettingsScreen extends StatelessWidget {
  const StackLockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateNotifier>();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final mode = app.stacksAuthMode;
    final isOn = mode != StacksAuthMode.off;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(color: cs.onSurfaceVariant),
        centerTitle: true,
        title: Text(
          l10n.settingsLockStacksTitle,
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
                  label: l10n.settingsLockEnabled,
                  value: isOn,
                  enabled: true,
                  onChanged: (v) => v
                      ? StacksSettingsActions.openModePicker(context, app)
                      : StacksSettingsActions.turnOffLock(context, app),
                ),
                if (isOn) ...[
                  SettingsPickerTile(
                    label: l10n.settingsAuthType,
                    value: authModeLabel(l10n, mode),
                    onTap: () =>
                        StacksSettingsActions.openModePicker(context, app),
                  ),
                  if (mode == StacksAuthMode.pin)
                    SettingsActionTile(
                      label: l10n.settingsChangePin,
                      onTap: () => StacksSettingsActions.changePin(context),
                    ),
                  SettingsPickerTile(
                    label: l10n.settingsRelockAfter,
                    value: lockTimeoutLabel(l10n, app.stacksLockTimeout),
                    onTap: () =>
                        StacksSettingsActions.openTimeoutPicker(context, app),
                  ),
                ],
              ],
            ),
            if (mode == StacksAuthMode.pin) ...[
              const SizedBox(height: AppSpacing.md),
              SettingsActionTile(
                label: l10n.settingsResetStacksLock,
                onTap: () => StacksSettingsActions.forgetPin(context, app),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
