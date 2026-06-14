import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/app_haptics.dart';
import '../theme/theme.dart';
import 'menu_action_tile.dart';

/// The edit/rename/delete actions available for a stack, shared between the
/// home card flow and the stack detail screen so both present an identical
/// menu and confirmation dialog.
enum StackAction { edit, rename, delete }

/// Shows the stack actions bottom sheet (Update amount / Change name / Delete)
/// for the stack named [stackName]. Returns the chosen action, or null if
/// dismissed. The caller performs the navigation/deletion.
Future<StackAction?> showStackActionsSheet(
  BuildContext context,
  String stackName,
) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return showModalBottomSheet<StackAction>(
    context: context,
    backgroundColor: theme.brightness == Brightness.dark
        ? cs.surfaceContainerHigh
        : cs.surfaceContainerLow,
    showDragHandle: true,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MenuSheetHeader(stackName),
              MenuActionGroup(
                children: [
                  MenuActionTile(
                    leading: const Text(
                      '₿',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    label: l10n.stackMenuUpdateAmount,
                    onTap: () => Navigator.of(ctx).pop(StackAction.edit),
                  ),
                  MenuActionTile(
                    leading: const Icon(Icons.edit_outlined),
                    label: l10n.stackMenuChangeName,
                    onTap: () => Navigator.of(ctx).pop(StackAction.rename),
                  ),
                  MenuActionTile(
                    leading: const Icon(Icons.delete_outline),
                    label: l10n.stackMenuDelete,
                    destructive: true,
                    onTap: () => Navigator.of(ctx).pop(StackAction.delete),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Confirmation dialog for deleting a stack. Returns true if the user confirms.
Future<bool?> showDeleteStackDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: appDialogBarrierColor(context),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      final cs = Theme.of(ctx).colorScheme;
      return Dialog(
        backgroundColor: cs.surface,
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
                l10n.dialogDeleteStackTitle,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.dialogDeleteStackBody,
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
                    textStyle:
                        AppTypography.title.copyWith(fontWeight: FontWeight.w500),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                    ),
                  ),
                  child: Text(l10n.dialogDeleteStackConfirm),
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
                    textStyle:
                        AppTypography.title.copyWith(fontWeight: FontWeight.w500),
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
