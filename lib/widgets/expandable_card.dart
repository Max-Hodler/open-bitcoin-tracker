import 'package:flutter/material.dart';

/// Mixin that owns the expand/collapse animation state shared between
/// [HashrateCard] and [HomeHeader]: a controller, its curve, and a
/// "keep the body mounted across the collapse animation" gate so the
/// expandable subtree clips smoothly out of view instead of disappearing
/// in a single frame before the parent shrinks.
///
/// Usage:
/// ```
/// class _MyCardState extends State<MyCard>
///     with SingleTickerProviderStateMixin, ExpandableCardStateMixin<MyCard> {
///   @override
///   bool get initiallyExpanded => widget.startOpen;
///
///   @override
///   Widget build(BuildContext context) {
///     return Column(children: [
///       MyHeader(onTap: () => setExpanded(!isExpanded)),
///       if (expansionMounted)
///         SizeTransition(sizeFactor: expandCurve, child: MyBody()),
///     ]);
///   }
/// }
/// ```
///
/// The host State must also mix in [SingleTickerProviderStateMixin] (or any
/// other [TickerProvider]) for the controller's vsync.
mixin ExpandableCardStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  /// Overridden by the host to seed the initial state. `true` skips the
  /// open animation so the first frame after launch matches persisted state.
  bool get initiallyExpanded => false;

  /// Override to customize duration. Defaults to 260ms — the shared cadence
  /// across the home screen's expand/collapse interactions.
  Duration get expandDuration => const Duration(milliseconds: 260);

  late final AnimationController _expand;
  late final CurvedAnimation _expandCurve;
  bool _expansionMounted = false;

  /// Eased curve. Pass to `SizeTransition.sizeFactor`.
  Animation<double> get expandCurve => _expandCurve;

  /// True while the expandable body should be in the tree. Stays true through
  /// a collapse animation so the body clips smoothly; flips false after the
  /// controller reaches dismissed.
  bool get expansionMounted => _expansionMounted;

  /// True if expansion is currently shown or animating in. Useful for tap
  /// handlers that toggle direction.
  bool get isExpanded =>
      _expand.status == AnimationStatus.forward ||
      _expand.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    final start = initiallyExpanded;
    _expansionMounted = start;
    _expand = AnimationController(
      vsync: this,
      duration: expandDuration,
      value: start ? 1.0 : 0.0,
    )..addStatusListener(_onExpandStatus);
    _expandCurve = CurvedAnimation(
      parent: _expand,
      curve: Curves.easeInOutCubic,
    );
  }

  void _onExpandStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _expansionMounted) {
      setState(() => _expansionMounted = false);
    }
  }

  /// Drive the open or close animation. Mounts the body before opening so the
  /// first frame of the open animation has something to grow.
  void setExpanded(bool expanded) {
    if (expanded == isExpanded) return;
    if (expanded) {
      setState(() => _expansionMounted = true);
      _expand.forward();
    } else {
      _expand.reverse();
    }
  }

  @override
  void dispose() {
    _expand.removeStatusListener(_onExpandStatus);
    _expandCurve.dispose();
    _expand.dispose();
    super.dispose();
  }
}
