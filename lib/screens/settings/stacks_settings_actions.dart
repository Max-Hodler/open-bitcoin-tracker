import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/stacks_auth_service.dart';
import '../../services/stacks_unlock_orchestrator.dart';
import '../../state/state.dart';
import '../pin_entry_screen.dart';
import 'reorder_stacks_screen.dart';
import 'settings_dialogs.dart';
import 'stack_lock_settings_screen.dart';

/// Shared handlers for the stacks-management and stack-lock actions.
///
/// Both [StacksSettingsScreen] and the home-screen stacks overflow menu drive
/// these, so the encryption-sensitive auth-mode transitions live in exactly one
/// place. Do not inline this logic into a caller — the DEK re-wrap sequencing in
/// [_applyModeChange] is load-bearing for keeping the on-disk envelope valid.
abstract final class StacksSettingsActions {
  static void openReorder(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ReorderStacksScreen()),
    );
  }

  static void openLockSettings(BuildContext context) {
    showStackLockSettingsSheet(context);
  }

  static Future<void> openModePicker(
    BuildContext context,
    AppStateNotifier app,
  ) async {
    final picked = await showAuthModePicker(context, app.stacksAuthMode);
    if (picked == null || picked == app.stacksAuthMode) return;
    if (!context.mounted) return;
    await _applyModeChange(context, app, app.stacksAuthMode, picked);
  }

  /// Apply a directly-chosen auth mode, skipping the picker dialog. Used by the
  /// lock settings sheet when the lock is off, where the two on-state options
  /// are offered inline so first-time setup is a single tap. Routes through the
  /// same [_applyModeChange] transition as [openModePicker].
  static Future<void> selectMode(
    BuildContext context,
    AppStateNotifier app,
    StacksAuthMode mode,
  ) async {
    if (mode == app.stacksAuthMode) return;
    await _applyModeChange(context, app, app.stacksAuthMode, mode);
  }

  static Future<void> openTimeoutPicker(
    BuildContext context,
    AppStateNotifier app,
  ) async {
    final picked = await showTimeoutPicker(context, app.stacksLockTimeout);
    if (picked == null) return;
    app.setStacksLockTimeout(picked);
  }

  static Future<void> turnOffLock(
    BuildContext context,
    AppStateNotifier app,
  ) async {
    await _applyModeChange(context, app, app.stacksAuthMode, StacksAuthMode.off);
  }

  /// Auto-disable the lock once the user has deleted their last stack, leaving
  /// the app in exactly the state it would be if they'd turned the lock off
  /// from settings. Unlike [turnOffLock] this skips re-auth: reaching the
  /// delete UI requires being unlocked, so the DEK is already in memory and the
  /// decrypt-back in [StacksUnlockOrchestrator.switchToOff] can run as-is.
  /// Asking the user to authenticate just to delete their final stack would be
  /// nonsensical. No-op unless the lock is currently active.
  static Future<void> disableLockForEmptyStacks(
    BuildContext context,
    AppStateNotifier app,
  ) async {
    if (app.stacksAuthMode == StacksAuthMode.off) return;
    final orch = context.read<StacksUnlockOrchestrator>();
    await orch.switchToOff();
    app.setStacksAuthMode(StacksAuthMode.off);
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

  static Future<bool> _reauthenticate(
    BuildContext context,
    StacksAuthMode mode,
  ) async {
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

  static Future<void> changePin(BuildContext context) async {
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => const PinEntryScreen.change(),
      ),
    );
  }

  static Future<void> forgetPin(BuildContext context, AppStateNotifier app) async {
    final confirmed = await showForgetPinDialog(context);
    if (confirmed != true || !context.mounted) return;
    await context.read<StacksUnlockOrchestrator>().resetEverything();
    app.setStacksAuthMode(StacksAuthMode.off);
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
