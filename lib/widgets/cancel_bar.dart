import 'package:flutter/material.dart';

import '../services/app_haptics.dart';

/// Generic 56-tall row holding a leading back button. Used as a Scaffold-less
/// alternative to AppBar on screens (e.g. the PIN entry screen) that paint
/// their own backdrop and just need a back affordance.
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
