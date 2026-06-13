import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../api/api.dart';
import '../../../data/app_enums.dart';
import '../../../data/fiat.dart';
import '../../../services/app_haptics.dart';
import '../../../theme/theme.dart';
import '../../../widgets/stack_card.dart' show StackCardPosition;

class RangePillsRow extends StatefulWidget {
  const RangePillsRow({
    super.key,
    required this.card,
    required this.rangePillData,
    required this.priceScale,
    required this.currency,
    this.position = StackCardPosition.only,
    this.playHint = false,
    this.onHintConsumed,
    this.hopiumMode = false,
  });

  final Widget card;
  final List<PricePoint> rangePillData;
  final double priceScale;
  final Currency currency;
  // When true, a second rail of price-milestone pills is laid out to the right
  // of the card, revealed by swiping the card to the left — what the stack
  // would be worth at round BTC prices (100K..1M, then 2M..10M) in [currency].
  // The historical pills on the left (swipe right) are unaffected.
  final bool hopiumMode;
  // Controls whether a bottom hairline is drawn under this row to separate it
  // from the next (first/middle: yes; only/last: no — those are the bottom of
  // the group).
  final StackCardPosition position;
  // When true, after first layout this row nudges itself to the right and back,
  // repeating every couple seconds, hinting that the card can be swiped aside
  // to reveal the range pills. A user-initiated swipe ends the loop.
  final bool playHint;
  // Fired once the user swipes the card themselves, ending the nudge loop. The
  // parent persists this so the nudge never plays again. Called at most once
  // per mounted row.
  final VoidCallback? onHintConsumed;

  @override
  State<RangePillsRow> createState() => _RangePillsRowState();
}

// Minimum width of a range pill cell. Cells stretch past this to fit long
// price strings, so the real divider positions are measured from layout rather
// than assumed to fall on a fixed stride — see [_RangePillsRowState].
const double _kRangePillMinWidth = 112;

// Width of the hairline divider drawn between adjacent pill cells.
const double _kRangePillDividerWidth = 1;

class _RangePillsRowState extends State<RangePillsRow> {
  // Rest offset is the width of the historical rail, computed after layout
  // (see [_restOffset]), so the controller is built lazily once that's known.
  ScrollController? _scrollController;
  // Shared, mutable handle the snap physics read at fling time. Kept stable
  // (created once) and mutated in place, so the live ScrollPosition's physics
  // always see the latest rest offset without depending on Scrollable choosing
  // to recreate the position when the physics instance changes.
  final _snapConfig = _SnapConfig();
  // Created once and reused so the ScrollView's physics identity is stable
  // across rebuilds (per-tick price updates), which keeps Scrollable from
  // recreating the position and resetting the scroll offset.
  late final _SnapScrollPhysics _snapPhysics =
      _SnapScrollPhysics(config: _snapConfig);
  // A stable key per cell so we can read each cell's laid-out width after the
  // frame and turn it into the scroll offset at which its leading divider
  // crosses the left screen edge. Cells are variable-width (long prices stretch
  // them past _kRangePillMinWidth), so a fixed stride drifts from the real
  // dividers. Keys are pooled by index and reused across rebuilds — minting
  // fresh GlobalKeys each build would tear down and rebuild every cell.
  final List<GlobalKey> _cellKeys = [];
  // Same pooling for the milestone (Hopium) rail's cells, measured to align its
  // own crossing haptics. Disjoint from [_cellKeys] so the two rails don't
  // share keys.
  final List<GlobalKey> _milestoneCellKeys = [];

  // Returns a stable key for historical cell [index], growing the pool as
  // needed. The child requests one key per cell during build; surplus keys left
  // over from a previous (longer) build are ignored by
  // _recomputeDividerOffsets, which reads only the first [_cellCount].
  GlobalKey _keyFor(int index) {
    while (_cellKeys.length <= index) {
      _cellKeys.add(GlobalKey());
    }
    return _cellKeys[index];
  }

  // Same as [_keyFor] for the milestone rail.
  GlobalKey _milestoneKeyFor(int index) {
    while (_milestoneCellKeys.length <= index) {
      _milestoneCellKeys.add(GlobalKey());
    }
    return _milestoneCellKeys[index];
  }

  int _cellCount = 0;
  int _milestoneCellCount = 0;
  // The historical rail sits to the LEFT of the card; the card rests at scroll
  // offset == its total width. The user reveals it by dragging the card right
  // (offset decreasing toward 0). Null until measured.
  double? _restOffset;
  // Scroll offsets, descending from [_restOffset], at which each historical
  // inter-cell divider crosses the right edge of the card as it slides away.
  List<double> _dividerOffsets = const [];
  // Scroll offsets, ascending from [_restOffset], at which each milestone
  // divider crosses the left edge of the card as it slides the other way.
  List<double> _milestoneDividerOffsets = const [];
  // Index of the last divider already crossed on each side (fire once per
  // crossing). Tracked per side since the two rails are walked independently.
  int _lastCrossedDivider = 0;
  int _lastCrossedMilestone = 0;

  // True once the user has swiped a card themselves — that ends the nudge loop
  // for good and notifies the parent (which persists it) exactly once.
  bool _hintConsumed = false;
  // Pending timer for the next nudge in the repeating loop. Cancelled on
  // consume and on dispose so a fired-then-unmounted row leaves nothing behind.
  Timer? _hintTimer;

  // How far the auto-nudge slides the card aside. Wide enough to reveal the
  // leading edge of the first range pill (cells are >= _kRangePillMinWidth)
  // without committing to a full pill, so it reads as "there's more here."
  static const double _kHintPeekOffset = 56;

  // Held off until the route transition back from the new-stack flow has
  // settled — firing on the first frame buries the slide under the page
  // animation, so the user lands on a still card and only then sees it move.
  static const Duration _kHintStartDelay = Duration(milliseconds: 650);

  // Gap between the end of one nudge and the start of the next. The loop keeps
  // replaying until the user finally swipes a stack themselves.
  static const Duration _kHintRepeatGap = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    if (widget.playHint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hintTimer = Timer(_kHintStartDelay, _maybePlayHint);
      });
    }
  }

  // Slides the card aside (toward the historical rail) and back once, then — if
  // the user still hasn't swiped — schedules the next nudge [_kHintRepeatGap]
  // later, looping indefinitely. Skips if a user swipe already ended the loop,
  // the row is gone, or the scroll view hasn't attached its position / measured
  // its rest offset yet (retried next frame in those cases).
  Future<void> _maybePlayHint() async {
    if (_hintConsumed || !mounted) return;
    final controller = _scrollController;
    final rest = _restOffset;
    if (controller == null || !controller.hasClients || rest == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybePlayHint());
      return;
    }
    // The historical rail is revealed by dragging the card right, i.e. scrolling
    // below the rest offset. Nudge toward it, clamped so a tiny rail can't push
    // past offset 0.
    final peekTarget = (rest - _kHintPeekOffset).clamp(0.0, rest);
    await controller.animateTo(
      peekTarget,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || _hintConsumed) return;
    await controller.animateTo(
      rest,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted || _hintConsumed) return;
    _hintTimer = Timer(_kHintRepeatGap, _maybePlayHint);
  }

  // Ends the nudge loop once the user swipes, and notifies the parent (which
  // persists the flag) exactly once. Idempotent.
  void _onHintConsumed() {
    if (_hintConsumed) return;
    _hintConsumed = true;
    _hintTimer?.cancel();
    _hintTimer = null;
    widget.onHintConsumed?.call();
  }

  // Reads measured cell widths and turns them into:
  //  - [_restOffset]: the historical rail's total width, where the card rests
  //    (its left edge flush with the viewport's left edge).
  //  - [_dividerOffsets]: offsets BELOW rest at which each historical divider
  //    crosses the card's right edge as the card slides right. The divider
  //    nearest the card crosses first (smallest delta from rest).
  //  - [_milestoneDividerOffsets]: offsets ABOVE rest at which each milestone
  //    divider crosses the card's left edge as the card slides left.
  // Layout is left-to-right (not reversed): [historical | card | milestone].
  void _recomputeDividerOffsets() {
    if (_cellCount == 0) return;
    final widths = <double>[];
    var railWidth = 0.0;
    for (var i = 0; i < _cellCount; i++) {
      final box = _cellKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return; // not laid out yet
      widths.add(box.size.width);
      railWidth += box.size.width;
      if (i > 0) railWidth += _kRangePillDividerWidth;
    }
    // Walk from the rightmost historical cell (nearest the card) leftward,
    // accumulating widths; each divider crossing is that many pixels of drag
    // below the rest offset.
    final hist = <double>[];
    var acc = 0.0;
    for (var i = widths.length - 1; i >= 1; i--) {
      acc += widths[i];
      hist.add(railWidth - acc);
      acc += _kRangePillDividerWidth;
    }
    // Milestone rail: walk from its leftmost cell (nearest the card) rightward;
    // each divider crossing is that many pixels of drag above the rest offset.
    final mile = <double>[];
    if (_milestoneCellCount > 0) {
      var macc = 0.0;
      for (var i = 0; i < _milestoneCellCount - 1; i++) {
        final box = _milestoneCellKeys[i].currentContext?.findRenderObject()
            as RenderBox?;
        if (box == null || !box.hasSize) break;
        macc += box.size.width + _kRangePillDividerWidth;
        mile.add(railWidth + macc);
      }
    }
    final restChanged = _restOffset != railWidth;
    if (restChanged ||
        !listEquals(hist, _dividerOffsets) ||
        !listEquals(mile, _milestoneDividerOffsets)) {
      setState(() {
        _restOffset = railWidth;
        _dividerOffsets = hist;
        _milestoneDividerOffsets = mile;
      });
      // Feed the live physics the measured centre so a fling that would carry
      // the card across it snaps back to fully centred.
      _snapConfig.restOffset = railWidth;
      // On first measure (or a width change), snap the card to rest so the
      // historical rail starts off-screen to the left rather than the card
      // opening pre-scrolled.
      if (restChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = _scrollController;
          if (mounted && c != null && c.hasClients && c.offset != railWidth) {
            c.jumpTo(railWidth);
          }
        });
      }
    }
  }

  void _onScroll() {
    final controller = _scrollController;
    final rest = _restOffset;
    if (controller == null || rest == null) return;
    final offset = controller.offset;
    // Historical side: drag below rest. Boundaries are ascending offsets, so
    // count how many the (decreasing) offset has dropped past.
    var crossed = 0;
    for (final boundary in _dividerOffsets) {
      if (offset <= boundary) {
        crossed++;
      } else {
        break;
      }
    }
    // Milestone side: drag above rest. Boundaries ascending; count how many the
    // (increasing) offset has passed.
    var crossedMile = 0;
    for (final boundary in _milestoneDividerOffsets) {
      if (offset >= boundary) {
        crossedMile++;
      } else {
        break;
      }
    }
    if (crossed != _lastCrossedDivider ||
        crossedMile != _lastCrossedMilestone) {
      _lastCrossedDivider = crossed;
      _lastCrossedMilestone = crossedMile;
      AppHaptics.selection();
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _scrollController?.removeListener(_onScroll);
    _scrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rangePills = _StackRangePills(
      data: widget.rangePillData,
      priceScale: widget.priceScale,
      currency: widget.currency,
      keyFor: _keyFor,
      onCellCount: (count) => _cellCount = count,
    );
    // Lazily build the controller now that this row is laying out. Seeding its
    // initial offset to the last-known rest keeps the card centred across
    // rebuilds (e.g. a currency swipe) without flashing the historical rail.
    final controller = _scrollController ??= ScrollController(
      initialScrollOffset: _restOffset ?? 0,
    )..addListener(_onScroll);
    // With the milestone rail gone, no build will report its cell count, so
    // zero it here to retire the stale milestone crossing boundaries.
    if (!widget.hopiumMode) {
      _milestoneCellCount = 0;
      _milestoneDividerOffsets = const [];
      _lastCrossedMilestone = 0;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _recomputeDividerOffsets());
        // The card carries an opaque background and a shadow on each edge so it
        // reads as one level above the recessed pill rails revealed beside it.
        final card = DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 5,
              ),
            ],
          ),
          child: SizedBox(width: fullWidth, child: widget.card),
        );
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // A user touch-drag carries dragDetails; the auto-nudge's
            // programmatic animateTo does not. So a drag-start with details is
            // a real swipe — it ends the hint loop for good.
            if (n is ScrollStartNotification && n.dragDetails != null) {
              _onHintConsumed();
            }
            return false;
          },
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // Snapping physics resolve every fling/drag to the nearest of the
            // three resting offsets (historical open, card centred, milestone
            // open) so the card never strands mid-screen. The physics read the
            // centre live from [_snapConfig], so a single stable instance keeps
            // working once the rest offset is measured a frame later.
            physics: _snapPhysics,
            controller: controller,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left rail (revealed by dragging the card right): historical
                  // "worth N years ago" pills. Always present.
                  rangePills,
                  card,
                  // Right rail (revealed by dragging the card left): price
                  // milestones. Only present in Hopium mode.
                  if (widget.hopiumMode)
                    _StackMilestonePills(
                      priceScale: widget.priceScale,
                      currency: widget.currency,
                      keyFor: _milestoneKeyFor,
                      onCellCount: (count) => _milestoneCellCount = count,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Mutable handle shared between the State and its snap physics. The State
// writes [restOffset] once the historical rail is measured; the physics read
// it live at fling time. This decouples snapping from whether Scrollable
// chooses to recreate its ScrollPosition when the physics instance changes —
// the position can hold one stable physics object and still see fresh targets.
class _SnapConfig {
  // The card-centred scroll offset (== historical rail width). Null until
  // measured, during which the physics fall back to plain bouncing.
  double? restOffset;
}

// Scroll physics where only the centred card is sticky. The rails scroll
// freely — a pill can be left partially off-screen — but a release whose
// momentum would land near the centre snaps the card back to fully centred, so
// the current-value view always settles cleanly. Everywhere else, the default
// bouncing momentum carries unchanged. Inert until the rest offset is measured.
class _SnapScrollPhysics extends ScrollPhysics {
  const _SnapScrollPhysics({required this.config, super.parent});

  final _SnapConfig config;

  @override
  _SnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapScrollPhysics(config: config, parent: buildParent(ancestor));

  // Maps release velocity (px/s) to projected coast distance (px) for deciding
  // where a free fling would land.
  static const double _kMomentumFactor = 0.18;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final rest = config.restOffset;
    // No measured centre yet, or out of range (let the parent bounce back).
    if (rest == null || position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final centre =
        rest.clamp(position.minScrollExtent, position.maxScrollExtent);
    final current = position.pixels;
    final projected = current + velocity * _kMomentumFactor;

    // Already centred and at rest: nothing to simulate.
    if ((current - centre).abs() < 0.5 && velocity.abs() < 0.5) return null;

    // The centre is a hard magnet: a fling that would carry the scroll ACROSS
    // centre (released on one side, projected to land on the other) stops dead
    // at centre however fast it's thrown — the card can't be flung past its own
    // centred position. A fling that stays on one side of centre, or moves
    // deeper into a rail, is left to the default free momentum so pills can rest
    // partially shown.
    final crossesCentre = (current - centre).sign != (projected - centre).sign;
    if (crossesCentre) {
      return ScrollSpringSimulation(
        spring,
        current,
        centre,
        velocity,
        tolerance: toleranceFor(position),
      );
    }
    return super.createBallisticSimulation(position, velocity);
  }

  // A snappy-but-soft spring so the settle reads as a deliberate snap rather
  // than a slow drift or a hard stop.
  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 180, ratio: 1.1);
}

class _StackRangePills extends StatelessWidget {
  const _StackRangePills({
    required this.data,
    required this.priceScale,
    required this.currency,
    required this.keyFor,
    required this.onCellCount,
  });

  final List<PricePoint> data;
  final double priceScale;
  final Currency currency;
  // Supplies a stable key for each cell so the parent can measure laid-out cell
  // widths and align haptics to the real divider positions.
  final GlobalKey Function(int index) keyFor;
  // Reports how many cells this build produced, so the parent measures exactly
  // that many (and not stale keys left over from a longer previous build).
  final ValueChanged<int> onCellCount;

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) {
      onCellCount(0);
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final firstT = DateTime.fromMillisecondsSinceEpoch(data.first.t);
    final maxYearsBack = now.year - firstT.year -
        (_isBefore(now.month, now.day, firstT.month, firstT.day) ? 1 : 0);
    final dateFormat = _pillDateFormat(
      Localizations.localeOf(context).toString(),
    );
    final offsets = [
      for (int y = maxYearsBack; y >= 1; y--)
        () {
          final at = DateTime(now.year - y, now.month, now.day,
              now.hour, now.minute, now.second, now.millisecond);
          return (label: dateFormat.format(at), atMs: at.millisecondsSinceEpoch);
        }(),
    ];
    if (offsets.isEmpty) {
      onCellCount(0);
      return const SizedBox.shrink();
    }
    final items = [
      for (final o in offsets)
        _RangePillData(label: o.label, pastPrice: _priceAt(o.atMs)),
    ];
    onCellCount(items.length);

    final cs = Theme.of(context).colorScheme;
    final railFill = context.palette.recessedSurface ?? cs.surfaceContainer;
    return ColoredBox(
      color: railFill,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                width: _kRangePillDividerWidth,
                thickness: _kRangePillDividerWidth,
                color: cs.outlineVariant,
              ),
            _RangeCell(key: keyFor(i), item: items[i], currency: currency),
          ],
        ],
      ),
    );
  }

  double? _priceAt(int targetMs) {
    if (data.isEmpty || targetMs <= data.first.t) return null;
    int lo = 0, hi = data.length - 1, best = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (data[mid].t <= targetMs) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best >= 0 ? data[best].price * priceScale : null;
  }

  static bool _isBefore(int aMonth, int aDay, int bMonth, int bDay) =>
      aMonth < bMonth || (aMonth == bMonth && aDay < bDay);
}

class _RangePillData {
  const _RangePillData({required this.label, required this.pastPrice});

  final String label;
  final double? pastPrice;
}

// DateFormat construction does a locale lookup and pattern parse each time,
// and every pill row rebuilds it per build — i.e. per price tick. The
// pattern is fixed, so cache one instance per locale.
final Map<String, DateFormat> _pillDateFormats = {};

DateFormat _pillDateFormat(String locale) =>
    _pillDateFormats[locale] ??= DateFormat("d MMM ''yy", locale);

class _RangeCell extends StatelessWidget {
  const _RangeCell({super.key, required this.item, required this.currency});

  final _RangePillData item;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pastPrice = item.pastPrice;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _kRangePillMinWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.label,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pastPrice == null
                  ? '—'
                  : formatFiat(pastPrice, currency, decimalsUnder10: true).full,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.3,
                color: pastPrice == null
                    ? cs.onSurfaceVariant
                    : cs.onSurface.withValues(alpha: 0.85),
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The "Hopium" price ladder, in the active currency: 100K..1M in 100K steps,
// then 2M..10M in 1M steps. Each entry is a target BTC price; the pill shows
// what the stack is worth once Bitcoin reaches it.
const List<int> _kHopiumMilestones = [
  100000, 200000, 300000, 400000, 500000, 600000, 700000, 800000, 900000,
  1000000, 2000000, 3000000, 4000000, 5000000, 6000000, 7000000, 8000000,
  9000000, 10000000,
];

// Renders a milestone price as a compact label like "100K" or "1M", to keep
// the pill's top line short. Always whole millions/hundred-thousands by
// construction, so no decimals are needed.
String _milestoneLabel(int price) {
  if (price >= 1000000) return '${price ~/ 1000000}M';
  return '${price ~/ 1000}K';
}

class _StackMilestonePills extends StatelessWidget {
  const _StackMilestonePills({
    required this.priceScale,
    required this.currency,
    required this.keyFor,
    required this.onCellCount,
  });

  // BTC amount of the stack (sats / 1e8); a milestone's value is price * scale.
  final double priceScale;
  final Currency currency;
  final GlobalKey Function(int index) keyFor;
  final ValueChanged<int> onCellCount;

  @override
  Widget build(BuildContext context) {
    onCellCount(_kHopiumMilestones.length);
    final cs = Theme.of(context).colorScheme;
    final railFill = context.palette.recessedSurface ?? cs.surfaceContainer;
    return ColoredBox(
      color: railFill,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < _kHopiumMilestones.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                width: _kRangePillDividerWidth,
                thickness: _kRangePillDividerWidth,
                color: cs.outlineVariant,
              ),
            _MilestoneCell(
              key: keyFor(i),
              price: _kHopiumMilestones[i],
              currency: currency,
              value: _kHopiumMilestones[i] * priceScale,
            ),
          ],
        ],
      ),
    );
  }
}

class _MilestoneCell extends StatelessWidget {
  const _MilestoneCell({
    super.key,
    required this.price,
    required this.currency,
    required this.value,
  });

  final int price;
  final Currency currency;
  final double value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final symbol = currencySymbols[currency] ?? r'$';
    final label = symbolAfterAmount
        ? '${_milestoneLabel(price)} $symbol'
        : '$symbol${_milestoneLabel(price)}';
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _kRangePillMinWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatFiat(value, currency, decimalsUnder10: true).full,
              style: AppTypography.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.3,
                color: cs.onSurface.withValues(alpha: 0.85),
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
