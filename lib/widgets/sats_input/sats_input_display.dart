import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/app_enums.dart';
import '../../data/fiat.dart';
import '../../theme/theme.dart';
import '../blinking_caret.dart';

/// Bitcoin-orange-underlined amount display used by the stack amount screens
/// and the converter's keypad area. Renders the digits of [input] one at a
/// time so taps can reposition the caret per-digit. The caret has zero layout
/// width so its 2px stroke doesn't shift surrounding glyphs.
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
      fontFeatures: const [ui.FontFeature.tabularFigures()],
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
    // Stack-with-Positioned would also work, but two side-by-side
    // GestureDetectors sharing the digit's intrinsic width are simpler and
    // respect FittedBox scaling.
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
