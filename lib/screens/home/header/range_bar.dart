import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_enums.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../services/app_haptics.dart';
import '../../../state/state.dart';
import '../../../theme/theme.dart';

// Stable, sorted lists for each overflow slot's candidates.
final List<BtcRange> _overflowDaysRanges = btcRangeDays;
final List<BtcRange> _overflowWeeksRanges = btcRangeWeeks;

// Ranges the user can mount in each overflow slot. Derived from the enum
// getters so adding a new value to the enum automatically picks it up here.
final List<BtcRange> _overflowMonthsRanges = btcRangeMonths;
final List<BtcRange> _overflowMenuRanges = btcRangeYears;

class RangeBar extends StatefulWidget {
  const RangeBar({
    super.key,
    required this.range,
    required this.onRange,
    required this.chartColor,
    this.onSettings,
  });

  final BtcRange range;
  final ValueChanged<BtcRange> onRange;
  final Color chartColor;
  // When non-null, a circular settings button is shown to the right of the
  // grey track, vertically aligned with it. Null hides the button.
  final VoidCallback? onSettings;

  @override
  State<RangeBar> createState() => _RangeBarState();
}

class _RangeBarState extends State<RangeBar>
    with TickerProviderStateMixin {
  // One key per range chip (in row order) so we can measure the selected chip's
  // laid-out rect and slide a single shared pill to it. The settings button is
  // not a selectable chip, so it has no key.
  static const int _rangeChipCount = 5;
  final List<GlobalKey> _chipKeys =
      List.generate(_rangeChipCount, (_) => GlobalKey());

  // Drives the vertical "nudge" the pill makes when the user swipes up/down on
  // it to cycle the range within a slot (1D→2D→…). The pill kicks a few pixels
  // in the swipe direction and springs back, so the gesture has visible
  // feedback. _nudgeDir is -1 for an up-swipe, +1 for down.
  late final AnimationController _nudgeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => setState(() {}))
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        setState(() {}); // lets build() re-evaluate _syncHintBob
      }
    });
  int _nudgeDir = 0;
  // Peak vertical travel of the nudge, in logical pixels.
  static const double _nudgeAmplitude = 6;

  // Kicks the pill in [dir] (-1 up, +1 down) and springs it back. Called when a
  // swipe cycles the slot's range; the slot itself doesn't move, so this is the
  // only motion that signals the change.
  void _nudgePill(int dir) {
    _hintBobController.stop();
    _nudgeDir = dir;
    _nudgeController.forward(from: 0);
  }

  // Current vertical offset of the nudge: a single up-then-back arc (sine) so it
  // eases out and returns to rest, scaled by direction and amplitude.
  double get _nudgeOffset =>
      _nudgeDir * _nudgeAmplitude * math.sin(_nudgeController.value * math.pi);

  // Drives the idle hint animation that bobs the pill up and down while the
  // swipe-chip tip is visible. Runs a slow repeating sine wave; paused when
  // the hint is dismissed, the pill is being dragged, or a real nudge fires.
  late final AnimationController _hintBobController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..addListener(() => setState(() {}));

  static const double _hintBobAmplitude = 5;

  // Current vertical offset from the idle hint bob. Produces a full sine cycle
  // (up → rest → down → rest) so the motion looks like a gentle invitation.
  double get _hintBobOffset =>
      _hintBobAmplitude * math.sin(_hintBobController.value * 2 * math.pi);

  // Latches to true the first time the user selects a non-All range while the
  // hint hasn't yet been dismissed. Once set it never clears (within the
  // session), so tapping back to All — or navigating to a full-screen page —
  // does NOT hide the hint. Only a vertical swipe on the pill dismisses it.
  bool _hintTriggered = false;

  // Starts or stops the hint bob depending on whether the tip is currently
  // visible. Called from build whenever the hint-dismissed flag changes.
  void _syncHintBob({required bool hintVisible}) {
    if (hintVisible && !_dragging && !_nudgeController.isAnimating) {
      if (!_hintBobController.isAnimating) {
        _hintBobController.value = 0;
        _hintBobController.repeat();
      }
    } else {
      _hintBobController.stop();
    }
  }

  @override
  void dispose() {
    _visualSelectTimer?.cancel();
    _nudgeController.dispose();
    _hintBobController.dispose();
    super.dispose();
  }
  // Key for the Stack the pill is positioned within — its render box is the
  // coordinate frame we resolve each chip's rect into.
  final GlobalKey _stackKey = GlobalKey();

  // Each range chip's rect, in the Stack's local coordinates, indexed by slot.
  // Empty until the first post-frame measurement lands; the pill is hidden
  // until then so it never flashes at the wrong spot. We measure every chip
  // (not just the selected one) so a drag can map the finger position to a slot
  // and snap to it.
  List<Rect> _chipRects = const [];

  // Per-slot width of just the label text (no chip padding), supplied by the
  // build. Used to highlight a hovered slot only once the dragged pill's center
  // is actually over the range's name — not as soon as it enters the padded
  // chip box. Empty until the first build populates it.
  List<double> _chipLabelWidths = const [];

  // While the user is dragging the pill, this holds its free left edge (Stack
  // coordinates); null when not dragging. During a drag the pill follows the
  // finger un-animated; on release it snaps to the nearest slot.
  double? _dragLeft;
  // Slot the drag started on, and the slot the pill currently overlaps. The
  // hovered slot's label is highlighted as the pill passes over it, and on
  // release we commit that slot's range if it differs from where we started.
  int _dragStartIndex = -1;
  int _dragHoverIndex = -1;

  bool get _dragging => _dragLeft != null;

  // The slot whose label shows the selected styling (bold + chart color +
  // flick-hint chevrons). It lags the real selected slot: when a tap picks a
  // new range, the pill starts gliding immediately and the label's selected
  // styling fades in shortly after — partway through the glide, not only on
  // arrival — so the highlight feels responsive while still trailing the pill.
  // -1 until the first build resolves the initial selection. Drags bypass this
  // and highlight the hovered slot directly.
  int _visualSelectedIndex = -1;

  // Pending flip of [_visualSelectedIndex] onto a newly tapped slot. Fired a
  // short way into the pill's glide so the label fade overlaps the pill's
  // motion instead of waiting for it to finish (the old onEnd-only behavior
  // left the highlight feeling late). The pill's onEnd is still a backstop in
  // case the glide is interrupted before this fires.
  Timer? _visualSelectTimer;
  // The slot the pending [_visualSelectTimer] will flip to; -1 when no flip is
  // scheduled. Lets a build detect when the tap target changed mid-glide and
  // reschedule for the new slot instead of firing on a stale one.
  int _visualSelectTarget = -1;
  // How long after a tap the label starts adopting the selected styling. Kept
  // well under the pill's 260ms glide so the fade and the slide finish at about
  // the same time.
  static const Duration _visualSelectLead = Duration(milliseconds: 90);

  // Re-measures every chip and, if any moved, updates [_chipRects] so the pill
  // can slide to the selected slot (and a drag can resolve slot boundaries).
  // Runs after every frame the bar lays out (selection change, label-width
  // change, text-scale change). Skipped mid-drag so measurement churn doesn't
  // fight the finger-driven position.
  void _measureChips() {
    if (_dragging) return;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;
    final rects = <Rect>[];
    for (final key in _chipKeys) {
      final chipBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (chipBox == null || !chipBox.hasSize) return; // not laid out yet
      final topLeft = stackBox.globalToLocal(chipBox.localToGlobal(Offset.zero));
      rects.add(topLeft & chipBox.size);
    }
    if (!_rectsEqual(rects, _chipRects)) {
      setState(() => _chipRects = rects);
    }
  }

  static bool _rectsEqual(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // The label's horizontal span within slot [index]'s chip rect: the label is
  // centered in the chip, so this is a [labelWidth]-wide band around the chip
  // center. Used to decide when the dragged pill's center has "reached the name"
  // and the slot should flip to its selected styling.
  ({double left, double right})? _labelSpan(int index) {
    if (index < 0 ||
        index >= _chipRects.length ||
        index >= _chipLabelWidths.length) {
      return null;
    }
    final center = _chipRects[index].center.dx;
    final half = _chipLabelWidths[index] / 2;
    return (left: center - half, right: center + half);
  }

  // Slot whose label band horizontally contains [centerX], or -1 if the pill's
  // center sits in the padding/gap between names. Drives the live hover
  // highlight: a slot only goes "selected" once the pill center is over its
  // name, not merely inside its (padded) chip box.
  int _slotForLabel(double centerX) {
    for (var i = 0; i < _chipRects.length; i++) {
      final span = _labelSpan(i);
      if (span != null && centerX >= span.left && centerX <= span.right) {
        return i;
      }
    }
    return -1;
  }

  void _onPillDragStart(int selectedIndex, DragStartDetails _) {
    if (_chipRects.isEmpty) return;
    _hintBobController.stop();
    // Drop any pending tap-driven flip; the drag highlights the hovered slot
    // directly and the timer would otherwise fire on the old tap target.
    _visualSelectTimer?.cancel();
    _visualSelectTarget = -1;
    setState(() {
      _dragStartIndex = selectedIndex;
      _dragHoverIndex = selectedIndex;
      _dragLeft = _chipRects[selectedIndex].left;
    });
  }

  void _onPillDragUpdate(DragUpdateDetails d) {
    final left = _dragLeft;
    if (left == null || _chipRects.isEmpty) return;
    final width = _chipRects[_dragStartIndex].width;
    // Clamp the pill within the span of the first and last range chips so it
    // can't be dragged off the track or under the settings button.
    final minLeft = _chipRects.first.left;
    final maxLeft = _chipRects.last.right - width;
    final next = (left + d.delta.dx).clamp(minLeft, maxLeft);
    // Highlight a slot only once the pill's center is over that slot's name; in
    // the padding/gap between names keep the last highlighted slot rather than
    // flipping early or going blank.
    final overLabel = _slotForLabel(next + width / 2);
    final hover = overLabel >= 0 ? overLabel : _dragHoverIndex;
    setState(() {
      _dragLeft = next;
      if (hover != _dragHoverIndex) {
        _dragHoverIndex = hover;
        AppHaptics.selection();
      }
    });
  }

  void _onPillDragEnd(DragEndDetails _) {
    final landedIndex = _dragHoverIndex;
    final startIndex = _dragStartIndex;
    setState(() {
      _dragLeft = null;
      _dragStartIndex = -1;
      _dragHoverIndex = -1;
      // The pill is already at the finger (the landed slot), so style that slot
      // selected immediately — there's no glide to lag behind, and leaving the
      // visual index on the start slot would flicker it bold during the snap.
      if (landedIndex >= 0) _visualSelectedIndex = landedIndex;
    });
    // Commit the new range only if the pill ended on a different slot. The
    // AnimatedPositioned then snaps the pill onto that slot's measured rect.
    if (landedIndex >= 0 && landedIndex != startIndex) {
      AppHaptics.light();
      _selectSlot(landedIndex);
    }
  }

  void _onPillDragCancel() {
    setState(() {
      _dragLeft = null;
      _dragStartIndex = -1;
      _dragHoverIndex = -1;
    });
  }

  // Activates the range mounted in slot [index] (row order: days, weeks,
  // months, years overflow slots, then All). Reads each overflow slot's current
  // value from the notifier so a drag selects exactly what tapping that chip
  // would.
  void _selectSlot(int index) {
    final app = context.read<AppStateNotifier>();
    final range = switch (index) {
      0 => app.daysOverflowQuickRange,
      1 => app.weeksOverflowQuickRange,
      2 => app.monthsOverflowQuickRange,
      3 => app.overflowQuickRange,
      _ => BtcRange.all,
    };
    widget.onRange(range);
  }

  @override
  Widget build(BuildContext context) {
    final range = widget.range;
    final onRange = widget.onRange;
    final chartColor = widget.chartColor;
    final onSettings = widget.onSettings;
    // Select just the four overflow slots instead of watching the whole
    // notifier — the bar sits in the per-tick header subtree, so an app-state
    // notification (converter keystroke, hint dismissal, …) must not drag it
    // into the rebuild.
    final swipeHintDismissed = context.select<AppStateNotifier, bool>(
      (a) => a.swipeChipHintDismissed,
    );
    // Latch: once the user has been on a non-All range the hint is "active".
    // Selecting All again (or navigating away) must NOT clear it — only a
    // vertical swipe on the pill dismisses the hint.
    if (widget.range != BtcRange.all && !swipeHintDismissed) {
      _hintTriggered = true;
    }
    final hintVisible = _hintTriggered && !swipeHintDismissed && widget.range != BtcRange.all;
    _syncHintBob(hintVisible: hintVisible);
    final daysOverflowSlot = context.select<AppStateNotifier, BtcRange>(
      (a) => a.daysOverflowQuickRange,
    );
    final weeksOverflowSlot = context.select<AppStateNotifier, BtcRange>(
      (a) => a.weeksOverflowQuickRange,
    );
    final overflowSlot = context.select<AppStateNotifier, BtcRange>(
      (a) => a.overflowQuickRange,
    );
    final monthsOverflowSlot = context.select<AppStateNotifier, BtcRange>(
      (a) => a.monthsOverflowQuickRange,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    // 1.4 matches the Inter body line-height (AppTypography.body height: 1.4).
    // Floor at 24 so the icon on overflow chips doesn't overflow at textScale=1.
    final labelRow = math.max<double>(textScaler.scale(14) * 1.4, 24);
    // Inner horizontal padding of the recessed track around the chip row.
    const trackPadding = 2.0;
    // Expected chip content height (text + vertical padding) — used to center
    // the grey track within the chip row via trackInset.
    final chipHeight = labelRow + 16;
    const greyBarHeight = 28.0;
    // Width floor for each chip's label. Two reasons we need this:
    //   1. Selecting a chip flips its weight to w600, which is wider than the
    //      regular weight — so without a floor the chip grows on selection
    //      and `spaceBetween` shifts every neighbor.
    //   2. The overflow chip's label cycles through 1Y..15Y and the digit
    //      count changes its width.
    // Measured against the actual rendered (bold) style so it tracks the
    // system font scale.
    final boldStyle = AppTypography.body.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    double labelWidth(String label) => _maxLabelWidth(
          context: context,
          labels: [label],
          style: boldStyle,
          textScaler: textScaler,
        );
    // Years chip floor: widest of all overflow-menu labels, since the chip
    // can show any of them.
    final overflowLabelWidth = _maxLabelWidth(
      context: context,
      labels: [
        for (final r in _overflowMenuRanges) _btcRangeLabel(context, r),
      ],
      style: boldStyle,
      textScaler: textScaler,
    );
    // Months chip floor: same idea for the months overflow chip (1M..12M).
    final monthsOverflowLabelWidth = _maxLabelWidth(
      context: context,
      labels: [
        for (final r in _overflowMonthsRanges) _btcRangeLabel(context, r),
      ],
      style: boldStyle,
      textScaler: textScaler,
    );
    // Days chip floor: widest of 1D..7D labels.
    final daysOverflowLabelWidth = _maxLabelWidth(
      context: context,
      labels: [
        for (final r in _overflowDaysRanges) _btcRangeLabel(context, r),
      ],
      style: boldStyle,
      textScaler: textScaler,
    );
    // Weeks chip floor: widest of 1W..4W labels.
    final weeksOverflowLabelWidth = _maxLabelWidth(
      context: context,
      labels: [
        for (final r in _overflowWeeksRanges) _btcRangeLabel(context, r),
      ],
      style: boldStyle,
      textScaler: textScaler,
    );
    // Layout: <days slot>, <weeks slot>, <months slot>, <years slot>, All. Both overflow slots
    // are user-customizable (long-press to change) and All sits at the end. The row distributes chips across the available width with
    // spaceBetween, but when natural chip widths exceed the screen (large
    // system text), it scrolls horizontally so every chip stays reachable.
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final horizontalPadding = isLandscape ? 32.0 : AppSpacing.md;
    // The whole row sits inside a recessed, pill-shaped track (segmented-control
    // look). The track's inner padding (trackPadding, above) keeps the selected
    // pill and the first/last labels off its rounded edge.
    final cs = Theme.of(context).colorScheme;
    final trackFill = context.palette.recessedSurface ?? cs.surfaceContainer;

    // Which of the five range chips is selected (row order: days, weeks,
    // months, years, All); -1 if none, which hides the sliding pill.
    final selectedIndex = range == daysOverflowSlot
        ? 0
        : range == weeksOverflowSlot
            ? 1
            : range == monthsOverflowSlot
                ? 2
                : range == overflowSlot
                    ? 3
                    : range == BtcRange.all
                        ? 4
                        : -1;

    // Per-slot label-text widths (row order), so a drag highlights a slot only
    // once the pill's center is over the name. The first four are each slot's
    // cycling-label floor; the All slot uses its own label width (without the
    // +18 chip padding the chip reserves for tap area).
    final allLabelWidth = labelWidth(_btcRangeLabel(context, BtcRange.all));
    _chipLabelWidths = [
      daysOverflowLabelWidth,
      weeksOverflowLabelWidth,
      monthsOverflowLabelWidth,
      overflowLabelWidth,
      allLabelWidth,
    ];

    // Build each range chip wrapped in an Expanded slot. The measurement key
    // goes on the chip itself (not the slot), so the pill hugs the chip's
    // label-sized box rather than the full slot width.
    Widget rangeSlot(int index, Widget chip) => Expanded(
          child: Center(child: KeyedSubtree(key: _chipKeys[index], child: chip)),
        );

    // Pill geometry: while dragging it follows the finger (free left, fixed at
    // the start slot's width); otherwise it sits on the selected chip's rect.
    // A vertical nudge (from a swipe that cycles the slot's range) shifts top by
    // _nudgeOffset; it's not applied while dragging.
    final selectedRect = (selectedIndex >= 0 && selectedIndex < _chipRects.length)
        ? _chipRects[selectedIndex]
        : null;
    final Rect? pillRect;
    if (_dragging && _dragStartIndex >= 0 &&
        _dragStartIndex < _chipRects.length) {
      final base = _chipRects[_dragStartIndex];
      pillRect = Rect.fromLTWH(_dragLeft!, base.top, base.width, base.height);
    } else if (selectedRect != null) {
      // Real nudge (user swipe) takes priority over the idle hint bob.
      final verticalOffset = _nudgeController.isAnimating
          ? _nudgeOffset
          : (_hintBobController.isAnimating ? _hintBobOffset : 0.0);
      pillRect = selectedRect.translate(0, verticalOffset);
    } else {
      pillRect = null;
    }
    // Seed the lagged visual index on the first build, and snap it straight to
    // the selection whenever there's no pill glide to wait for — either the
    // initial paint (-1), or there's no rendered pill (rects not measured yet,
    // or nothing selected) so the pill's onEnd will never fire to catch it up.
    if (_visualSelectedIndex == -1 || pillRect == null) {
      _visualSelectTimer?.cancel();
      _visualSelectTarget = -1;
      _visualSelectedIndex = selectedIndex;
    } else if (!_dragging && _visualSelectedIndex != selectedIndex) {
      // A tap moved the selection and the pill is gliding to it. Flip the label
      // to selected a short way into the glide so the fade overlaps the slide
      // rather than starting only when the pill lands. Reschedule if the target
      // changed (a second tap mid-glide) so the timer never fires on a stale
      // slot.
      if (_visualSelectTarget != selectedIndex) {
        _visualSelectTimer?.cancel();
        _visualSelectTarget = selectedIndex;
        final target = selectedIndex;
        _visualSelectTimer = Timer(_visualSelectLead, () {
          _visualSelectTarget = -1;
          if (!mounted || _dragging) return;
          setState(() => _visualSelectedIndex = target);
        });
      }
    }
    // The hovered slot's label is highlighted while dragging; otherwise the
    // *visually* selected slot is — which lags the real selection until the
    // pill finishes gliding (the pill below tracks selectedIndex directly, so
    // it moves first and the label flips bold/orange only on arrival).
    final highlightIndex = _dragging ? _dragHoverIndex : _visualSelectedIndex;
    bool slotSelected(int index) => index == highlightIndex;
    // Combined vertical offset for the selected chip's content (label).
    // Real nudge wins; idle hint bob fills in when actively running.
    final chipContentOffsetY = _nudgeController.isAnimating
        ? _nudgeOffset
        : (_hintBobController.isAnimating ? _hintBobOffset : 0.0);
    // Room reserved above and below the chip row so the pill's drop-shadow
    // (and its swipe-nudge travel) isn't clipped by the bar's box. The shadow
    // falls downward (offset 0,1 + blur), so the bottom needs more than the top
    // — the top only has to clear the upward nudge.
    const shadowBleedTop = 7.0;
    const shadowBleedBottom = 11.0;
    return LayoutBuilder(
        builder: (context, constraints) {
          // When a settings circle is shown it sits to the right of the track,
          // separated by a small gap. Reserve that space so the track doesn't
          // extend underneath it.
          const settingsGap = 8.0;
          final settingsReserve = onSettings != null
              ? greyBarHeight + settingsGap + (36 - greyBarHeight) / 2
              : 0.0;
          final rightPadding = horizontalPadding + settingsReserve;
          final innerWidth = constraints.maxWidth -
              horizontalPadding -
              rightPadding -
              trackPadding * 2;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _measureChips(),
          );
          // Vertical inset that makes the grey track shorter than the chips.
          final trackInset = (chipHeight - greyBarHeight) / 2;
          // Vertical position of the circle's top edge within the LayoutBuilder
          // — shadow bleed above + chip row's top inset to the grey bar.
          final circleTop = shadowBleedTop + trackInset;
          return Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  shadowBleedTop,
                  rightPadding,
                  shadowBleedBottom,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Grey track — inset vertically so it's shorter than the chip
                    // row, letting the pill overflow it top and bottom.
                    Positioned.fill(
                      top: trackInset,
                      bottom: trackInset,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: trackFill,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: trackPadding),
                  child: SizedBox(
                    width: innerWidth,
                    child: Stack(
                      key: _stackKey,
                      clipBehavior: Clip.none,
                      children: [
                      // The single sliding pill, behind the chips. When idle it
                      // animates its left/top/width/height between the previous
                      // and new selected-chip rects, so selecting a range glides
                      // the pill over. While dragging — or while a swipe-nudge is
                      // running — the duration is zero so the pill tracks the
                      // finger / nudge curve 1:1 instead of lagging behind the
                      // implicit tween.
                      if (pillRect != null)
                        AnimatedPositioned(
                          duration: (_dragging ||
                                  _nudgeController.isAnimating ||
                                  _hintBobController.isAnimating)
                              ? Duration.zero
                              : const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          // Once the pill arrives at the newly selected slot,
                          // flip that slot's label to its selected styling. Skip
                          // while dragging — the hovered label is driven live by
                          // _dragHoverIndex, not this lagged index.
                          onEnd: () {
                            if (!_dragging &&
                                _visualSelectedIndex != selectedIndex) {
                              setState(() =>
                                  _visualSelectedIndex = selectedIndex);
                            }
                          },
                          left: pillRect.left,
                          top: pillRect.top,
                          width: pillRect.width,
                          height: pillRect.height,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: _dragging ? 0.20 : 0.12,
                                      ),
                                      offset: const Offset(0, 1),
                                      blurRadius: _dragging ? 6 : 3,
                                    ),
                                  ],
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          rangeSlot(
                            0,
                            _RangeChipWithPct(
                              label: _btcRangeLabel(context, daysOverflowSlot),
                              selected: slotSelected(0),
                              onTap: () => slotSelected(0)
                                  ? _showDaysOverflowSlotPicker(context)
                                  : onRange(daysOverflowSlot),
                              onLongPress: () =>
                                  _showDaysOverflowSlotPicker(context),
                              onSwipeUp: () {
                                _nudgePill(-1);
                                _stepDaysOverflowSlot(context, 1);
                              },
                              onSwipeDown: () {
                                _nudgePill(1);
                                _stepDaysOverflowSlot(context, -1);
                              },
                              contentOffsetY: slotSelected(0) ? chipContentOffsetY : 0,
                              rollDirection: _nudgeDir == 0 ? 1 : _nudgeDir,
                              chartColor: chartColor,
                              minLabelWidth: daysOverflowLabelWidth,
                            ),
                          ),
                          rangeSlot(
                            1,
                            _RangeChipWithPct(
                              label: _btcRangeLabel(context, weeksOverflowSlot),
                              selected: slotSelected(1),
                              onTap: () => slotSelected(1)
                                  ? _showWeeksOverflowSlotPicker(context)
                                  : onRange(weeksOverflowSlot),
                              onLongPress: () =>
                                  _showWeeksOverflowSlotPicker(context),
                              onSwipeUp: () {
                                _nudgePill(-1);
                                _stepWeeksOverflowSlot(context, 1);
                              },
                              onSwipeDown: () {
                                _nudgePill(1);
                                _stepWeeksOverflowSlot(context, -1);
                              },
                              contentOffsetY: slotSelected(1) ? chipContentOffsetY : 0,
                              rollDirection: _nudgeDir == 0 ? 1 : _nudgeDir,
                              chartColor: chartColor,
                              minLabelWidth: weeksOverflowLabelWidth,
                            ),
                          ),
                          rangeSlot(
                            2,
                            _RangeChipWithPct(
                              label:
                                  _btcRangeLabel(context, monthsOverflowSlot),
                              selected: slotSelected(2),
                              onTap: () => slotSelected(2)
                                  ? _showMonthsOverflowSlotPicker(context)
                                  : onRange(monthsOverflowSlot),
                              onLongPress: () =>
                                  _showMonthsOverflowSlotPicker(context),
                              onSwipeUp: () {
                                _nudgePill(-1);
                                _stepMonthsOverflowSlot(context, 1);
                              },
                              onSwipeDown: () {
                                _nudgePill(1);
                                _stepMonthsOverflowSlot(context, -1);
                              },
                              contentOffsetY: slotSelected(2) ? chipContentOffsetY : 0,
                              rollDirection: _nudgeDir == 0 ? 1 : _nudgeDir,
                              chartColor: chartColor,
                              minLabelWidth: monthsOverflowLabelWidth,
                            ),
                          ),
                          rangeSlot(
                            3,
                            _RangeChipWithPct(
                              label: _btcRangeLabel(context, overflowSlot),
                              selected: slotSelected(3),
                              onTap: () => slotSelected(3)
                                  ? _showOverflowSlotPicker(context)
                                  : onRange(overflowSlot),
                              onLongPress: () =>
                                  _showOverflowSlotPicker(context),
                              onSwipeUp: () {
                                _nudgePill(-1);
                                _stepOverflowSlot(context, 1);
                              },
                              onSwipeDown: () {
                                _nudgePill(1);
                                _stepOverflowSlot(context, -1);
                              },
                              contentOffsetY: slotSelected(3) ? chipContentOffsetY : 0,
                              rollDirection: _nudgeDir == 0 ? 1 : _nudgeDir,
                              chartColor: chartColor,
                              minLabelWidth: overflowLabelWidth,
                            ),
                          ),
                          rangeSlot(
                            4,
                            _RangeChipWithPct(
                              label: _btcRangeLabel(context, BtcRange.all),
                              selected: slotSelected(4),
                              onTap: () => onRange(BtcRange.all),
                              chartColor: chartColor,
                              minLabelWidth: allLabelWidth + 18,
                            ),
                          ),
                        ],
                      ),
                      // Transparent drag handle on top of the pill. Sized and
                      // positioned to the pill so a horizontal drag starting on
                      // it slides the pill; it's translucent, so plain taps fall
                      // through to the chips underneath (which handle selection
                      // and the swipe-to-cycle gesture). Sits last in the Stack
                      // so it wins the horizontal-drag arena over the chips.
                      if (selectedRect != null)
                        Positioned.fromRect(
                          rect: pillRect ?? selectedRect,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragStart: (d) =>
                                _onPillDragStart(selectedIndex, d),
                            onHorizontalDragUpdate: _onPillDragUpdate,
                            onHorizontalDragEnd: _onPillDragEnd,
                            onHorizontalDragCancel: _onPillDragCancel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
              ),
              if (onSettings != null)
                Positioned(
                  right: horizontalPadding + (36 - greyBarHeight) / 2,
                  top: circleTop,
                  width: greyBarHeight,
                  height: greyBarHeight,
                  child: _SettingsCircle(
                    onTap: onSettings,
                    fill: trackFill,
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          );
        },
      );
  }

  Future<void> _showDaysOverflowSlotPicker(BuildContext context) =>
      _showOverflowPicker(
        context,
        ranges: _overflowDaysRanges,
        keyPrefix: 'daysOverflowSlot',
        getCurrent: (a) => a.daysOverflowQuickRange,
        setCurrent: (a, v) => a.setDaysOverflowQuickRange(v),
        longLabel: _btcRangeDaysLongLabel,
      );

  void _stepDaysOverflowSlot(BuildContext context, int step) =>
      _stepSlot(
        context,
        step: step,
        ranges: _overflowDaysRanges,
        getCurrent: (a) => a.daysOverflowQuickRange,
        setCurrent: (a, v) => a.setDaysOverflowQuickRange(v),
      );

  Future<void> _showWeeksOverflowSlotPicker(BuildContext context) =>
      _showOverflowPicker(
        context,
        ranges: _overflowWeeksRanges,
        keyPrefix: 'weeksOverflowSlot',
        getCurrent: (a) => a.weeksOverflowQuickRange,
        setCurrent: (a, v) => a.setWeeksOverflowQuickRange(v),
        longLabel: _btcRangeWeeksLongLabel,
      );

  void _stepWeeksOverflowSlot(BuildContext context, int step) =>
      _stepSlot(
        context,
        step: step,
        ranges: _overflowWeeksRanges,
        getCurrent: (a) => a.weeksOverflowQuickRange,
        setCurrent: (a, v) => a.setWeeksOverflowQuickRange(v),
      );

  Future<void> _showOverflowSlotPicker(BuildContext context) =>
      _showOverflowPicker(
        context,
        ranges: _overflowMenuRanges,
        keyPrefix: 'overflowSlot',
        getCurrent: (a) => a.overflowQuickRange,
        setCurrent: (a, v) => a.setOverflowQuickRange(v),
        longLabel: _btcRangeLongLabel,
      );

  // Vertical swipe on the overflow slot cycles through `_overflowMenuRanges`
  // with wrap-around. step=+1 mounts the next-longer year, step=-1 the
  // next-shorter; mirrors the picker side-effect of also activating it.
  void _stepOverflowSlot(BuildContext context, int step) =>
      _stepSlot(
        context,
        step: step,
        ranges: _overflowMenuRanges,
        getCurrent: (a) => a.overflowQuickRange,
        setCurrent: (a, v) => a.setOverflowQuickRange(v),
      );

  Future<void> _showMonthsOverflowSlotPicker(BuildContext context) =>
      _showOverflowPicker(
        context,
        ranges: _overflowMonthsRanges,
        keyPrefix: 'monthsOverflowSlot',
        getCurrent: (a) => a.monthsOverflowQuickRange,
        setCurrent: (a, v) => a.setMonthsOverflowQuickRange(v),
        longLabel: _btcRangeMonthsLongLabel,
      );

  void _stepMonthsOverflowSlot(BuildContext context, int step) =>
      _stepSlot(
        context,
        step: step,
        ranges: _overflowMonthsRanges,
        getCurrent: (a) => a.monthsOverflowQuickRange,
        setCurrent: (a, v) => a.setMonthsOverflowQuickRange(v),
      );

  // Generic picker: shows a radio-group dialog letting the user choose a range
  // from [ranges] for one overflow slot. [getCurrent]/[setCurrent] read/write
  // the slot on [AppStateNotifier]; [longLabel] formats each option's title row.
  Future<void> _showOverflowPicker(
    BuildContext context, {
    required List<BtcRange> ranges,
    required String keyPrefix,
    required BtcRange Function(AppStateNotifier) getCurrent,
    required void Function(AppStateNotifier, BtcRange) setCurrent,
    required String Function(BuildContext, BtcRange) longLabel,
  }) async {
    final app = context.read<AppStateNotifier>();
    final current = getCurrent(app);
    final picked = await showDialog<BtcRange>(
      context: context,
      barrierColor: appDialogBarrierColor(context),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return Dialog(
          elevation: 24,
          shadowColor: Colors.black,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.rangePickerLongTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in ranges.asMap().entries) ...[
                          if (entry.key > 0)
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Theme.of(ctx).colorScheme.outlineVariant,
                            ),
                          _BtcRangeRow(
                            key: ValueKey('$keyPrefix-${entry.value.name}'),
                            label: longLabel(ctx, entry.value),
                            selected: entry.value == current,
                            onTap: () => Navigator.of(ctx).pop(entry.value),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      setCurrent(app, picked);
      widget.onRange(picked);
    }
  }

  // Generic stepper: cycles [ranges] by [step] positions for one overflow slot.
  // Dart's % on negatives returns non-negative for positive divisors, so wrap
  // works cleanly without a manual fixup.
  void _stepSlot(
    BuildContext context, {
    required int step,
    required List<BtcRange> ranges,
    required BtcRange Function(AppStateNotifier) getCurrent,
    required void Function(AppStateNotifier, BtcRange) setCurrent,
  }) {
    final app = context.read<AppStateNotifier>();
    app.dismissSwipeChipHint();
    final current = getCurrent(app);
    final i = ranges.indexOf(current);
    final base = i < 0 ? 0 : i;
    final next = ranges[(base + step) % ranges.length];
    if (next == current) return;
    setCurrent(app, next);
    widget.onRange(next);
  }
}

class _SettingsCircle extends StatelessWidget {
  const _SettingsCircle({
    required this.onTap,
    required this.fill,
    required this.color,
  });

  final VoidCallback onTap;
  final Color fill;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.light();
        onTap();
      },
      child: DecoratedBox(
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
        child: Center(
          child: Icon(Icons.tune, size: 16, color: color),
        ),
      ),
    );
  }
}

class _RangeChipWithPct extends StatelessWidget {
  const _RangeChipWithPct({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.chartColor,
    this.onLongPress,
    this.onSwipeUp,
    this.onSwipeDown,
    this.contentOffsetY = 0,
    this.rollDirection = 1,
    this.minLabelWidth,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color chartColor;
  final VoidCallback? onLongPress;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final double contentOffsetY;
  final int rollDirection;
  final double? minLabelWidth;

  @override
  Widget build(BuildContext context) {
    return _Chip(
      label: label,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      onSwipeUp: onSwipeUp,
      onSwipeDown: onSwipeDown,
      contentOffsetY: contentOffsetY,
      rollDirection: rollDirection,
      compact: true,
      selectedColor: chartColor,
      minLabelWidth: minLabelWidth,
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.onSwipeUp,
    this.onSwipeDown,
    this.contentOffsetY = 0,
    this.rollDirection = 1,
    this.compact = false,
    this.selectedColor,
    this.minLabelWidth,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  // Each accumulated _swipeStep of vertical drag fires one of these. Up = drag
  // toward smaller y (negative dy), down = drag toward larger y. Used by the
  // overflow range slot to cycle through years without opening the picker.
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  // Vertical translation (logical px) applied to the chip's label + chevrons.
  // The parent feeds the same swipe-nudge offset it applies to the sliding pill
  // here, so the pill and its content move together while a swipe cycles ranges.
  final double contentOffsetY;
  // Direction the label slides in when it changes during a swipe: +1 for a
  // down-swipe (new label enters from below), -1 for an up-swipe (enters from
  // above). Mirrors the live-price RollingNumber direction, but vertical.
  final int rollDirection;
  final bool compact;
  // When set, overrides the selected-state text/icon color (defaults to
  // cs.onSurface). Used to tint the active chip orange to match the chart.
  final Color? selectedColor;
  // Width floor for the label text. The overflow chip cycles through labels of
  // varying widths (1Y..15Y) and uses this to keep its size stable so the row
  // doesn't reflow on each cycle.
  final double? minLabelWidth;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  static const double _swipeStep = 24;
  // How long the selected styling (label color/weight, flick-hint chevrons)
  // takes to fade in or out when this chip gains or loses selection.
  static const Duration _selectFade = Duration(milliseconds: 200);
  // Cumulative dy since drag-start. The chip uses a vertical-drag recognizer
  // so it wins the gesture arena against the enclosing scroll view — without
  // that, drags on the chip would also feed the outer scroll and trigger
  // overscroll bounce. Once the user drags well past the chip's bounds we
  // stop firing (treats it as "they meant to scroll, just got the chip"),
  // though by then the scroll view has already lost the arena.
  double _accumDy = 0;
  bool _outsideChip = false;

  void _handleDragStart(DragStartDetails _) {
    _accumDy = 0;
    _outsideChip = false;
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    if (widget.onSwipeUp == null && widget.onSwipeDown == null) return;
    if (_outsideChip) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final local = box.globalToLocal(d.globalPosition);
      final size = box.size;
      if (local.dx < -16 ||
          local.dy < -16 ||
          local.dx > size.width + 16 ||
          local.dy > size.height + 16) {
        _outsideChip = true;
        return;
      }
    }
    _accumDy += d.delta.dy;
    while (_accumDy <= -_swipeStep) {
      _accumDy += _swipeStep;
      if (widget.onSwipeUp != null) {
        AppHaptics.selection();
        widget.onSwipeUp!();
      }
    }
    while (_accumDy >= _swipeStep) {
      _accumDy -= _swipeStep;
      if (widget.onSwipeDown != null) {
        AppHaptics.selection();
        widget.onSwipeDown!();
      }
    }
  }

  void _handleDragEnd(DragEndDetails _) {
    _accumDy = 0;
    _outsideChip = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = widget.selected
        ? (widget.selectedColor ?? cs.onSurface)
        : cs.onSurfaceVariant;
    final hasSwipe = widget.onSwipeUp != null || widget.onSwipeDown != null;
    Widget core = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.light();
        widget.onTap();
      },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              AppHaptics.medium();
              widget.onLongPress!();
            },
      child: Container(
        constraints: BoxConstraints(
          minWidth: math.max(36, (widget.minLabelWidth ?? 0) + 1),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 10 : AppSpacing.md,
          vertical: 8,
        ),
        // The selected-state pill background is drawn by the shared sliding
        // pill behind the row (see _RangeBarState.build), not per-chip — so the
        // chip itself is transparent and only styles its label.
        alignment: Alignment.center,
        child: Transform.translate(
            offset: Offset(0, widget.contentOffsetY - 1),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: _selectFade,
                  curve: Curves.easeOut,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : null,
                    color: activeColor,
                  ),
                  child: AnimatedSwitcher(
                    duration: AppSpacing.motionDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.center,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, anim) {
                      final isIncoming =
                          child.key == ValueKey(widget.label);
                      final begin = Offset(
                        0,
                        (isIncoming ? 1.0 : -1.0) *
                            widget.rollDirection *
                            0.6,
                      );
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: begin,
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      widget.label,
                      key: ValueKey(widget.label),
                      textAlign: TextAlign.center,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    if (!hasSwipe) return core;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _EagerVerticalDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_EagerVerticalDragRecognizer>(
          () => _EagerVerticalDragRecognizer(),
          (instance) {
            instance
              ..dragStartBehavior = DragStartBehavior.down
              ..onStart = _handleDragStart
              ..onUpdate = _handleDragUpdate
              ..onEnd = _handleDragEnd
              ..onCancel = () {
                _accumDy = 0;
                _outsideChip = false;
              };
          },
        ),
      },
      child: core,
    );
  }
}

// Vertical-drag recognizer that wins the gesture arena as soon as the pointer
// moves vertically (rather than waiting for slop), so the enclosing scroll
// view doesn't also receive the deltas — which would otherwise bounce the
// page. Crucially, it does NOT claim on pointer-down: the inner tap
// recognizer needs to win plain taps, and would lose if this one accepted
// eagerly on every touch.
//
// We only claim when the motion is predominantly vertical (|dy| > |dx|).
// Without this check a real finger's horizontal pill-drag has enough vertical
// jitter that dy != 0 fires first and this recognizer steals the arena,
// preventing the pill from being dragged on physical devices.
class _EagerVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerMoveEvent &&
        event.delta.dy != 0 &&
        event.delta.dy.abs() > event.delta.dx.abs()) {
      resolve(GestureDisposition.accepted);
    }
  }
}

class _BtcRangeRow extends StatelessWidget {
  const _BtcRangeRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    final radius = BorderRadius.circular(AppSpacing.radius);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? p.bitcoinOrange : cs.outline,
                    width: 2,
                  ),
                  color: selected ? p.bitcoinOrange : Colors.transparent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.title.copyWith(
                    fontWeight: FontWeight.w400,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Memo for _maxLabelWidth: RangeBar rebuilds at price-tick cadence and lays
// out ~38 painters per build, but the widths only change with the label set
// (locale), style, text scale, or direction. LRU-capped so locale/theme
// switches can't grow it unboundedly.
final Map<(String, TextStyle, TextScaler, TextDirection), double>
    _labelWidthCache = {};
const int _labelWidthCacheCap = 32;

// Measures the widest label among `labels` rendered with `style` and the
// supplied `TextScaler`. Used to reserve a stable width on the overflow chip
// so cycling through 1Y..15Y doesn't shift neighboring chips.
double _maxLabelWidth({
  required BuildContext context,
  required List<String> labels,
  required TextStyle style,
  required TextScaler textScaler,
}) {
  final textDirection = Directionality.of(context);
  final key = (labels.join('\u0000'), style, textScaler, textDirection);
  final cached = _labelWidthCache.remove(key);
  if (cached != null) {
    _labelWidthCache[key] = cached; // refresh LRU position
    return cached;
  }
  double maxWidth = 0;
  for (final label in labels) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    if (tp.size.width > maxWidth) maxWidth = tp.size.width;
    tp.dispose();
  }
  if (_labelWidthCache.length >= _labelWidthCacheCap) {
    _labelWidthCache.remove(_labelWidthCache.keys.first);
  }
  _labelWidthCache[key] = maxWidth;
  return maxWidth;
}

String _btcRangeLabel(BuildContext context, BtcRange r) {
  final l10n = AppLocalizations.of(context);
  return switch (r) {
    BtcRange.d1 => l10n.rangePill1D,
    BtcRange.d2 => l10n.rangePill2D,
    BtcRange.d3 => l10n.rangePill3D,
    BtcRange.d4 => l10n.rangePill4D,
    BtcRange.d5 => l10n.rangePill5D,
    BtcRange.d6 => l10n.rangePill6D,
    BtcRange.d7 => l10n.rangePill7D,
    BtcRange.w1 => l10n.rangePill1W,
    BtcRange.w2 => l10n.rangePill2W,
    BtcRange.w3 => l10n.rangePill3W,
    BtcRange.w4 => l10n.rangePill4W,
    BtcRange.m1 => l10n.rangePill1M,
    BtcRange.m2 => l10n.rangePill2M,
    BtcRange.m3 => l10n.rangePill3M,
    BtcRange.m4 => l10n.rangePill4M,
    BtcRange.m5 => l10n.rangePill5M,
    BtcRange.m6 => l10n.rangePill6M,
    BtcRange.m7 => l10n.rangePill7M,
    BtcRange.m8 => l10n.rangePill8M,
    BtcRange.m9 => l10n.rangePill9M,
    BtcRange.m10 => l10n.rangePill10M,
    BtcRange.m11 => l10n.rangePill11M,
    BtcRange.m12 => l10n.rangePill12M,
    BtcRange.y1 => l10n.rangePill1Y,
    BtcRange.y2 => l10n.rangePill2Y,
    BtcRange.y3 => l10n.rangePill3Y,
    BtcRange.y4 => l10n.rangePill4Y,
    BtcRange.y5 => l10n.rangePill5Y,
    BtcRange.y6 => l10n.rangePill6Y,
    BtcRange.y7 => l10n.rangePill7Y,
    BtcRange.y8 => l10n.rangePill8Y,
    BtcRange.y9 => l10n.rangePill9Y,
    BtcRange.y10 => l10n.rangePill10Y,
    BtcRange.y11 => l10n.rangePill11Y,
    BtcRange.y12 => l10n.rangePill12Y,
    BtcRange.y13 => l10n.rangePill13Y,
    BtcRange.y14 => l10n.rangePill14Y,
    BtcRange.y15 => l10n.rangePill15Y,
    BtcRange.all => l10n.rangePillAll,
  };
}

// Long-form label for the days overflow picker: "1 Day", "3 Days", etc.
String _btcRangeDaysLongLabel(BuildContext context, BtcRange r) {
  final d = r.days;
  if (d == null) return _btcRangeLabel(context, r);
  return AppLocalizations.of(context).rangePickerDaysFull(d);
}

// Long-form label for the weeks overflow picker: "1 Week", "2 Weeks", etc.
String _btcRangeWeeksLongLabel(BuildContext context, BtcRange r) {
  final w = r.weeks;
  if (w == null) return _btcRangeLabel(context, r);
  return AppLocalizations.of(context).rangePickerWeeksFull(w);
}

// Long-form label for the months overflow picker: "1 Month", "6 Months", etc.
// Falls back to the short label for non-month ranges (safety belt; the picker
// only ever supplies month-shaped values).
String _btcRangeMonthsLongLabel(BuildContext context, BtcRange r) {
  final months = r.months;
  if (months == null) return _btcRangeLabel(context, r);
  return AppLocalizations.of(context).rangePickerMonthsFull(months);
}

// Long-form label for the overflow-slot picker: "1 Year", "5 Years", etc.
// Falls back to the short label for non-year ranges.
String _btcRangeLongLabel(BuildContext context, BtcRange r) {
  final years = r.years;
  if (years == null) return _btcRangeLabel(context, r);
  return AppLocalizations.of(context).rangePickerYearsFull(years);
}


