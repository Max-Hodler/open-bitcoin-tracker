import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Rounded square that backs an overflow-menu item's leading icon. The fill
/// matches the range selector bar's track (`recessedSurface`, falling back to
/// `surfaceContainer`) so the menu icons read as part of the same visual
/// language.
class MenuIconSquare extends StatelessWidget {
  const MenuIconSquare({super.key, required this.icon});

  /// The icon to center inside the square. Sized/colored by the caller so the
  /// square stays a neutral container (e.g. the delete row tints its icon with
  /// the error color).
  final Widget icon;

  // Edge of the square. Sized to comfortably hold a 22px icon with a little
  // breathing room.
  static const double _size = 34;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = context.palette.recessedSurface ?? cs.surfaceContainer;
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      // Center the icon both ways. Some Material glyphs (the swap arrows, the
      // bitcoin/dollar marks) don't sit dead-center in their own font box, so
      // a plain alignment leaves them looking top-left heavy; Center on a tight
      // child keeps every icon visually centered in the square.
      child: Center(child: icon),
    );
  }
}
