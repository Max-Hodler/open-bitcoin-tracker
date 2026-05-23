import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_enums.dart';
import '../../data/sats.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';

/// Opens Android's native floating selection toolbar (Copy/Paste pill) anchored
/// at [globalPos]. Inserts the toolbar into the root Overlay with a transparent
/// scrim so an outside tap dismisses it.
///
/// Copy is shown only when [currentInput] has digits; it writes the raw digit
/// string (no separators, no ₿) to the clipboard. Paste is shown only when the
/// clipboard has text; on tap it sanitizes the contents via
/// [Sats.sanitizePastedSats] / [Sats.sanitizePastedBtc] and either commits via
/// [onPasteAccepted] or surfaces an error snackbar.
Future<void> showSatsInputMenu({
  required BuildContext context,
  required Offset globalPos,
  required String currentInput,
  required BtcDisplayMode mode,
  required ValueChanged<String> onPasteAccepted,
}) async {
  final l10n = AppLocalizations.of(context);
  final overlay = Overlay.of(context, rootOverlay: true);
  final hasClipboardText = await Clipboard.hasStrings();
  if (!context.mounted) return;

  final canCopy = currentInput.isNotEmpty;
  if (!canCopy && !hasClipboardText) return;

  late OverlayEntry entry;
  void close() {
    if (entry.mounted) entry.remove();
  }

  final items = <ContextMenuButtonItem>[
    if (canCopy)
      ContextMenuButtonItem(
        label: l10n.satsInputActionCopy,
        onPressed: () async {
          close();
          await Clipboard.setData(ClipboardData(text: currentInput));
          AppHaptics.medium();
          if (!context.mounted) return;
          _showSatsSnack(context, l10n.snackSatsCopied);
        },
      ),
    if (hasClipboardText)
      ContextMenuButtonItem(
        label: l10n.satsInputActionPaste,
        onPressed: () async {
          close();
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          final raw = data?.text ?? '';
          final sanitized = mode == BtcDisplayMode.btc
              ? Sats.sanitizePastedBtc(raw)
              : Sats.sanitizePastedSats(raw);
          if (!context.mounted) return;
          if (sanitized == null) {
            _showSatsSnack(context, l10n.snackSatsPasteInvalid);
            return;
          }
          onPasteAccepted(sanitized);
          AppHaptics.medium();
        },
      ),
  ];

  if (items.isEmpty) return;

  entry = OverlayEntry(
    builder: (_) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: close,
          ),
        ),
        AdaptiveTextSelectionToolbar.buttonItems(
          anchors: TextSelectionToolbarAnchors(primaryAnchor: globalPos),
          buttonItems: items,
        ),
      ],
    ),
  );
  overlay.insert(entry);
}

void _showSatsSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
}
