import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import 'settings_dialogs.dart';
import 'settings_widgets.dart';
import 'stacks_settings_actions.dart';

/// Bottom sheet holding the stack-lock controls (enable/disable, auth type,
/// re-lock timeout, change/reset PIN). Opened from the home overflow menu's
/// "Lock stacks" entry and from the Stacks settings screen. All actions
/// delegate to [StacksSettingsActions] so the encryption-sensitive transitions
/// stay in one place.
///
/// The body is a [Consumer] so the sheet reflows in place when the auth mode
/// changes — enabling the lock swaps the single "Enable lock" button for the
/// full control list without the sheet having to close and reopen.
Future<void> showStackLockSettingsSheet(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.brightness == Brightness.dark
        ? cs.surfaceContainerHigh
        : cs.surfaceContainerLow,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: Consumer<AppStateNotifier>(
            builder: (ctx, app, _) {
              final mode = app.stacksAuthMode;
              final isOn = mode != StacksAuthMode.off;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: AppSpacing.xs,
                      bottom: isOn ? AppSpacing.md : AppSpacing.xs,
                    ),
                    child: Text(
                      isOn ? l10n.settingsLockStacksTitle : l10n.settingsLockStacksSetupTitle,
                      style: AppTypography.label.copyWith(
                        fontSize: 18,
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!isOn) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xs,
                        0,
                        AppSpacing.xs,
                        AppSpacing.md,
                      ),
                      child: Text(
                        l10n.settingsEnableLockHint,
                        style: AppTypography.body.copyWith(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SettingsGroup(
                      children: [
                        for (final m in StacksAuthMode.values
                            .where((m) => m != StacksAuthMode.off))
                          AuthModeRow(
                            key: ValueKey('stacksAuthMode-${m.code}'),
                            mode: m,
                            onTap: () => StacksSettingsActions.selectMode(
                                ctx, app, m),
                          ),
                      ],
                    ),
                  ]
                  else ...[
                    SettingsGroup(
                      children: [
                        SettingsActionTile(
                          label: l10n.settingsDisableLock,
                          onTap: () =>
                              StacksSettingsActions.turnOffLock(ctx, app),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SettingsGroup(
                      children: [
                        SettingsPickerTile(
                          label: l10n.settingsAuthType,
                          value: authModeLabel(l10n, mode),
                          onTap: () =>
                              StacksSettingsActions.openModePicker(ctx, app),
                        ),
                        if (mode == StacksAuthMode.pin)
                          SettingsActionTile(
                            label: l10n.settingsChangePin,
                            onTap: () =>
                                StacksSettingsActions.changePin(ctx),
                          ),
                        SettingsPickerTile(
                          label: l10n.settingsRelockAfter,
                          value:
                              lockTimeoutLabel(l10n, app.stacksLockTimeout),
                          onTap: () => StacksSettingsActions.openTimeoutPicker(
                              ctx, app),
                        ),
                      ],
                    ),
                    if (mode == StacksAuthMode.pin) ...[
                      const SizedBox(height: AppSpacing.md),
                      SettingsGroup(
                        children: [
                          SettingsActionTile(
                            label: l10n.settingsResetStacksLock,
                            onTap: () =>
                                StacksSettingsActions.forgetPin(ctx, app),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
