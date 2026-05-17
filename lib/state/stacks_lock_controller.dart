import 'package:flutter/widgets.dart';

import '../data/app_enums.dart';
import 'app_state_notifier.dart';

class StacksLockController extends ChangeNotifier
    with WidgetsBindingObserver {
  StacksLockController({required AppStateNotifier app}) : _app = app {
    _lastMode = _app.stacksAuthMode;
    _unlocked = _lastMode == StacksAuthMode.off;
    _app.addListener(_onAppStateChanged);
  }

  final AppStateNotifier _app;
  bool _unlocked = true;
  DateTime? _backgroundedAt;
  StacksAuthMode _lastMode = StacksAuthMode.off;
  bool _started = false;
  bool _disposed = false;

  StacksAuthMode get mode => _app.stacksAuthMode;
  bool get isLocked => mode != StacksAuthMode.off && !_unlocked;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Flip the UI to unlocked. The caller must have already decrypted the
  /// stacks via [AppStateNotifier.unlockWithDek] — this just lifts the gate.
  void unlock() {
    if (_unlocked) return;
    _unlocked = true;
    notifyListeners();
  }

  /// Lift the gate AND wipe the in-memory DEK + decrypted stacks. Called by
  /// the manual lock button and by the lifecycle observer on background
  /// timeout. Idempotent.
  void lockNow() {
    if (!_unlocked) return;
    _app.relock();
    _unlocked = false;
    notifyListeners();
  }

  void _onAppStateChanged() {
    final next = _app.stacksAuthMode;
    if (next == _lastMode) return;
    final prev = _lastMode;
    _lastMode = next;
    if (next == StacksAuthMode.off) {
      // Auth was disabled -> reveal stacks immediately.
      if (!_unlocked) {
        _unlocked = true;
        notifyListeners();
      }
    } else if (prev == StacksAuthMode.off) {
      // Auth was enabled from off -> lock right away (cold-start parity).
      if (_unlocked) {
        _unlocked = false;
        notifyListeners();
      }
    } else {
      // Mode switched between two on-states (device <-> pin); leave _unlocked alone.
      // The settings flow that triggered the swap already required re-auth.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only 'paused' and 'resumed' are observed. inactive/hidden/detached are
    // deliberately ignored: local_auth's OS prompt fires 'inactive' and
    // treating it as backgrounded would re-lock immediately on success,
    // producing a permanent re-prompt loop.
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final timeout = _app.stacksLockTimeout.duration; // null == "Never" / cold-start only
      final bg = _backgroundedAt;
      _backgroundedAt = null;
      if (mode == StacksAuthMode.off || timeout == null || bg == null) return;
      if (DateTime.now().difference(bg) >= timeout && _unlocked) {
        _app.relock();
        _unlocked = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_onAppStateChanged);
    super.dispose();
  }
}
