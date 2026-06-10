import 'package:flutter/services.dart';

/// Dart side of the security method channel implemented in MainActivity.
///
/// Both calls are best-effort: on platforms without the channel (tests,
/// non-Android) they degrade to a no-op / null rather than throwing, so lock
/// state changes and cooldown checks never fail on the channel's account.
abstract final class PlatformSecurity {
  static const _channel =
      MethodChannel('com.openbitcointracker.app/platform_security');

  /// Adds or clears FLAG_SECURE on the activity window. While set, the
  /// recents thumbnail is blanked and screenshots/screen capture are blocked.
  static Future<void> setSecureScreen(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecureScreen', secure);
    } on MissingPluginException {
      // No host implementation (tests / non-Android).
    } on PlatformException {
      // Never let a window-flag failure break a lock state change.
    }
  }

  /// Monotonic milliseconds since boot, or null where unavailable.
  static Future<int?> elapsedRealtimeMs() async {
    try {
      return await _channel.invokeMethod<int>('elapsedRealtime');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
