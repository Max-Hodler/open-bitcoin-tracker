import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/app_enums.dart';
import '../data/sats.dart';
import '../data/stack.dart' as model;
import '../format/fiat.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/app_haptics.dart';
import '../state/state.dart';
import '../theme/theme.dart';
import '../widgets/blinking_caret.dart';
import '../widgets/number_pad.dart';

class CancelBar extends StatelessWidget {
  const CancelBar({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: Align(
        alignment: Alignment.centerLeft,
        child: BackButton(
          color: cs.onSurfaceVariant,
          onPressed: () {
            AppHaptics.light();
            onCancel();
          },
        ),
      ),
    );
  }
}

class SatsInputDisplay extends StatelessWidget {
  const SatsInputDisplay({
    super.key,
    required this.input,
    required this.caret,
    required this.mode,
    this.onLongPressAt,
    this.onCaretAt,
  });

  // In sats mode this is a digit string (e.g. "78276"); in BTC mode it's a
  // raw decimal string with '.' as the separator and no grouping (e.g.
  // "0.00078276").
  final String input;
  // Caret position in the raw [input] string, in [0, input.length].
  final int caret;
  final BtcDisplayMode mode;
  final ValueChanged<Offset>? onLongPressAt;
  // Called when the user taps a digit (or the trailing zone) to reposition the
  // caret. The argument is a raw-string index in [0, input.length].
  final ValueChanged<int>? onCaretAt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final formatted = input.isEmpty
        ? ''
        : (mode == BtcDisplayMode.btc
            ? formatFiatRaw(input)
            : intFormatter.format(int.parse(input)));

    final digitStyle = AppTypography.title.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      color: cs.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Caret is rendered with zero layout width so moving it between digits
    // doesn't shift the surrounding glyphs by the caret's 2px stroke. The
    // OverflowBox lets it paint outside its 0-width slot.
    final caretWidget = SizedBox(
      width: 0,
      height: 28 * 1.2,
      child: OverflowBox(
        maxWidth: 2,
        alignment: Alignment.centerLeft,
        child: BlinkingCaret(
          color: cs.onSurface,
          height: 28 * 1.2,
          // Reset blink on input change AND on caret moves so it's always
          // visible immediately after a tap.
          keystrokeSignal: '$input|$caret',
        ),
      ),
    );

    // Render each character of the formatted string as its own widget so we
    // can hit-test per character (iOS-style caret placement). The [caret]
    // index is in raw-input coordinates: in sats mode every digit advances
    // it by one and group separators (commas, NBSPs) don't exist in raw so
    // they're skipped. In BTC mode the locale decimal separator also exists
    // in raw (the '.' the user typed) so it advances the index too, while
    // grouping separators still don't.
    final localeSep = localeDecimalSeparator;
    final children = <Widget>[];
    var rawConsumed = 0;
    void addCaretIfHere() {
      if (rawConsumed == caret) children.add(caretWidget);
    }

    if (formatted.isEmpty) {
      // Nothing to tap; show just the caret so the underline isn't bare.
      children.add(caretWidget);
    } else {
      for (var i = 0; i < formatted.length; i++) {
        final ch = formatted[i];
        final isDigit = ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
        final isDecimal = mode == BtcDisplayMode.btc && ch == localeSep;
        if (isDigit || isDecimal) {
          addCaretIfHere();
          final before = rawConsumed;
          final after = rawConsumed + 1;
          children.add(_TapDigit(
            ch: ch,
            style: digitStyle,
            onTapBefore:
                onCaretAt == null ? null : () => onCaretAt!(before),
            onTapAfter: onCaretAt == null ? null : () => onCaretAt!(after),
          ));
          rawConsumed = after;
        } else {
          // Group separator (or anything else) — doesn't appear in raw input.
          children.add(Text(ch, style: digitStyle));
        }
      }
      // Caret at end of input.
      addCaretIfHere();
    }

    final content = Container(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: p.bitcoinOrange),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!symbolAfterAmount) ...[
              Text(
                '₿',
                style: AppTypography.title.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: p.bitcoinOrange,
                ),
              ),
              const SizedBox(width: 4),
            ],
            ...children,
            if (symbolAfterAmount) ...[
              const SizedBox(width: 4),
              Text(
                '₿',
                style: AppTypography.title.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: p.bitcoinOrange,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final cb = onLongPressAt;
    if (cb == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) => cb(details.globalPosition),
      child: content,
    );
  }
}

class _TapDigit extends StatelessWidget {
  const _TapDigit({
    required this.ch,
    required this.style,
    required this.onTapBefore,
    required this.onTapAfter,
  });

  final String ch;
  final TextStyle style;
  final VoidCallback? onTapBefore;
  final VoidCallback? onTapAfter;

  @override
  Widget build(BuildContext context) {
    final text = Text(ch, style: style);
    if (onTapBefore == null && onTapAfter == null) return text;
    // Stack-with-Positioned would also work, but two side-by-side GestureDetectors
    // sharing the digit's intrinsic width are simpler and respect FittedBox scaling.
    return Stack(
      children: [
        text,
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTapBefore,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTapAfter,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SatsFiatLabel extends StatelessWidget {
  const SatsFiatLabel({super.key, required this.input, required this.mode});

  final String input;
  final BtcDisplayMode mode;

  @override
  Widget build(BuildContext context) {
    final currency = context.select<AppStateNotifier, Currency>((a) => a.currency);
    final rate = context.select<LivePriceController, double?>(
          (c) => c.rates.forCurrency(currency),
        ) ??
        0;
    final btcValue = mode == BtcDisplayMode.btc
        ? (double.tryParse(input) ?? 0)
        : (int.tryParse(input) ?? 0) / Sats.perBtc;
    final fiatValue = rate == 0 ? 0.0 : btcValue * rate;
    final symbol = currencySymbols[currency] ?? r'$';
    final showHint = input.isEmpty;
    final l10n = AppLocalizations.of(context);
    final label = showHint
        ? (mode == BtcDisplayMode.btc
            ? l10n.satsInputUnitHintBtc
            : l10n.satsInputUnitHint)
        : rate == 0
            ? ''
            : symbolAfterAmount
                ? '${formatDerivedFiatValue(fiatValue)}$symbol'
                : '$symbol${formatDerivedFiatValue(fiatValue)}';

    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 24,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: AppTypography.body.copyWith(
            fontSize: 18,
            color: cs.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

Widget buildSatsInputScaffold({
  required BuildContext context,
  required String input,
  required int caret,
  required bool isValid,
  required BtcDisplayMode mode,
  required void Function(String) onInput,
  required VoidCallback onDelete,
  required VoidCallback onClear,
  required VoidCallback onConfirm,
  required bool zeroDisabled,
  required VoidCallback onZeroBlocked,
  required bool showLeadingZeroWarning,
  String? confirmLabel,
  ValueChanged<Offset>? onInputLongPressAt,
  ValueChanged<int>? onCaretAt,
}) {
  final l10n = AppLocalizations.of(context);
  final cs = Theme.of(context).colorScheme;
  return Scaffold(
    backgroundColor: cs.surfaceContainerLow,
    appBar: AppBar(
      backgroundColor: cs.surfaceContainerLow,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: BackButton(
        color: cs.onSurfaceVariant,
        onPressed: () {
          AppHaptics.light();
          Navigator.of(context).maybePop();
        },
      ),
      centerTitle: true,
      title: Text(
        l10n.satsInputLabel,
        style: AppTypography.title.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SatsInputDisplay(
              input: input,
              caret: caret,
              mode: mode,
              onLongPressAt: onInputLongPressAt,
              onCaretAt: onCaretAt,
            ),
            const SizedBox(height: AppSpacing.sm),
            SatsFiatLabel(input: input, mode: mode),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Opacity(
                opacity: showLeadingZeroWarning ? 1.0 : 0.0,
                child: Text(
                  l10n.satsInputLeadingZeroWarning,
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(
                    fontSize: 14,
                    letterSpacing: 1.2,
                    color: cs.error,
                  ),
                ),
              ),
            ),
            NumberPad(
              onInput: onInput,
              onDelete: onDelete,
              onClear: onClear,
              onEnter: onConfirm,
              isValid: isValid,
              isEmpty: input.isEmpty,
              // Decimal key + locale separator only in BTC mode. In sats mode
              // the leading-zero gate uses [zeroDisabled] as before.
              showDecimal: mode == BtcDisplayMode.btc,
              decimalLabel: localeDecimalSeparator,
              zeroDisabled: zeroDisabled,
              onZeroBlocked: onZeroBlocked,
              confirmLabel: confirmLabel,
            ),
          ],
        ),
      ),
    ),
  );
}

class StackNameField extends StatelessWidget {
  const StackNameField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = context.palette;
    // Hide the Material selection drop handle (the orange "tear" under the
    // caret). Long-press still reveals the system Cut/Copy/Paste toolbar.
    return Theme(
      data: theme.copyWith(
        textSelectionTheme: theme.textSelectionTheme.copyWith(
          selectionHandleColor: Colors.transparent,
        ),
      ),
      child: TextField(
      controller: controller,
      focusNode: focusNode,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: cs.onSurface,
      // Match BlinkingCaret on the amount/converter screens (fontSize * 1.2)
      // instead of the SDK default which renders to the full line height.
      cursorHeight: 28 * 1.2,
      inputFormatters: [
        LengthLimitingTextInputFormatter(model.Stack.maxNameLength),
      ],
      onSubmitted: onSubmitted,
      style: AppTypography.title.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        filled: false,
        contentPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: p.bitcoinOrange),
        ),
      ),
    ),
    );
  }
}

class StackNameLimitLabel extends StatelessWidget {
  const StackNameLimitLabel({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: visible ? 1 : 0,
      child: Text(
        AppLocalizations.of(context).stackNameLimitReached,
        textAlign: TextAlign.center,
        style: AppTypography.label.copyWith(
          color: p.bitcoinOrange,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class StackNameConfirmButton extends StatelessWidget {
  const StackNameConfirmButton({
    super.key,
    required this.isValid,
    required this.onTap,
    this.label,
  });

  final bool isValid;
  final VoidCallback onTap;
  // When set, the button renders this text instead of the default check icon.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: isValid ? 1.0 : 0.4,
      child: SizedBox(
        height: 64,
        child: FilledButton(
          onPressed: isValid
              ? () {
                  AppHaptics.light();
                  onTap();
                }
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: p.bitcoinOrange,
            foregroundColor: Colors.white,
            disabledBackgroundColor: p.bitcoinOrange,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
          ),
          child: label == null
              ? const Icon(Icons.check, size: 28)
              : Text(
                  label!,
                  style: AppTypography.title.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Max fractional digits we accept on the BTC-mode amount input. Matches the
/// 8 decimals of canonical satoshis, so the rounded sats value is lossless.
const int _kBtcMaxDecimals = 8;

/// Returns the new (input, caret) after inserting [digit] (or '.') at [caret]
/// in the BTC-mode amount input. Returns null when the keystroke should be
/// ignored (already-present decimal, fractional cap reached, supply cap
/// exceeded, etc.).
(String, int)? tryInsertBtcChar(String input, int caret, String ch) {
  if (ch == '.') {
    if (input.contains('.')) return null;
    if (input.isEmpty) {
      // First char: render as '0.' with caret after the dot.
      return ('0.', 2);
    }
    return ('${input.substring(0, caret)}.${input.substring(caret)}', caret + 1);
  }
  if (input.contains('.')) {
    final dot = input.indexOf('.');
    final fracLen = input.length - dot - 1;
    final insertingInFraction = caret > dot;
    if (insertingInFraction && fracLen >= _kBtcMaxDecimals) return null;
  }
  final next = '${input.substring(0, caret)}$ch${input.substring(caret)}';
  // Strip the leading-zero rule from sats mode: "0.001" is valid, but reject
  // pure leading-zero integer parts like "07" (jump to "7" instead would
  // surprise the user mid-edit, so just block the insert).
  if (ch == '0' &&
      caret == 0 &&
      input.isNotEmpty &&
      !input.startsWith('0')) {
    return null;
  }
  if (!_btcInputWithinSupply(next)) return null;
  return (next, caret + 1);
}

bool _btcInputWithinSupply(String input) {
  final parsed = double.tryParse(input);
  if (parsed == null) return false;
  // Generous epsilon to allow typing the exact cap (21000000) without
  // floating-point error rejecting it.
  return parsed <= 21000000.000000005;
}

/// Renders a sats integer as a canonical BTC raw string ('.'-separated, no
/// grouping, up to 8 fractional digits with trailing zeros trimmed). Returns
/// '' for 0.
String satsToBtcRaw(int sats) {
  if (sats <= 0) return '';
  final whole = sats ~/ Sats.perBtc;
  final fraction = sats.remainder(Sats.perBtc).abs();
  if (fraction == 0) return whole.toString();
  var fracStr = fraction.toString().padLeft(8, '0');
  fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
  return '$whole.$fracStr';
}

/// Parses a BTC raw input string to canonical sats. Returns 0 for an empty
/// or unparseable input.
int btcRawToSats(String input) {
  if (input.isEmpty) return 0;
  final parsed = double.tryParse(input);
  if (parsed == null) return 0;
  return (parsed * Sats.perBtc).round();
}

/// Strips everything but ASCII digits, trims leading zeros, and validates the
/// result fits the sats-input constraints (digit cap + supply cap, non-zero).
/// Returns null if the clipboard contents can't yield a valid amount.
String? sanitizePastedSats(String raw) {
  final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) return null;
  final trimmed = digitsOnly.replaceFirst(RegExp(r'^0+'), '');
  if (trimmed.isEmpty) return null;
  if (trimmed.length > Sats.maxInputDigits) return null;
  final parsed = int.tryParse(trimmed);
  if (parsed == null || parsed == 0) return null;
  if (parsed > Sats.maxSupply) return null;
  return trimmed;
}

/// Sanitizes a clipboard string for the BTC-mode amount input. Accepts a
/// decimal number using either '.' or ',' as the separator (so users can paste
/// from locales other than the active one); the returned raw uses '.' to
/// match the in-app canonical form. Caps fractional digits at 8 and validates
/// against the 21M supply.
String? sanitizePastedBtc(String raw) {
  // Drop everything but digits and the two common decimal separators.
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (cleaned.isEmpty) return null;
  // Pick the *last* separator as the decimal point; treat any earlier
  // separators as grouping noise and strip them. Handles "1,234.56" (en) and
  // "1.234,56" (es) without needing to know the source locale.
  String normalized;
  final lastDot = cleaned.lastIndexOf('.');
  final lastComma = cleaned.lastIndexOf(',');
  final lastSep = lastDot > lastComma ? lastDot : lastComma;
  if (lastSep < 0) {
    normalized = cleaned;
  } else {
    final intPart = cleaned.substring(0, lastSep).replaceAll(RegExp(r'[.,]'), '');
    final fracPart = cleaned.substring(lastSep + 1);
    if (fracPart.contains(RegExp(r'[.,]'))) return null;
    normalized = fracPart.isEmpty ? intPart : '$intPart.$fracPart';
  }
  if (normalized.isEmpty || normalized == '.') return null;
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0) return null;
  // Round-trip through sats so the value matches the keypad's max-supply gate
  // and we honor the 8-decimal cap.
  final sats = (parsed * Sats.perBtc).round();
  if (sats <= 0 || sats > Sats.maxSupply) return null;
  // Re-derive raw from sats so trailing zeros are trimmed and we never echo
  // back more than 8 fractional digits.
  final whole = sats ~/ Sats.perBtc;
  final fraction = sats.remainder(Sats.perBtc).abs();
  if (fraction == 0) return whole.toString();
  var fracStr = fraction.toString().padLeft(8, '0');
  fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
  return '$whole.$fracStr';
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

/// Opens Android's native floating selection toolbar (Copy/Paste pill) anchored
/// at [globalPos]. Inserts the toolbar into the root Overlay with a transparent
/// scrim so an outside tap dismisses it.
///
/// Copy is shown only when [currentInput] has digits; it writes the raw digit
/// string (no separators, no ₿) to the clipboard. Paste is shown only when the
/// clipboard has text; on tap it sanitizes the contents via [sanitizePastedSats]
/// and either commits via [onPasteAccepted] or surfaces an error snackbar.
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
              ? sanitizePastedBtc(raw)
              : sanitizePastedSats(raw);
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
