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
  });

  final Widget card;
  final List<PricePoint> rangePillData;
  final double priceScale;
  final Currency currency;
  // Controls whether a bottom hairline is drawn under this row to separate it
  // from the next (first/middle: yes; only/last: no — those are the bottom of
  // the group).
  final StackCardPosition position;

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
  final _scrollController = ScrollController();
  // A stable key per cell so we can read each cell's laid-out width after the
  // frame and turn it into the scroll offset at which its leading divider
  // crosses the left screen edge. Cells are variable-width (long prices stretch
  // them past _kRangePillMinWidth), so a fixed stride drifts from the real
  // dividers. Keys are pooled by index and reused across rebuilds — minting
  // fresh GlobalKeys each build would tear down and rebuild every cell.
  final List<GlobalKey> _cellKeys = [];

  // Returns a stable key for cell [index], growing the pool as needed. The
  // child requests one key per cell during build; surplus keys left over from a
  // previous (longer) build are ignored by _recomputeDividerOffsets, which
  // reads only the first [_cellCount].
  GlobalKey _keyFor(int index) {
    while (_cellKeys.length <= index) {
      _cellKeys.add(GlobalKey());
    }
    return _cellKeys[index];
  }

  int _cellCount = 0;
  // Scroll offsets at which each inter-cell divider crosses the left screen
  // edge, ascending. Recomputed after layout whenever widths may have changed.
  List<double> _dividerOffsets = const [];
  // Index of the last divider already crossed (so we fire once per crossing).
  int _lastCrossedDivider = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  // Reads measured cell widths and computes the scroll offset at which each
  // inter-cell divider crosses the left screen edge. The rail is laid out
  // right-to-left (reverse: true): at offset 0 the left screen edge sits at the
  // rightmost pill's right edge, then walks left through the pills as the offset
  // grows. So a divider's crossing offset is the summed width of every cell (and
  // divider) to its right — the card width drops out entirely.
  void _recomputeDividerOffsets() {
    if (_cellCount == 0) return;
    final widths = <double>[];
    for (var i = 0; i < _cellCount; i++) {
      final box = _cellKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return; // not laid out yet
      widths.add(box.size.width);
    }
    // Cells are ordered left-to-right; walk from the rightmost cell leftward,
    // accumulating widths, so the divider nearest the card lands first.
    final offsets = <double>[];
    var acc = 0.0;
    for (var i = widths.length - 1; i >= 1; i--) {
      acc += widths[i];
      offsets.add(acc);
      acc += _kRangePillDividerWidth;
    }
    if (!listEquals(offsets, _dividerOffsets)) {
      setState(() => _dividerOffsets = offsets);
    }
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if (offset <= 0) {
      _lastCrossedDivider = 0;
      return;
    }
    // Count how many divider boundaries the current offset has passed.
    var crossed = 0;
    for (final boundary in _dividerOffsets) {
      if (offset >= boundary) {
        crossed++;
      } else {
        break;
      }
    }
    if (crossed != _lastCrossedDivider) {
      _lastCrossedDivider = crossed;
      AppHaptics.selection();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _recomputeDividerOffsets());
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          controller: _scrollController,
          reverse: true,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                rangePills,
                // The card carries an opaque background and a shadow on its
                // left edge so it reads as one level above the recessed pill
                // rail revealed to its left. The negative x-offset with zero
                // spread throws the blur leftward only; the card's own fill
                // keeps the shadow from bleeding under the text.
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        offset: const Offset(-2, 0),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  child: SizedBox(width: fullWidth, child: widget.card),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
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
    final dateFormat = DateFormat(
      "d MMM ''yy",
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
