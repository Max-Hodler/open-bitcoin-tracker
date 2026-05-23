import 'package:flutter/material.dart';

import '../../services/app_haptics.dart';
import '../../theme/theme.dart';

/// Bitcoin-orange full-width confirm button used by the stack name flows.
/// Renders either a check glyph (default) or the [label] text when supplied,
/// dimmed but tap-blocked when [isValid] is false.
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
