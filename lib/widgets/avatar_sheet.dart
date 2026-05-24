import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/stack_avatar_color.dart';
import '../l10n/generated/app_localizations.dart';
import '../screens/crop_stack_image_screen.dart';
import '../services/app_haptics.dart';
import '../services/stack_image_service.dart';
import '../theme/theme.dart';
import 'menu_action_tile.dart';

/// Open the avatar bottom sheet — used both by per-stack cards and by the
/// portfolio-total card. The sheet doesn't know what it's editing; it just
/// hands new color/image values back through the callbacks.
///
/// - [title] renders at the top (typically the stack/total name).
/// - [currentImageData] / [currentColorKey] drive which swatch is "selected"
///   and whether the "Remove image" row shows up.
/// - [onColorSet] is called with the chosen palette key, or null for the
///   default. The sheet closes itself before invoking the callback.
/// - [onImageSet] receives the final base64-encoded JPEG after pick + crop
///   + downscale. Not called on cancel/failure.
/// - [onImageCleared] is fired when the user taps "Remove image".
Future<void> showAvatarSheet(
  BuildContext context, {
  required String title,
  required String? currentImageData,
  required String? currentColorKey,
  required ValueChanged<String?> onColorSet,
  required ValueChanged<String> onImageSet,
  required VoidCallback onImageCleared,
}) async {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final hasImage = currentImageData != null;
  final action = await showModalBottomSheet<_AvatarSheetAction>(
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AvatarSheetHeader(
                title: title,
                subtitle: hasImage ? null : l10n.stackImageSheetSubtitle,
              ),
              if (!hasImage) ...[
                _AvatarColorRow(
                  selectedKey: currentColorKey,
                  onPick: (key) {
                    Navigator.of(ctx).pop();
                    AppHaptics.selection();
                    onColorSet(key);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _AvatarSectionLabel(l10n.stackImageSectionLabel),
              const SizedBox(height: AppSpacing.sm),
              MenuActionGroup(
                children: [
                  MenuActionTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    label: hasImage
                        ? l10n.stackImageChangeFromGallery
                        : l10n.stackImageChooseFromGallery,
                    onTap: () => Navigator.of(ctx)
                        .pop(_AvatarSheetAction.pickFromGallery),
                  ),
                  if (hasImage)
                    MenuActionTile(
                      leading: const Icon(Icons.delete_outline),
                      label: l10n.stackImageRemove,
                      destructive: true,
                      onTap: () =>
                          Navigator.of(ctx).pop(_AvatarSheetAction.remove),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted) return;
  switch (action) {
    case _AvatarSheetAction.pickFromGallery:
      try {
        final picked = await pickStackImageBytes();
        if (!context.mounted) return;
        if (picked == null) return;
        final cropped = await Navigator.of(context).push<Uint8List?>(
          MaterialPageRoute(
            builder: (_) => CropStackImageScreen(imageBytes: picked),
          ),
        );
        if (!context.mounted) return;
        if (cropped == null) return;
        final base64 = await processCroppedStackImage(cropped);
        if (!context.mounted) return;
        onImageSet(base64);
      } on StackImagePickFailure {
        if (!context.mounted) return;
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.stackImagePickFailed)),
        );
      }
    case _AvatarSheetAction.remove:
      onImageCleared();
    case null:
      break;
  }
}

enum _AvatarSheetAction { pickFromGallery, remove }

class _AvatarSheetHeader extends StatelessWidget {
  const _AvatarSheetHeader({required this.title, this.subtitle});

  final String title;
  // Null hides the subtitle (e.g. when the swatch row is also hidden because
  // the user has set an image — the title-only header reads cleaner there).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.92,
              child: Text(
                title,
                style: AppTypography.label.copyWith(
                  fontSize: 18,
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvatarColorRow extends StatelessWidget {
  const _AvatarColorRow({required this.selectedKey, required this.onPick});

  final String? selectedKey;
  final void Function(String? key) onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = StackAvatarColor.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AvatarSectionLabel(l10n.stackImageColorLabel),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < entries.length; i++)
                _ColorSwatch(
                  color: entries[i].color,
                  // First entry == default == stored as null.
                  selected: i == 0
                      ? selectedKey == null || selectedKey == entries[i].key
                      : selectedKey == entries[i].key,
                  onTap: () => onPick(i == 0 ? null : entries[i].key),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvatarSectionLabel extends StatelessWidget {
  const _AvatarSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Text(
        label,
        style: AppTypography.label.copyWith(
          fontSize: 13,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: _size,
      height: _size,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: selected
                  ? Border.all(color: cs.onSurface, width: 2.5)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
