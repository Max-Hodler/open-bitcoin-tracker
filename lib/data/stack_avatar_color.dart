import 'package:flutter/material.dart';

/// Picker palette for the default initial-letter avatar. Keyed by short
/// stable strings (persisted on [Stack.colorKey]). The null key falls back
/// to the active theme's bitcoinOrange so existing stacks keep their look.
///
/// All colors are tuned to sit in the same warm/earthy register as
/// bitcoinOrange (#F7931A) so they read as a coherent set rather than a
/// rainbow. They serve as both the letter color and the seed for the
/// lighter background tint (computed at render time with alpha 0.18).
class StackAvatarColor {
  const StackAvatarColor(this.key, this.color);

  final String key;
  final Color color;

  /// Order matters — this is also the swatch order in the picker UI.
  /// 'orange' is intentionally first so the default-equivalent swatch
  /// reads as the leading option.
  static const List<StackAvatarColor> palette = [
    StackAvatarColor('orange', Color(0xFFF7931A)),
    StackAvatarColor('amber', Color(0xFFE0A030)),
    StackAvatarColor('rust', Color(0xFFC45A2C)),
    StackAvatarColor('plum', Color(0xFF8E4A6E)),
    StackAvatarColor('olive', Color(0xFF7A7A2E)),
    StackAvatarColor('teal', Color(0xFF2D7A7A)),
  ];

  /// Resolve a stored key to a color. Returns null when [key] is null or
  /// doesn't match any palette entry — caller falls back to the theme's
  /// bitcoinOrange in that case.
  static Color? resolve(String? key) {
    if (key == null) return null;
    for (final c in palette) {
      if (c.key == key) return c.color;
    }
    return null;
  }
}
