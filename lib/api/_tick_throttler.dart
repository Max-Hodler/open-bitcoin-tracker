import 'dart:async';

/// Min-interval throttle for a "something changed, please notify" signal.
///
/// Used by [LivePriceController] to gate price-card repaints: WS ticks arrive
/// ~1/sec and the user's cadence preference says how often we're allowed to
/// repaint. The contract is:
///
/// - If [interval] is null, every [request] fires [onFire] synchronously.
/// - Otherwise, if the time since the last fire is >= [interval], fire
///   immediately. If not, arm a single deferred timer for the remainder of
///   the window so the latest signal isn't dropped. Subsequent [request]s
///   while a timer is pending are coalesced into it.
///
/// Callers that want to suppress fires entirely (e.g. the "off" cadence)
/// should simply not call [request].
class TickThrottler {
  TickThrottler({required this.onFire});

  /// Called on each accepted fire. Implementation should be the
  /// `notifyListeners()` (or equivalent) call.
  final void Function() onFire;

  /// Minimum gap between fires. null = no throttling, every [request] fires.
  Duration? interval;

  DateTime? _lastFiredAt;
  Timer? _pendingTimer;
  bool _disposed = false;

  /// Request a fire. Honors [interval] per the class contract.
  void request() {
    if (_disposed) return;
    final i = interval;
    if (i == null) {
      _fireNow();
      return;
    }
    final last = _lastFiredAt;
    final now = DateTime.now();
    final elapsed = last == null ? i : now.difference(last);
    if (elapsed >= i) {
      _fireNow();
      return;
    }
    if (_pendingTimer != null) return;
    _pendingTimer = Timer(i - elapsed, () {
      _pendingTimer = null;
      if (_disposed) return;
      _fireNow();
    });
  }

  /// Mark the throttle as having just fired without actually firing. Lets the
  /// caller reset the cooldown window — e.g. when the user toggles cadence
  /// from "off" back on and the controller fires once manually so the UI
  /// catches up; the next throttled tick should then wait a full interval.
  void markFired() {
    _lastFiredAt = DateTime.now();
    cancelPending();
  }

  /// Cancel any pending fire. Use when [interval] changes so a deferred fire
  /// scheduled under the old policy doesn't slip through.
  void cancelPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  void dispose() {
    _disposed = true;
    cancelPending();
  }

  void _fireNow() {
    _lastFiredAt = DateTime.now();
    cancelPending();
    onFire();
  }
}
