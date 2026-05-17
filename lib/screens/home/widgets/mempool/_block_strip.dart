import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../api/api.dart';
import '../../../../main.dart' show appRouteObserver;
import '../../../../services/app_haptics.dart';
import '../../../../theme/theme.dart';
import '_block_visuals.dart';

class BlockStrip extends StatefulWidget {
  const BlockStrip({super.key, required this.snapshot, required this.boxSize});

  final MempoolSnapshot snapshot;
  final double boxSize;

  @override
  State<BlockStrip> createState() => _BlockStripState();
}

class _BlockStripState extends State<BlockStrip>
    with RouteAware, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Persist the scroll controller across rebuilds so periodic refetches don't
  // reset the user's scroll position. We re-center the divider on:
  //   - first paint (post-frame, retried until the viewport has a width),
  //   - the projected-blocks count crossing the default-visible threshold
  //     (an empty-mempool first snapshot expands to 6 projected blocks),
  //   - returning to the home screen from a pushed route (didPopNext),
  //   - the app being resumed from background (didChangeAppLifecycleState).
  late final ScrollController _ctrl;
  int _lastCenteredProjectedCount = -1;
  // Per-block stride used to detect when a block edge crosses the viewport's
  // left edge. Recomputed in didUpdateWidget because boxSize tracks
  // text-scale.
  double _blockStride = 1;
  int _lastHapticBlockCount = 0;
  // Whether a recenter retry is already queued for the next frame, so we
  // don't pile up callbacks if multiple triggers fire before layout settles.
  bool _recenterRetryPending = false;
  // Safety cap on retries — if we somehow can't get a viewport after this
  // many frames, give up rather than reschedule forever.
  static const int _maxRecenterRetries = 30;
  int _recenterRetryCount = 0;

  // Slide animation state. Mirrors mempool.space: when a new block arrives
  // every visible slot shifts right by one stride, the rightmost-projected
  // crosses the divider into mined[0] (and re-styles as mined), and a fresh
  // slot enters from offscreen-left to take the leftmost-projected position.
  //
  // We model the strip as a unified list of slots (projected + mined) keyed
  // by stable identity; an AnimationController drives every slot's `left`
  // from its initial to target position. Driving the slide ourselves (rather
  // than via AnimatedPositioned) lets the crossing slot paint its background
  // as a split of projected/mined colors using the live animation value.
  static const Duration _slideDuration = Duration(milliseconds: 600);
  static const int _maxMined = 4;

  late final AnimationController _slideCtrl;
  late final Animation<double> _slideAnim;

  List<_Slot> _slots = const [];
  // Highest mined-height we've reconciled. New blocks must exceed this to
  // trigger the slide. Anything else is a refresh-in-place.
  int? _topHeight;

  void _onScroll() {
    if (!_ctrl.hasClients) return;
    final offset = _ctrl.offset;
    if (offset <= 0) {
      _lastHapticBlockCount = 0;
      return;
    }
    final count = (offset / _blockStride).floor();
    if (count != _lastHapticBlockCount) {
      _lastHapticBlockCount = count;
      AppHaptics.selection();
    }
  }

  @override
  void initState() {
    super.initState();
    _topHeight = widget.snapshot.mined.isNotEmpty
        ? widget.snapshot.mined.first.height
        : null;

    _blockStride = widget.boxSize + AppSpacing.sm;
    _ctrl = ScrollController()..addListener(_onScroll);
    _slideCtrl = AnimationController(vsync: this, duration: _slideDuration);
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);
    _slideCtrl.addStatusListener(_onSlideStatus);
    WidgetsBinding.instance.addObserver(this);
    // First-paint center. The scroll position isn't attached yet here; defer
    // to after the first layout so viewportDimension is available. Uses the
    // retry scheduler — see _scheduleRecenter for why a single post-frame
    // is not enough.
    _scheduleRecenter();
  }

  // Key for a mined slot. Mined blocks have stable heights from
  // mempool.space; the very-recent enrichment-lag case (height == null) gets
  // a positional fallback within this slide — the slot list is rebuilt for
  // every slide, so cross-slide identity isn't required.
  ValueKey<String> _minedSlotKey(MempoolBlock b, int positionInSlide) {
    final h = b.height;
    return h != null
        ? ValueKey<String>('mined-$h')
        : ValueKey<String>('mined-pos-$positionInSlide');
  }

  @override
  void didUpdateWidget(covariant BlockStrip oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Stride tracks boxSize, which tracks system text-scale.
    _blockStride = widget.boxSize + AppSpacing.sm;

    final projectedShown = widget.snapshot.projected.length.clamp(0, 8);
    if (_shouldRecenter(projectedShown)) {
      _scheduleRecenter();
    }

    final newMined = widget.snapshot.mined;
    if (newMined.isEmpty) {
      _topHeight = null;
      return;
    }

    final newTop = newMined.first.height;
    final oldTop = _topHeight;

    if (oldTop == null || (newTop != null && newTop > oldTop)) {
      // New block(s). Trigger the slide. We only animate the first new block
      // — multi-block batches are rare; the rest snap into place after the
      // slide finishes.
      _startSlide();
      _topHeight = newTop;
    }
  }

  /// Capture the current strip layout into [_slots], rotate everything right
  /// by one stride, and drive the slide via [_slideCtrl].
  void _startSlide() {
    final s = widget.snapshot;
    final projectedCount = s.projected.length.clamp(0, 8);

    // The "before" mined list — what's currently on screen. Reconstructed
    // from the new snapshot by dropping the new front entry; the new front
    // is what the rightmost-projected becomes at slide-end (after the
    // snapshot-based render takes over).
    final prevMined = s.mined.length > 1 ? s.mined.skip(1).toList() : <MempoolBlock>[];

    // Build the slot list: leftmost projected (idx 0) → rightmost projected
    // (idx projectedCount-1) → first mined (idx projectedCount) → last mined.
    final slots = <_Slot>[];

    // Insert the new "incoming projected" slot at -1 (offscreen left).
    // After the slide, it'll be at index 0 (leftmost projected).
    // Data: the next poll will refresh projected; for now, use the current
    // leftmost-projected as a placeholder so it doesn't render blank.
    final placeholder = s.projected.isNotEmpty
        ? s.projected.last
        : const MempoolBlock(medianFeeSatVb: null, txCount: 0);
    slots.add(_Slot(
      key: ValueKey<String>('incoming-${DateTime.now().microsecondsSinceEpoch}'),
      block: placeholder,
      initialIndex: -1,
      targetIndex: 0,
      kindAtTarget: BlockKind.projected,
      crossesDivider: false,
    ));

    // Existing projected blocks, reversed so display index 0 = leftmost.
    // Each shifts right by 1. The rightmost-projected crosses the divider
    // and becomes mined at slide-end — kindAtTarget = mined so its styling
    // lands correctly when the slide completes. During the slide, its
    // background is painted as a split of projected/mined colors based on
    // the live animation value, and its content is forced to projected
    // (label/fee) until slide-end when the snapshot-based render takes over.
    for (var displayIdx = 0; displayIdx < projectedCount; displayIdx++) {
      // s.projected is fee-priority order: [0] = highest priority = rightmost
      // (next-to-divider). Display order is reversed: leftmost shows the
      // longest-ETA (last in array). So display index 0 → s.projected[count-1].
      final dataIdx = projectedCount - 1 - displayIdx;
      final block = s.projected[dataIdx];
      final crosses = displayIdx == projectedCount - 1;
      slots.add(_Slot(
        key: ValueKey<String>('projected-pos-$displayIdx'),
        block: block,
        initialIndex: displayIdx,
        targetIndex: displayIdx + 1,
        kindAtTarget: crosses ? BlockKind.mined : BlockKind.projected,
        crossesDivider: crosses,
      ));
    }

    // Existing mined blocks. Each shifts right by 1.
    for (var minedIdx = 0; minedIdx < prevMined.length; minedIdx++) {
      final block = prevMined[minedIdx];
      slots.add(_Slot(
        key: _minedSlotKey(block, minedIdx),
        block: block,
        initialIndex: projectedCount + minedIdx,
        targetIndex: projectedCount + minedIdx + 1,
        kindAtTarget: BlockKind.mined,
        crossesDivider: false,
      ));
    }

    setState(() {
      _slots = slots;
    });

    _slideCtrl
      ..stop()
      ..value = 0
      ..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _slideCtrl.removeStatusListener(_onSlideStatus);
    _slideCtrl.dispose();
    _ctrl.removeListener(_onScroll);
    _ctrl.dispose();
    super.dispose();
  }

  void _onSlideStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    setState(() {
      _slots = const [];
    });
  }

  // Re-center the divider when the home screen is revealed again after a
  // pushed route (Settings, Converter, etc.) pops, or after the app returns
  // from the background. Viewport width is already known in both cases, so
  // we just jumpTo directly.
  @override
  void didPopNext() => _scheduleRecenter();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleRecenter();
  }

  // Schedule a recenter for the next frame, retrying on subsequent frames if
  // the scroll view hasn't attached its position yet or reports a zero
  // viewport. The first post-frame after mount usually succeeds, but in some
  // layout-deferred scenarios (the strip mounting inside a sliver that lays
  // out late, a frame where the parent reports a stale zero viewport, etc.)
  // the first attempt silently early-returns and the strip lands wherever
  // the framework's initial offset put it — which is what produced the
  // "loaded all the way left" / "all the way right" bug.
  void _scheduleRecenter() {
    if (_recenterRetryPending) return;
    _recenterRetryPending = true;
    _recenterRetryCount = 0;
    WidgetsBinding.instance.addPostFrameCallback(_recenterAttempt);
  }

  void _recenterAttempt(Duration _) {
    if (!mounted) {
      _recenterRetryPending = false;
      return;
    }
    if (_recenterDivider()) {
      _recenterRetryPending = false;
      return;
    }
    if (_recenterRetryCount >= _maxRecenterRetries) {
      _recenterRetryPending = false;
      return;
    }
    _recenterRetryCount++;
    WidgetsBinding.instance.addPostFrameCallback(_recenterAttempt);
  }

  bool _recenterDivider() {
    if (!mounted || !_ctrl.hasClients) return false;
    if (_ctrl.position.viewportDimension <= 0) return false;
    final projectedShown = widget.snapshot.projected.length.clamp(0, 8);
    final target = _calculateDividerCenterScrollOffset(
      projectedShown: projectedShown,
      viewportWidth: _ctrl.position.viewportDimension,
      boxSize: widget.boxSize,
    );
    final clamped = target.clamp(
      _ctrl.position.minScrollExtent,
      _ctrl.position.maxScrollExtent,
    );
    _ctrl.jumpTo(clamped);
    _lastHapticBlockCount = (clamped / _blockStride).floor();
    _lastCenteredProjectedCount = projectedShown;
    return true;
  }

  bool _shouldRecenter(int projectedCount) {
    if (_lastCenteredProjectedCount < 0) return true;
    final wasShortOfDefault = _lastCenteredProjectedCount < 2;
    final nowMeetsDefault = projectedCount >= 2;
    return wasShortOfDefault && nowMeetsDefault;
  }

  // Layout math (left-edge positions in scroll content):
  //   [p_n-1]...[p0] <gap_sm/2><div><gap_sm/2> [m0][m1][m2][m3] <gap_sm> [link]
  // Each block has width = boxSize, gaps between projected blocks = sm,
  // gaps between mined blocks = sm, gap before link = sm. The divider is
  // kMempoolDividerWidth (= sm) wide.
  double _projectedLeftAt(int displayIndex) {
    // displayIndex = 0 is the leftmost-rendered projected (oldest, highest
    // ETA); displayIndex = count-1 is the rightmost (next-to-divider).
    return displayIndex * (widget.boxSize + AppSpacing.sm);
  }

  double _dividerLeft(int projectedCount) {
    // The rightmost-projected ends at projectedCount*(boxSize+sm) - sm; the
    // divider sits half a gap past that.
    return projectedCount * (widget.boxSize + AppSpacing.sm) - AppSpacing.sm / 2;
  }

  double _minedLeft(int minedIndex, int projectedCount) {
    final firstMinedLeft = _dividerLeft(projectedCount) +
        kMempoolDividerWidth +
        AppSpacing.sm / 2;
    return firstMinedLeft + minedIndex * (widget.boxSize + AppSpacing.sm);
  }

  double _linkLeft(int projectedCount) =>
      _minedLeft(_maxMined, projectedCount);

  double _stripWidth(int projectedCount) =>
      _linkLeft(projectedCount) + widget.boxSize;

  /// Convert a unified slot index into a left-edge position. Indices
  /// [0, projectedCount-1] are projected slots; [projectedCount, ...] are
  /// mined. Indices outside the visible range extrapolate (used so a slot
  /// entering at index -1 has a sane offscreen-left position, and so a slot
  /// exiting past _maxMined has a sane offscreen-right position).
  double _slotLeft(int index, int projectedCount) {
    if (index < projectedCount) {
      return index * (widget.boxSize + AppSpacing.sm);
    }
    return _minedLeft(index - projectedCount, projectedCount);
  }

  Widget _slotPositioned({
    required _Slot slot,
    required double t,
    required int projectedShown,
    required double dividerLeftPx,
    required double boxSize,
  }) {
    final initialLeft = _slotLeft(slot.initialIndex, projectedShown);
    final targetLeft = _slotLeft(slot.targetIndex, projectedShown);
    final left = ui.lerpDouble(initialLeft, targetLeft, t)!;

    // For the crossing slot, compute the fraction of the box that lies on the
    // mined side of the divider. The block's right edge starts at the divider
    // (fraction = 0) and ends a stride past it (fraction = 1) — but we cap at
    // the divider center so the projected/mined split tracks the visible line.
    double minedFraction = 0;
    if (slot.crossesDivider) {
      final blockRight = left + boxSize;
      final dividerCenter = dividerLeftPx + kMempoolDividerWidth / 2;
      final overshoot = (blockRight - dividerCenter).clamp(0.0, boxSize);
      minedFraction = overshoot / boxSize;
    }

    // Crossing slot's styling-kind is mined (lands correctly at slide-end),
    // but its content during the slide is projected data — render the
    // label/fee with projected formatting until the snapshot takes over.
    final renderAsProjected = slot.kindAtTarget == BlockKind.projected ||
        slot.crossesDivider;

    return Positioned(
      key: slot.key,
      left: left,
      top: 0,
      width: boxSize,
      height: boxSize,
      child: BlockBox(
        block: slot.block,
        kind: slot.kindAtTarget,
        width: boxSize,
        // For mined slots displayIndex/projectedCount aren't used for the
        // URL. For projected slots, targetIndex is the post-slide display
        // position (0..projectedCount-1).
        displayIndex: renderAsProjected
            ? slot.targetIndex.clamp(0, projectedShown - 1)
            : 0,
        projectedCount: projectedShown,
        minedFraction: minedFraction,
        contentAsProjected: renderAsProjected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final boxSize = widget.boxSize;
    final projectedShown = s.projected.length.clamp(0, 8);
    final stripHeight = boxSize;
    final stripWidth = _stripWidth(projectedShown);
    final sliding = _slots.isNotEmpty;

    final strip = SizedBox(
      height: stripHeight,
      child: SingleChildScrollView(
        controller: _ctrl,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: kMempoolStripPadding),
        child: SizedBox(
          width: stripWidth,
          height: boxSize,
          child: ClipRect(
            child: Stack(
              children: [
                if (sliding) ...[
                  AnimatedBuilder(
                    animation: _slideAnim,
                    builder: (context, _) {
                      final t = _slideAnim.value;
                      final dividerLeftPx = _dividerLeft(projectedShown);
                      return Stack(
                        children: [
                          for (final slot in _slots)
                            _slotPositioned(
                              slot: slot,
                              t: t,
                              projectedShown: projectedShown,
                              dividerLeftPx: dividerLeftPx,
                              boxSize: boxSize,
                            ),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  for (var i = projectedShown - 1; i >= 0; i--)
                    Positioned(
                      key: ValueKey<String>('proj-$i'),
                      left: _projectedLeftAt(projectedShown - 1 - i),
                      top: 0,
                      width: boxSize,
                      height: boxSize,
                      child: BlockBox(
                        block: s.projected[i],
                        kind: BlockKind.projected,
                        width: boxSize,
                        displayIndex: projectedShown - 1 - i,
                        projectedCount: projectedShown,
                        contentAsProjected: true,
                      ),
                    ),
                  for (var i = 0; i < s.mined.length; i++)
                    Positioned(
                      key: ValueKey<String>(
                        'mined-${s.mined[i].height ?? "i$i"}',
                      ),
                      left: _minedLeft(i, projectedShown),
                      top: 0,
                      width: boxSize,
                      height: boxSize,
                      child: BlockBox(
                        block: s.mined[i],
                        kind: BlockKind.mined,
                        width: boxSize,
                        displayIndex: 0,
                        projectedCount: projectedShown,
                        contentAsProjected: false,
                      ),
                    ),
                ],
                Positioned(
                  key: const ValueKey('divider'),
                  left: _dividerLeft(projectedShown),
                  top: 0,
                  width: kMempoolDividerWidth,
                  height: boxSize,
                  child: DashedDivider(height: boxSize),
                ),
                Positioned(
                  key: const ValueKey('link'),
                  left: _linkLeft(projectedShown),
                  top: 0,
                  width: boxSize,
                  height: boxSize,
                  child: LinkBlock(width: boxSize),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return strip;
  }
}

/// Pure: scroll offset that puts the divider at the horizontal center of the
/// viewport. Lifted out of [_BlockStripState] so the math is independently
/// readable and testable.
///
/// The divider sits between the rightmost-projected block and the first mined
/// block. Its left-edge position inside the scroll content is:
///   projectedShown * (boxSize + AppSpacing.sm) - AppSpacing.sm / 2
/// We then offset by kMempoolStripPadding (the scrollable's leading padding)
/// and target the divider's center (left + kMempoolDividerWidth / 2) at
/// viewportWidth / 2.
double _calculateDividerCenterScrollOffset({
  required int projectedShown,
  required double viewportWidth,
  required double boxSize,
}) {
  final dividerLeft =
      projectedShown * (boxSize + AppSpacing.sm) - AppSpacing.sm / 2;
  return kMempoolStripPadding +
      dividerLeft +
      kMempoolDividerWidth / 2 -
      viewportWidth / 2;
}

/// Render-state for one slot in a slide. Each slot represents a block that
/// will animate from `initialIndex` to `targetIndex`. The slot's left edge
/// is interpolated from the slide controller's value.
///
/// For the crossing slot (rightmost-projected becoming first-mined),
/// `kindAtTarget` is mined — that's the styling the slot lands on at
/// fraction = 1 — but `block` carries the projected data the user sees
/// during the slide (no mined height yet), so content is rendered as
/// projected for the whole slide. `crossesDivider` toggles the split-fill
/// painter that tracks the divider as the block moves across it.
class _Slot {
  _Slot({
    required this.key,
    required this.block,
    required this.initialIndex,
    required this.targetIndex,
    required this.kindAtTarget,
    required this.crossesDivider,
  });

  final ValueKey<String> key;
  final MempoolBlock block;
  final int initialIndex;
  final int targetIndex;
  final BlockKind kindAtTarget;
  final bool crossesDivider;
}
