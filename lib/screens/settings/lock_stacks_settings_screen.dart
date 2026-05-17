import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/stacks_auth_service.dart';
import '../../services/stacks_unlock_orchestrator.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';
import '../pin_entry_screen.dart';
import '_dialogs.dart';
import '_widgets.dart';

class LockStacksSettingsScreen extends StatelessWidget {
  const LockStacksSettingsScreen({super.key});

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
          l10n.settingsLockStacks,
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
            SettingsPickerTile(
              label: l10n.settingsAuthType,
              value: authModeLabel(l10n, mode),
              onTap: () => openModePicker(context, app),
            ),
            if (isOn) ...[
              const SizedBox(height: AppSpacing.xs),
              SettingsPickerTile(
                label: l10n.settingsRelockAfter,
                value: lockTimeoutLabel(l10n, app.stacksLockTimeout),
                onTap: () => _openTimeoutPicker(context, app),
              ),
            ],
            if (mode == StacksAuthMode.pin) ...[
              const SizedBox(height: AppSpacing.xs),
              SettingsActionTile(
                label: l10n.settingsChangePin,
                onTap: () => _changePin(context),
              ),
            ],
            if (isOn) ...[
              const SizedBox(height: AppSpacing.xs),
              SettingsActionTile(
                label: l10n.settingsTurnOffLock,
                onTap: () => _turnOffLock(context, app),
              ),
            ],
            if (mode == StacksAuthMode.pin) ...[
              const SizedBox(height: AppSpacing.xs),
              SettingsActionTile(
                label: l10n.settingsResetStacksLock,
                onTap: () => _forgetPin(context, app),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Entry point exposed for [StacksSettingsScreen] so it can open the picker
  /// directly when the user toggles auth on from "off" (skipping this screen).
  static Future<void> openModePicker(
    BuildContext context,
    AppStateNotifier app,
  ) async {
    final picked = await showAuthModePicker(context, app.stacksAuthMode);
    if (picked == null || picked == app.stacksAuthMode) return;
    if (!context.mounted) return;
    await _applyModeChange(context, app, app.stacksAuthMode, picked);
  }

  Future<void> _openTimeoutPicker(
    BuildContext context,
    AppStateNotifier app,
  ) async {
    final picked = await showTimeoutPicker(context, app.stacksLockTimeout);
    if (picked == null) return;
    app.setStacksLockTimeout(picked);
  }

  static Future<void> _turnOffLock(
    BuildContext context,
    AppStateNotifier app,
  ) async {
    final navigator = Navigator.of(context);
    await _applyModeChange(context, app, app.stacksAuthMode, StacksAuthMode.off);
    if (app.stacksAuthMode == StacksAuthMode.off && navigator.canPop()) {
      navigator.pop();
    }
  }

  /// Coordinates an auth-mode transition: re-auth where needed, swap wraps via
  /// the orchestrator, and update the notifier on success. Each branch covers
  /// one (current → next) pair so a misroute simply does nothing.
  static Future<void> _applyModeChange(
    BuildContext context,
    AppStateNotifier app,
    StacksAuthMode current,
    StacksAuthMode next,
  ) async {
    final service = context.read<StacksAuthService>();
    final orch = context.read<StacksUnlockOrchestrator>();

    // any → off: re-auth (which also gives us the DEK), decrypt-back, wipe.
    if (next == StacksAuthMode.off) {
      final ok = await _reauthenticate(context, current);
      if (!ok || !context.mounted) return;
      await orch.switchToOff();
      app.setStacksAuthMode(StacksAuthMode.off);
      return;
    }

    // → device
    if (next == StacksAuthMode.device) {
      final available = await service.isDeviceAuthAvailable();
      if (!context.mounted) return;
      if (!available) {
        await showDeviceUnavailableDialog(context);
        return;
      }
      if (current == StacksAuthMode.off) {
        // First-time setup: prompt biometric and mint a DEK.
        final outcome = await orch.migrateOrInitDeviceMode();
        if (!context.mounted) return;
        if (outcome != UnlockOutcome.success) {
          await showBiometricNotEnrolledDialog(context);
          return;
        }
        app.setStacksAuthMode(StacksAuthMode.device);
        return;
      }
      // pin → device: re-auth via PIN to obtain DEK, then add biometric wrap
      // and drop the PIN wrap.
      final ok = await _reauthenticate(context, current);
      if (!ok || !context.mounted) return;
      final dek = app.currentDek;
      if (dek == null) {
        // Defensive: re-auth should have populated the DEK. If it didn't,
        // we're in legacy plaintext mode and the transition can't happen.
        _toast(context, AppLocalizations.of(context).snackCouldNotEnableDeviceUnlock);
        return;
      }
      final bound = await orch.switchPinToDevice(dek);
      if (!context.mounted) return;
      if (!bound) {
        await showBiometricNotEnrolledDialog(context);
        return;
      }
      app.setStacksAuthMode(StacksAuthMode.device);
      return;
    }

    // → pin
    if (current == StacksAuthMode.device) {
      // device → pin: re-auth biometric to obtain DEK, then collect new PIN.
      final ok = await _reauthenticate(context, current);
      if (!ok || !context.mounted) return;
      final dek = app.currentDek;
      if (dek == null) {
        _toast(context, AppLocalizations.of(context).snackCouldNotSwitchToPin);
        return;
      }
      final newPin = await _promptForNewPin(context);
      if (newPin == null || !context.mounted) return;
      await orch.switchDeviceToPin(dek, newPin);
      app.setStacksAuthMode(StacksAuthMode.pin);
      return;
    }
    // off → pin: collect a PIN; the setup screen mints + adopts the DEK.
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => const PinEntryScreen.setup(),
      ),
    );
    if (result != true || !context.mounted) return;
    app.setStacksAuthMode(StacksAuthMode.pin);
  }

  static Future<bool> _reauthenticate(BuildContext context, StacksAuthMode mode) async {
    if (mode == StacksAuthMode.off) return true;
    if (mode == StacksAuthMode.device) {
      // Use the orchestrator so the biometric path also unwraps the DEK
      // into the notifier — needed by transitions that re-wrap it.
      final orch = context.read<StacksUnlockOrchestrator>();
      final outcome = await orch.unlockWithDevice();
      return outcome == UnlockOutcome.success;
    }
    // PIN re-auth: the verify screen calls the orchestrator on success, so
    // the DEK is in app.currentDek by the time we get back.
    final title = AppLocalizations.of(context).pinConfirmTitle;
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => PinEntryScreen.verify(title: title),
      ),
    );
    return result == true;
  }

  static Future<String?> _promptForNewPin(BuildContext context) async {
    return await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const PinEntryScreen.collect(),
      ),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => const PinEntryScreen.change(),
      ),
    );
  }

  Future<void> _forgetPin(BuildContext context, AppStateNotifier app) async {
    final confirmed = await showForgetPinDialog(context);
    if (confirmed != true || !context.mounted) return;
    await context.read<StacksUnlockOrchestrator>().resetEverything();
    app.setStacksAuthMode(StacksAuthMode.off);
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
