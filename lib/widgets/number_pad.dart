import 'package:flutter/material.dart';

import '../services/app_haptics.dart';
import '../theme/theme.dart';
import 'soft_ink_splash.dart';

Key numberPadKey(String label) => ValueKey('keypad-$label');

// Vertical sizing for keypad keys. Key width follows the grid (third of the
// available width minus gaps); height is the same as width, clamped to keep
// short phones tappable (min) and tall phones from looking like a tabloid (max).
const double _kMinKeyHeight = 56;
const double _kMaxKeyHeight = 80;
// Height of the confirm/check button that sits below the grid.
const double _kConfirmButtonHeight = 64;

class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.onInput,
    required this.onDelete,
    required this.onClear,
    required this.onEnter,
    required this.isValid,
    this.isEmpty = false,
    this.showConfirm = true,
    this.showDecimal = false,
    this.decimalLabel = '.',
    this.zeroDisabled = false,
    this.onZeroBlocked,
    this.confirmLabel,
  });

  final ValueChanged<String> onInput;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final VoidCallback onEnter;
  final bool isValid;
  final bool isEmpty;
  final bool showConfirm;
  final bool showDecimal;
  final String decimalLabel;
  final bool zeroDisabled;
  final VoidCallback? onZeroBlocked;
  // When set, the confirm button renders this text instead of the default
  // check icon.
  final String? confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Grid(
          onInput: onInput,
          onDelete: onDelete,
          onClear: onClear,
          showDecimal: showDecimal,
          decimalLabel: decimalLabel,
          zeroDisabled: zeroDisabled,
          onZeroBlocked: onZeroBlocked,
          isEmpty: isEmpty,
        ),
        if (showConfirm) ...[
          const SizedBox(height: AppSpacing.sm),
          _ConfirmButton(
            isValid: isValid,
            onTap: onEnter,
            label: confirmLabel,
          ),
        ],
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.onInput,
    required this.onDelete,
    required this.onClear,
    required this.showDecimal,
    required this.decimalLabel,
    required this.zeroDisabled,
    required this.onZeroBlocked,
    required this.isEmpty,
  });

  final ValueChanged<String> onInput;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final bool showDecimal;
  final String decimalLabel;
  final bool zeroDisabled;
  final VoidCallback? onZeroBlocked;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) =>
        _Key(key: numberPadKey(d), onTap: () => onInput(d), child: Text(d));
    return LayoutBuilder(builder: (context, constraints) {
      final keyWidth = (constraints.maxWidth - AppSpacing.sm * 2) / 3;
      final keyHeight = keyWidth.clamp(_kMinKeyHeight, _kMaxKeyHeight);
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: keyWidth / keyHeight,
        children: _tiles(digit),
      );
    });
  }

  List<Widget> _tiles(Widget Function(String) digit) {
    final bottomLeft = showDecimal
        ? _Key(key: numberPadKey('.'), onTap: () => onInput('.'), child: Text(decimalLabel))
        : _Key(
            key: numberPadKey('AC'),
            onTap: isEmpty ? () {} : onClear,
            disabled: isEmpty,
            child: const Text('AC'),
          );
    final zeroKey = zeroDisabled
        ? _Key(
            key: numberPadKey('0'),
            onTap: onZeroBlocked ?? () {},
            disabled: true,
            child: const Text('0'),
          )
        : _Key(key: numberPadKey('0'), onTap: () => onInput('0'), child: const Text('0'));
    return [
      digit('1'),
      digit('2'),
      digit('3'),
      digit('4'),
      digit('5'),
      digit('6'),
      digit('7'),
      digit('8'),
      digit('9'),
      bottomLeft,
      zeroKey,
      _Key(
        key: numberPadKey('backspace'),
        onTap: isEmpty ? () {} : onDelete,
        disabled: isEmpty,
        child: const Icon(Icons.backspace_outlined, size: 22),
      ),
    ];
  }
}

class _Key extends StatelessWidget {
  const _Key({
    super.key,
    required this.onTap,
    required this.child,
    this.disabled = false,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = cs.onSurface;
    // Match the stack cards on the home screen so the keypad reads as the
    // same surface family. Material ripple handles press feedback.
    final tint = cs.surface;
    final radius = BorderRadius.circular(AppSpacing.radius);
    return Material(
      color: tint,
      borderRadius: radius,
      child: InkWell(
        onTap: () {
          if (!disabled) AppHaptics.medium();
          onTap();
        },
        borderRadius: radius,
        // Radial pulse from the tap point, like Google Calculator. Highlight
        // is a faint static fade so the press still registers immediately
        // before the splash catches up.
        splashColor: fg.withValues(alpha: 0.20),
        highlightColor: Colors.transparent,
        splashFactory: SoftInkSplash.splashFactory,
        child: Center(
          child: DefaultTextStyle.merge(
            style: AppTypography.body.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w400,
              color: fg,
            ),
            child: IconTheme(
              data: IconThemeData(color: fg),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.isValid,
    required this.onTap,
    this.label,
  });

  final bool isValid;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: isValid ? 1.0 : 0.4,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SizedBox(
          height: _kConfirmButtonHeight,
          child: Material(
            color: p.bitcoinOrange,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (!isValid) return;
                AppHaptics.medium();
                onTap();
              },
              child: Center(
                child: label == null
                    ? const Icon(
                        Icons.check,
                        size: 28,
                        color: Colors.white,
                      )
                    : Text(
                        label!,
                        style: AppTypography.title.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
