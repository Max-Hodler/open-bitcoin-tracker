import 'package:flutter/material.dart';

import '../orange_primary_button.dart';

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
  final String? label;

  @override
  Widget build(BuildContext context) {
    return OrangePrimaryButton(
      isValid: isValid,
      onTap: onTap,
      label: label,
    );
  }
}
