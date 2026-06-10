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

class RangeBar extends StatelessWidget {
  const RangeBar({
    super.key,
    required this.range,
    required this.onRange,
    required this.chartColor,
  });

  final BtcRange range;
  final ValueChanged<BtcRange> onRange;
  final Color chartColor;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateNotifier>();
    final daysOverflowSlot = app.daysOverflowQuickRange;
    final weeksOverflowSlot = app.weeksOverflowQuickRange;
    final overflowSlot = app.overflowQuickRange;
    final monthsOverflowSlot = app.monthsOverflowQuickRange;
    final textScaler = MediaQuery.textScalerOf(context);
    // 1.4 line-height factor (AppTypography.body actual) + 16 padding + 4px
    // slack so the inner Column never overflows by sub-pixel amounts at very
    // large text scales. The chevron icon (24px on the overflow chip) drives
    // the row height when system text is small, so we floor on it — without
    // that, the icon overflows the column by ~0.4px at textScale=1.0.
    final labelRow = math.max<double>(textScaler.scale(14) * 1.4, 24);
    final chipHeight = labelRow + 16 + 4;
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
    const horizontalPadding = AppSpacing.md;
    return SizedBox(
      height: chipHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final innerWidth = constraints.maxWidth - horizontalPadding * 2;
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              horizontalPadding, 0, horizontalPadding, 0,
            ),
            child: SizedBox(
              width: innerWidth,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: Center(
                      child: _RangeChipWithPct(
                        label: _btcRangeLabel(context, daysOverflowSlot),
                        selected: range == daysOverflowSlot,
                        onTap: () => onRange(daysOverflowSlot),
                        onLongPress: () => _showDaysOverflowSlotPicker(context),
                        onSwipeUp: () => _stepDaysOverflowSlot(context, 1),
                        onSwipeDown: () => _stepDaysOverflowSlot(context, -1),
                        chartColor: chartColor,
                        showChevron: true,
                        minLabelWidth: daysOverflowLabelWidth,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _RangeChipWithPct(
                        label: _btcRangeLabel(context, weeksOverflowSlot),
                        selected: range == weeksOverflowSlot,
                        onTap: () => onRange(weeksOverflowSlot),
                        onLongPress: () => _showWeeksOverflowSlotPicker(context),
                        onSwipeUp: () => _stepWeeksOverflowSlot(context, 1),
                        onSwipeDown: () => _stepWeeksOverflowSlot(context, -1),
                        chartColor: chartColor,
                        showChevron: true,
                        minLabelWidth: weeksOverflowLabelWidth,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _RangeChipWithPct(
                        label: _btcRangeLabel(context, monthsOverflowSlot),
                        selected: range == monthsOverflowSlot,
                        onTap: () => onRange(monthsOverflowSlot),
                        onLongPress: () => _showMonthsOverflowSlotPicker(context),
                        onSwipeUp: () => _stepMonthsOverflowSlot(context, 1),
                        onSwipeDown: () => _stepMonthsOverflowSlot(context, -1),
                        chartColor: chartColor,
                        showChevron: true,
                        minLabelWidth: monthsOverflowLabelWidth,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _RangeChipWithPct(
                        label: _btcRangeLabel(context, overflowSlot),
                        selected: range == overflowSlot,
                        onTap: () => onRange(overflowSlot),
                        onLongPress: () => _showOverflowSlotPicker(context),
                        onSwipeUp: () => _stepOverflowSlot(context, 1),
                        onSwipeDown: () => _stepOverflowSlot(context, -1),
                        chartColor: chartColor,
                        showChevron: true,
                        minLabelWidth: overflowLabelWidth,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _RangeChipWithPct(
                        label: _btcRangeLabel(context, BtcRange.all),
                        selected: range == BtcRange.all,
                        onTap: () => onRange(BtcRange.all),
                        chartColor: chartColor,
                        minLabelWidth:
                            labelWidth(_btcRangeLabel(context, BtcRange.all)) +
                            18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDaysOverflowSlotPicker(BuildContext context) async {
    final app = context.read<AppStateNotifier>();
    app.dismissRangeChipHint();
    final current = app.daysOverflowQuickRange;
    final picked = await showDialog<BtcRange>(
      context: context,
      barrierColor: appDialogBarrierColor(context),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        return RadioGroup<BtcRange>(
          groupValue: _overflowDaysRanges.contains(current) ? current : null,
          onChanged: (v) {
            AppHaptics.selection();
            Navigator.of(ctx).pop(v);
          },
          child: SimpleDialog(
            elevation: 24,
            shadowColor: Colors.black,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.rangePickerLongTitle),
                const SizedBox(height: 4),
                Text(
                  l10n.homeSwipeChipHint,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            children: [
              for (final r in _overflowDaysRanges)
                RadioListTile<BtcRange>(
                  key: ValueKey('daysOverflowSlot-${r.name}'),
                  title: Text(_btcRangeDaysLongLabel(ctx, r)),
                  value: r,
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      app.setDaysOverflowQuickRange(picked);
      onRange(picked);
    }
  }

  void _stepDaysOverflowSlot(BuildContext context, int step) {
    final app = context.read<AppStateNotifier>();
    app.dismissSwipeChipHint();
    final current = app.daysOverflowQuickRange;
    final ranges = _overflowDaysRanges;
    final i = ranges.indexOf(current);
    final base = i < 0 ? 0 : i;
    final n = ranges.length;
    final next = ranges[(base + step) % n];
    if (next == current) return;
    app.setDaysOverflowQuickRange(next);
    onRange(next);
  }

  Future<void> _showWeeksOverflowSlotPicker(BuildContext context) async {
    final app = context.read<AppStateNotifier>();
    app.dismissRangeChipHint();
    final current = app.weeksOverflowQuickRange;
    final picked = await showDialog<BtcRange>(
      context: context,
      barrierColor: appDialogBarrierColor(context),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        return RadioGroup<BtcRange>(
          groupValue: _overflowWeeksRanges.contains(current) ? current : null,
          onChanged: (v) {
            AppHaptics.selection();
            Navigator.of(ctx).pop(v);
          },
          child: SimpleDialog(
            elevation: 24,
            shadowColor: Colors.black,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.rangePickerLongTitle),
                const SizedBox(height: 4),
                Text(
                  l10n.homeSwipeChipHint,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            children: [
              for (final r in _overflowWeeksRanges)
                RadioListTile<BtcRange>(
                  key: ValueKey('weeksOverflowSlot-${r.name}'),
                  title: Text(_btcRangeWeeksLongLabel(ctx, r)),
                  value: r,
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      app.setWeeksOverflowQuickRange(picked);
      onRange(picked);
    }
  }

  void _stepWeeksOverflowSlot(BuildContext context, int step) {
    final app = context.read<AppStateNotifier>();
    app.dismissSwipeChipHint();
    final current = app.weeksOverflowQuickRange;
    final ranges = _overflowWeeksRanges;
    final i = ranges.indexOf(current);
    final base = i < 0 ? 0 : i;
    final n = ranges.length;
    final next = ranges[(base + step) % n];
    if (next == current) return;
    app.setWeeksOverflowQuickRange(next);
    onRange(next);
  }

  Future<void> _showOverflowSlotPicker(BuildContext context) async {
    final app = context.read<AppStateNotifier>();
    app.dismissRangeChipHint();
    final current = app.overflowQuickRange;
    final picked = await showDialog<BtcRange>(
      context: context,
      barrierColor: appDialogBarrierColor(context),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        return RadioGroup<BtcRange>(
          groupValue: _overflowMenuRanges.contains(current) ? current : null,
          onChanged: (v) {
            AppHaptics.selection();
            Navigator.of(ctx).pop(v);
          },
          child: SimpleDialog(
            elevation: 24,
            shadowColor: Colors.black,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.rangePickerLongTitle),
                const SizedBox(height: 4),
                Text(
                  l10n.homeSwipeChipHint,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            children: [
              for (final r in _overflowMenuRanges)
                RadioListTile<BtcRange>(
                  key: ValueKey('overflowSlot-${r.name}'),
                  title: Text(_btcRangeLongLabel(ctx, r)),
                  value: r,
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      app.setOverflowQuickRange(picked);
      onRange(picked);
    }
  }

  // Vertical swipe on the overflow slot cycles through `_overflowMenuRanges`
  // with wrap-around. step=+1 mounts the next-longer year, step=-1 the
  // next-shorter; mirrors the picker side-effect of also activating it.
  void _stepOverflowSlot(BuildContext context, int step) {
    final app = context.read<AppStateNotifier>();
    app.dismissSwipeChipHint();
    final current = app.overflowQuickRange;
    final ranges = _overflowMenuRanges;
    final i = ranges.indexOf(current);
    final base = i < 0 ? 0 : i;
    final n = ranges.length;
    // Dart's % on negatives still returns non-negative for positive divisors,
    // so this wraps cleanly without a manual fixup.
    final next = ranges[(base + step) % n];
    if (next == current) return;
    app.setOverflowQuickRange(next);
    onRange(next);
  }

  Future<void> _showMonthsOverflowSlotPicker(BuildContext context) async {
    final app = context.read<AppStateNotifier>();
    app.dismissRangeChipHint();
    final current = app.monthsOverflowQuickRange;
    final picked = await showDialog<BtcRange>(
      context: context,
      barrierColor: appDialogBarrierColor(context),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final cs = Theme.of(ctx).colorScheme;
        return RadioGroup<BtcRange>(
          groupValue: _overflowMonthsRanges.contains(current) ? current : null,
          onChanged: (v) {
            AppHaptics.selection();
            Navigator.of(ctx).pop(v);
          },
          child: SimpleDialog(
            elevation: 24,
            shadowColor: Colors.black,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.rangePickerLongTitle),
                const SizedBox(height: 4),
                Text(
                  l10n.homeSwipeChipHint,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            children: [
              for (final r in _overflowMonthsRanges)
                RadioListTile<BtcRange>(
                  key: ValueKey('monthsOverflowSlot-${r.name}'),
                  title: Text(_btcRangeMonthsLongLabel(ctx, r)),
                  value: r,
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      app.setMonthsOverflowQuickRange(picked);
      onRange(picked);
    }
  }

  void _stepMonthsOverflowSlot(BuildContext context, int step) {
    final app = context.read<AppStateNotifier>();
    app.dismissSwipeChipHint();
    final current = app.monthsOverflowQuickRange;
    final ranges = _overflowMonthsRanges;
    final i = ranges.indexOf(current);
    final base = i < 0 ? 0 : i;
    final n = ranges.length;
    final next = ranges[(base + step) % n];
    if (next == current) return;
    app.setMonthsOverflowQuickRange(next);
    onRange(next);
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
    this.showChevron = false,
    this.minLabelWidth,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color chartColor;
  final VoidCallback? onLongPress;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final bool showChevron;
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
      compact: true,
      showChevron: showChevron,
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
    this.compact = false,
    this.showChevron = false,
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
  final bool compact;
  // Renders a small downward chevron next to the label to signal "tap opens a
  // menu." Used on the overflow range slot so the picker affordance is
  // visible.
  final bool showChevron;
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
        constraints: const BoxConstraints(minWidth: 36),
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 10 : AppSpacing.md,
          vertical: 8,
        ),
        alignment: Alignment.center,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Builder(
                builder: (_) {
                  final row = Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: AppTypography.body.copyWith(
                          fontSize: 14,
                          fontWeight:
                              widget.selected ? FontWeight.w600 : null,
                          color: activeColor,
                        ),
                      ),
                      if (widget.showChevron)
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Icon(
                            Icons.unfold_more,
                            size: 16,
                            color: activeColor,
                          ),
                        ),
                    ],
                  );
                  final minW = widget.minLabelWidth;
                  if (minW == null) return row;
                  // Stable-width slot so cycling labels (1Y..15Y, 1M..12M) and
                  // bold↔regular weight changes don't reflow the row. The row
                  // inside centers itself, so the chevron stays tight against
                  // the label rather than floating to the slot's edge. For
                  // chevron chips we add the chevron's own width (16px icon +
                  // 2px gap) so the slot still fits the widest label + chevron
                  // without overflow. SizedBox (not ConstrainedBox) because
                  // IntrinsicWidth ignores min constraints; +1px slack absorbs
                  // sub-pixel measurement differences.
                  final slotWidth =
                      minW + (widget.showChevron ? 18 : 0) + 1;
                  return SizedBox(width: slotWidth, child: row);
                },
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
class _EagerVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerMoveEvent && event.delta.dy != 0) {
      resolve(GestureDisposition.accepted);
    }
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

