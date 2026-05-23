import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/theme.dart';

/// Fades in below [StackNameField] when the user hits the name-length cap.
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
