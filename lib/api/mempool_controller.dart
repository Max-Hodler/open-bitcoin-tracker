import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'mempool_client.dart';

/// Polls [MempoolClient] every 60s while a subscriber is mounted and the app
/// is foregrounded. Mined blocks land every ~10 min and the projected fee
/// buckets only shift in user-perceptible ways every minute or two, so the
/// cadence is generous on quota without feeling stale. Pauses while
/// backgrounded *or* while no subscriber is listening (e.g. user navigated
/// away from the home screen); refetches on resume / re-subscribe if stale.
class MempoolController extends ChangeNotifier with WidgetsBindingObserver {
  MempoolController({MempoolClient? client})
      : _client = client ?? MempoolClient();

  static const Duration _pollInterval = Duration(seconds: 60);

  final MempoolClient _client;

  MempoolSnapshot? _snapshot;
  bool _failed = false;
  bool _started = false;
  bool _disposed = false;
  bool _backgrounded = false;
  int _subscribers = 0;
  Timer? _timer;

  MempoolSnapshot? get snapshot => _snapshot;
  bool get failed => _failed;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Register a visible consumer. The first subscriber kicks off polling
  /// (and an immediate fetch if the cached snapshot is stale or absent).
  /// Pair every call with [removeSubscriber] in the consumer's dispose.
  void addSubscriber() {
    if (_disposed) return;
    _subscribers++;
    if (_subscribers != 1) return;
    final fetchedAt = _snapshot?.fetchedAt;
    final stale = fetchedAt == null ||
        DateTime.now().difference(fetchedAt) >= _pollInterval;
    if (stale) unawaited(_fetch());
    _arm();
  }

  void removeSubscriber() {
    if (_subscribers == 0) return;
    _subscribers--;
    if (_subscribers == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Re-fetch immediately. Used by the retry button on the error state.
  void restartStream() {
    if (!_started || _disposed) return;
    unawaited(_fetch());
  }

  /// Debug-only: synthesize a new mined block at the front of the snapshot
  /// to exercise the strip's slide animation without waiting ~10 minutes for
  /// a real block. No-op in release builds.
  void debugSimulateNewBlock() {
    if (!kDebugMode) return;
    final current = _snapshot;
    if (current == null || current.mined.isEmpty) return;
    final top = current.mined.first;
    final fake = MempoolBlock(
      medianFeeSatVb: top.medianFeeSatVb,
      txCount: top.txCount,
      height: (top.height ?? 0) + 1,
    );
    _snapshot = MempoolSnapshot(
      projected: current.projected,
      mined: [fake, ...current.mined],
      fetchedAt: current.fetchedAt,
    );
    notifyListeners();
  }

  void _arm() {
    _timer?.cancel();
    if (_backgrounded || _disposed || _subscribers == 0) return;
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_fetch()));
  }

  Future<void> _fetch() async {
    if (_disposed) return;
    final result = await _client.fetch();
    if (_disposed) return;
    if (result == null) {
      _failed = true;
    } else {
      _failed = false;
      _snapshot = result;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _backgrounded = true;
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.resumed:
        _backgrounded = false;
        if (_subscribers == 0) return;
        // Skip the immediate refetch if the cached snapshot is still fresh —
        // a quick app-switch shouldn't cost a network round-trip. The poll
        // interval doubles as the staleness threshold.
        final fetchedAt = _snapshot?.fetchedAt;
        final stale = fetchedAt == null ||
            DateTime.now().difference(fetchedAt) >= _pollInterval;
        if (stale) unawaited(_fetch());
        _arm();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _client.close();
    super.dispose();
  }
}
