import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'hashrate_client.dart';

/// Polls [HashrateClient] while a subscriber is mounted and the app is
/// foregrounded. Pauses while backgrounded *or* while no subscriber is
/// listening; refetches on resume / re-subscribe if stale.
///
/// Owns a per-range snapshot cache so the expanded chart can swap ranges
/// without losing previously-fetched data. The "active" range — set by
/// [setActiveRange] — is the only one the timer keeps fresh; other ranges
/// stay cached at whatever value they last loaded.
///
/// Cadence is range-aware: the d3 endpoint is the only one that updates on a
/// sub-day cadence, and even then the value drifts by fractions of a percent
/// per minute, so we poll it every [_d3PollInterval]. Longer ranges are
/// daily-aggregate datasets that don't change between polls at all, so they
/// poll on [_longRangePollInterval] (only relevant while expanded — collapse
/// returns the active range to d3). Consecutive failures back off
/// exponentially (×2 per failure, capped at [_maxBackoff]) and reset on a
/// successful fetch — saves radio wakeups when the device has no signal.
class HashrateController extends ChangeNotifier with WidgetsBindingObserver {
  HashrateController({HashrateClient? client})
      : _client = client ?? HashrateClient();

  static const Duration _d3PollInterval = Duration(minutes: 5);
  static const Duration _longRangePollInterval = Duration(minutes: 15);
  static const Duration _maxBackoff = Duration(minutes: 16);

  final HashrateClient _client;

  final Map<HashrateRange, HashrateSnapshot> _snapshots = {};
  // apiPaths currently in flight. Keyed by string (not range) so a fetch for
  // y5 also marks y10 and all as loading — they share the `/all` endpoint and
  // a single response satisfies every sibling, so we must dedupe here too.
  final Set<String> _inFlightPaths = {};
  // apiPaths whose most recent fetch failed. Cleared on a successful refetch.
  // Ranges sharing an apiPath share the same failure state for free.
  final Set<String> _failedPaths = {};
  // Consecutive failure count per apiPath; doubles the next-poll delay until
  // capped by [_maxBackoff]. Reset on success or on a manual user retry.
  final Map<String, int> _consecutiveFailures = {};
  HashrateRange _activeRange = HashrateRange.d3;
  bool _started = false;
  bool _disposed = false;
  bool _backgrounded = false;
  int _subscribers = 0;
  Timer? _timer;

  HashrateSnapshot? snapshotFor(HashrateRange range) => _snapshots[range];

  bool isLoading(HashrateRange range) => _inFlightPaths.contains(range.apiPath);

  bool didFail(HashrateRange range) => _failedPaths.contains(range.apiPath);

  /// Register a visible consumer. The first subscriber lazily attaches the
  /// lifecycle observer (so the controller costs nothing when the user has
  /// hidden the widget) and kicks off polling — with an immediate fetch if
  /// the cached snapshot for the active range is stale or absent.
  /// Pair every call with [removeSubscriber] in the consumer's dispose.
  void addSubscriber() {
    if (_disposed) return;
    _subscribers++;
    if (_subscribers != 1) return;
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _refetchIfStale(_activeRange);
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

  /// Switch the polled range. If there's no cached snapshot for [range] we
  /// fetch immediately so the chart can render; otherwise we just rearm the
  /// timer against the new range so subsequent ticks refresh it instead
  /// of the previous one.
  void setActiveRange(HashrateRange range) {
    if (_disposed) return;
    if (_activeRange == range) {
      _refetchIfStale(range);
      return;
    }
    _activeRange = range;
    notifyListeners();
    _refetchIfStale(range);
    _arm();
  }

  /// Force a refetch of [range] regardless of cache. Used by the chart's
  /// retry button and the collapsed-card error retry. Resets the backoff so
  /// the user's explicit tap doesn't get stuck waiting on the prior delay.
  void refetchRange(HashrateRange range) {
    if (_disposed) return;
    _consecutiveFailures.remove(range.apiPath);
    unawaited(_fetch(range));
  }

  Duration _baseInterval(HashrateRange range) =>
      range == HashrateRange.d3 ? _d3PollInterval : _longRangePollInterval;

  // After N consecutive failures the next attempt waits base × 2^N, capped at
  // [_maxBackoff]. Zero failures → just the base interval.
  Duration _nextDelayFor(HashrateRange range) {
    final base = _baseInterval(range);
    final fails = _consecutiveFailures[range.apiPath] ?? 0;
    if (fails == 0) return base;
    final ms = base.inMilliseconds * math.pow(2, fails).toInt();
    final capped = math.min(ms, _maxBackoff.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  void _arm() {
    _timer?.cancel();
    if (_backgrounded || _disposed || _subscribers == 0) return;
    final delay = _nextDelayFor(_activeRange);
    // Single-shot timer that re-arms itself on completion. Keeps the cadence
    // adaptive: each tick consults the latest backoff/active-range state
    // instead of the value that was true when [_arm] was first called.
    _timer = Timer(delay, _onTick);
  }

  void _onTick() {
    if (_disposed) return;
    unawaited(_fetch(_activeRange).whenComplete(_arm));
  }

  void _refetchIfStale(HashrateRange range) {
    // Stale if *this* range has no snapshot, or the cached one is older than
    // its base interval. A sibling range (same apiPath) being fresh isn't
    // enough — they currently keep independent cache entries — but the
    // in-flight check below still dedupes the network call itself.
    final snap = _snapshots[range];
    final stale = snap == null ||
        DateTime.now().difference(snap.fetchedAt) >= _baseInterval(range);
    if (stale && !_inFlightPaths.contains(range.apiPath)) {
      unawaited(_fetch(range));
    }
  }

  Future<void> _fetch(HashrateRange range) async {
    if (_disposed) return;
    final apiPath = range.apiPath;
    if (_inFlightPaths.contains(apiPath)) return;
    _inFlightPaths.add(apiPath);
    // Notify only when the chart actually has nothing to show — i.e. this is
    // the first fetch for the range. For staleness refetches there's already
    // cached data, so suppressing the in-flight notify avoids a needless
    // rebuild of the fl_chart subtree on every poll tick. Deferred one
    // microtask so callers that kick off a fetch from inside a build (e.g.
    // addSubscriber → _refetchIfStale during didChangeDependencies) don't
    // trip the framework's markNeedsBuild-during-build assertion.
    final isFirstLoad = _snapshots[range] == null;
    if (isFirstLoad) {
      scheduleMicrotask(() {
        if (_disposed) return;
        if (_inFlightPaths.contains(apiPath)) notifyListeners();
      });
    }
    final payload = await _client.fetchApiPath(apiPath);
    if (_disposed) return;
    _inFlightPaths.remove(apiPath);
    if (payload == null) {
      _failedPaths.add(apiPath);
      _consecutiveFailures[apiPath] = (_consecutiveFailures[apiPath] ?? 0) + 1;
    } else {
      _failedPaths.remove(apiPath);
      _consecutiveFailures.remove(apiPath);
      // Populate snapshots for *every* sibling sharing this apiPath. One
      // fetch satisfies y5/y10/all simultaneously, so switching between
      // them while expanded does no extra network work after the first call.
      for (final r in HashrateRange.values) {
        if (r.apiPath == apiPath) {
          _snapshots[r] = snapshotForRange(payload, r);
        }
      }
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
        _refetchIfStale(_activeRange);
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
