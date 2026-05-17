import 'package:flutter/services.dart';

/// Thin wrapper around `HapticFeedback` so call sites stay terse —
/// `AppHaptics.light()` instead of importing `services` everywhere.
class AppHaptics {
  AppHaptics._();

  static void selection() => HapticFeedback.selectionClick();

  static void light() => HapticFeedback.lightImpact();

  static void medium() => HapticFeedback.mediumImpact();

  static void heavy() => HapticFeedback.heavyImpact();
}
