import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'menu_icon_square.dart';

/// One row inside a [PopupMenuItem]: a [MenuIconSquare] leading glyph, a label,
/// and an optional trailing widget. Wrapped in [IgnorePointer] because the
/// enclosing [PopupMenuItem] owns the tap/selection — the row is purely visual.
///
/// Callers pass an already-built [icon] (so the few glyphs that need a
/// `Transform` nudge can wrap it) and the resolved text style for the active and
/// disabled states, keeping each menu's own typography in one place.
class MenuItemRow extends StatelessWidget {
  const MenuItemRow({
    super.key,
    required this.icon,
    required this.label,
    required this.style,
    this.disabledStyle,
    this.trailing,
    this.enabled = true,
  });

  /// The leading glyph, already sized and coloured by the caller. Dropped into a
  /// [MenuIconSquare].
  final Widget icon;
  final String label;

  /// Text style for the active row.
  final TextStyle style;

  /// Text style when [enabled] is false. Falls back to [style] when null.
  final TextStyle? disabledStyle;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        children: [
          MenuIconSquare(icon: icon),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: enabled ? style : (disabledStyle ?? style)),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
