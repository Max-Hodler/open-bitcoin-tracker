import 'package:flutter/material.dart';

import '../services/app_haptics.dart';

/// 36×36 circular icon button used for the compact affordances in the home
/// header (lock/unlock, add-stack) and as the tap target backing the overflow
/// menus. Fires a light haptic on tap and clamps itself to a fixed 36×36 box so
/// neighbouring buttons line up as a matched set.
///
/// The default rendering is a transparent circle with an [onSurfaceVariant]
/// foreground; disabled state fades the foreground to 38% so it reads as
/// inactive without going invisible. Callers that need a different glyph
/// baseline (e.g. the `attach_money` nudge) wrap [icon] themselves.
class CircularIconButton extends StatelessWidget {
  const CircularIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconSize = 22,
    this.tooltip,
    this.enabled = true,
  });

  final Widget icon;
  final VoidCallback onTap;
  final double iconSize;
  final String? tooltip;
  final bool enabled;

  /// Edge of the square tap target. Shared by every caller so the lock, add and
  /// overflow affordances read as a matched 36×36 row.
  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final faded = cs.onSurfaceVariant.withValues(alpha: 0.38);
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: enabled
            ? () {
                AppHaptics.light();
                onTap();
              }
            : null,
        tooltip: tooltip,
        icon: icon,
        iconSize: iconSize,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: enabled ? cs.onSurfaceVariant : faded,
          disabledForegroundColor: faded,
          elevation: 0,
          fixedSize: const Size(size, size),
          minimumSize: const Size(size, size),
          maximumSize: const Size(size, size),
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
