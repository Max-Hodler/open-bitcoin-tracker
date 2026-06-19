import 'package:flutter/material.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../theme/theme.dart';
import '../../widgets/menu_icon_square.dart';
import '../../widgets/orange_primary_button.dart';

String authModeLabel(AppLocalizations l10n, StacksAuthMode m) {
  switch (m) {
    case StacksAuthMode.off:
      return l10n.authModeOff;
    case StacksAuthMode.device:
      return l10n.authModeDevice;
    case StacksAuthMode.pin:
      return l10n.authModePin;
  }
}

IconData _authModeIcon(StacksAuthMode m) {
  switch (m) {
    case StacksAuthMode.off:
      return Icons.lock_open;
    case StacksAuthMode.device:
      return Icons.fingerprint;
    case StacksAuthMode.pin:
      return Icons.pin;
  }
}

/// Selectable list row for an auth mode: orange leading icon, label, and a
/// trailing chevron. Tapping commits the choice. Used both by the change-mode
/// dialog ([showAuthModePicker]) and inline in the lock settings sheet when the
/// lock is still off, so first-time setup can pick a mode without the extra
/// dialog hop.
class AuthModeRow extends StatelessWidget {
  const AuthModeRow({
    super.key,
    required this.mode,
    required this.onTap,
  });

  final StacksAuthMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppSpacing.radius);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              MenuIconSquare(
                icon: Icon(_authModeIcon(mode), size: 22, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  authModeLabel(l10n, mode),
                  style: AppTypography.title.copyWith(
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String lockTimeoutLabel(AppLocalizations l10n, StacksLockTimeout t) {
  switch (t) {
    case StacksLockTimeout.s30:
      return l10n.lockTimeoutSeconds(30);
    case StacksLockTimeout.m1:
      return l10n.lockTimeoutMinutes(1);
    case StacksLockTimeout.m5:
      return l10n.lockTimeoutMinutes(5);
    case StacksLockTimeout.never:
      return l10n.lockTimeoutNever;
  }
}

/// Picker dialog that lists the on-states (pin, device) so the user can pick
/// or swap which auth mode locks their stacks. Off is excluded — turning the
/// lock off goes through the dedicated [SettingsActionTile] so we can confirm
/// destructively.
Future<StacksAuthMode?> showAuthModePicker(
  BuildContext context,
  StacksAuthMode current,
) {
  return showDialog<StacksAuthMode>(
    context: context,
    barrierColor: appDialogBarrierColor(context),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return Dialog(
        elevation: 24,
        shadowColor: Colors.black,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.settingsAuthType,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              for (final m in StacksAuthMode.values
                  .where((m) => m != StacksAuthMode.off)
                  .toList()
                  .asMap()
                  .entries) ...[
                if (m.key > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                  ),
                AuthModeRow(
                  key: ValueKey('stacksAuthMode-${m.value.code}'),
                  mode: m.value,
                  onTap: () => Navigator.of(ctx).pop(m.value),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<StacksLockTimeout?> showTimeoutPicker(
  BuildContext context,
  StacksLockTimeout current,
) {
  return showDialog<StacksLockTimeout>(
    context: context,
    barrierColor: appDialogBarrierColor(context),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return Dialog(
        elevation: 24,
        shadowColor: Colors.black,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.settingsRelockAfter,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              for (final t in StacksLockTimeout.values) ...[
                OrangePrimaryButton(
                  key: ValueKey('stacksLockTimeout-${t.code}'),
                  isValid: true,
                  label: lockTimeoutLabel(l10n, t),
                  height: 52,
                  onTap: () {
                    AppHaptics.selection();
                    Navigator.of(ctx).pop(t);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showBiometricNotEnrolledDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      final cs = Theme.of(ctx).colorScheme;
      return Dialog(
        backgroundColor: cs.surface,
        elevation: 24,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.dialogNoBiometricTitle,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.dialogNoBiometricBody,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    AppHaptics.light();
                    Navigator.of(ctx).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.outlineVariant,
                    foregroundColor: cs.onSurface,
                    textStyle: AppTypography.title.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                    ),
                  ),
                  child: Text(l10n.buttonOk),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showDeviceUnavailableDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      final cs = Theme.of(ctx).colorScheme;
      final p = ctx.palette;
      return Dialog(
        backgroundColor: cs.surface,
        elevation: 24,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.dialogDeviceUnavailableTitle,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.dialogDeviceUnavailableBody,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    AppHaptics.light();
                    Navigator.of(ctx).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: p.bitcoinOrange,
                    foregroundColor: Colors.white,
                    textStyle: AppTypography.title.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                    ),
                  ),
                  child: Text(l10n.buttonOk),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<bool?> showForgetPinDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      final cs = Theme.of(ctx).colorScheme;
      return Dialog(
        backgroundColor: cs.surface,
        elevation: 24,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.dialogForgetPinTitle,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.dialogForgetPinBody,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    AppHaptics.light();
                    Navigator.of(ctx).pop(true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: Colors.white,
                    textStyle: AppTypography.title.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                    ),
                  ),
                  child: Text(l10n.dialogForgetPinConfirm),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    AppHaptics.light();
                    Navigator.of(ctx).pop(false);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.outlineVariant,
                    foregroundColor: cs.onSurface,
                    textStyle: AppTypography.title.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                    ),
                  ),
                  child: Text(l10n.buttonCancel),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
