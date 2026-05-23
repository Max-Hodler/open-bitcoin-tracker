import 'package:flutter/material.dart';

import '../../data/app_enums.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../theme/theme.dart';

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
      return RadioGroup<StacksAuthMode>(
        groupValue: current,
        onChanged: (v) {
          AppHaptics.selection();
          Navigator.of(ctx).pop(v);
        },
        child: SimpleDialog(
          elevation: 24,
          shadowColor: Colors.black,
          title: Text(l10n.settingsAuthType),
          children: [
            for (final m in StacksAuthMode.values)
              if (m != StacksAuthMode.off)
                RadioListTile<StacksAuthMode>(
                  key: ValueKey('stacksAuthMode-${m.code}'),
                  title: Text(authModeLabel(l10n, m)),
                  value: m,
                ),
          ],
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
      return RadioGroup<StacksLockTimeout>(
        groupValue: current,
        onChanged: (v) {
          AppHaptics.selection();
          Navigator.of(ctx).pop(v);
        },
        child: SimpleDialog(
          elevation: 24,
          shadowColor: Colors.black,
          title: Text(l10n.settingsRelockAfter),
          children: [
            for (final t in StacksLockTimeout.values)
              RadioListTile<StacksLockTimeout>(
                key: ValueKey('stacksLockTimeout-${t.code}'),
                title: Text(lockTimeoutLabel(l10n, t)),
                value: t,
              ),
          ],
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
