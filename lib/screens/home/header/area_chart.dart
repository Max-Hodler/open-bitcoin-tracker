import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../api/api.dart';

class AreaChart extends StatefulWidget {
  const AreaChart({
    super.key,
    required this.data,
    required this.windowStartMs,
    required this.windowEndMs,
    required this.color,
    required this.logScale,
    required this.rangeKey,
    required this.onHover,
  });

  final List<PricePoint> data;
  final int windowStartMs;
  final int windowEndMs;
  final Color color;
  final bool logScale;
  // Opaque identity used only to trigger the zoom tween when the caller
  // switches what time window is being displayed (e.g. 1M → 3M on the price
  // card, or `m1` → `y1` on the hashrate card). Compared via `!=` in
  // didUpdateWidget; the chart never reads any semantics off it.
  final Object rangeKey;
  final ValueChanged<PricePoint?> onHover;

  @override
  State<AreaChart> createState() => _AreaChartState();
}

class _AreaChartState extends State<AreaChart>
    with SingleTickerProviderStateMixin {
  List<PricePoint>? _spotsForData;
  bool _spotsForLogScale = false;
  late List<FlSpot> _spots;

  // Animated window endpoints. When the parent changes windowStartMs/End,
  // we tween from the last-shown values to the new targets so the chart
  // feels like a camera zoom instead of a data morph.
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  double? _animFromStartX;
  double? _animFromEndX;
  double? _animFromMinY;
  double? _animFromMaxY;
  double _targetStartX = 0;
  double _targetEndX = 0;
  double _targetMinY = 0;
  double _targetMaxY = 0;
  bool _transitioning = false;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _rebuildSpots() {
    final data = widget.data;
    final logScale = widget.logScale;
    final spots = <FlSpot>[
      for (final p in data)
        FlSpot(
          p.t.toDouble(),
          logScale && p.price > 0 ? math.log(p.price) / math.ln10 : p.price,
        ),
    ];
    _spots = spots;
    _spotsForData = data;
    _spotsForLogScale = logScale;
  }

  // Min/max y over spots whose x falls inside [startX, endX], with 5% padding.
  // Spots are sorted by x, so we can scan linearly; lists are small enough.
  (double, double) _windowYFit(double startX, double endX) {
    double? minY, maxY;
    for (final s in _spots) {
      if (s.x < startX) continue;
      if (s.x > endX) break;
      if (minY == null || s.y < minY) minY = s.y;
      if (maxY == null || s.y > maxY) maxY = s.y;
    }
    if (minY == null || maxY == null) {
      minY = _spots.first.y;
      maxY = _spots.first.y;
    }
    if (minY == maxY) maxY = minY + 1;
    final pad = (maxY - minY) * 0.05;
    return (minY - pad, maxY + pad);
  }

  @override
  void didUpdateWidget(covariant AreaChart old) {
    super.didUpdateWidget(old);
    // The zoom tween should fire only on user-initiated transitions: changing
    // the range (1M → 3M animates the all-history camera) or toggling log
    // scale. The raw window endpoints drift forward by a few ms on every
    // rebuild because windowEndMs trails DateTime.now(), and the data list
    // gets a new identity on every currency switch (priceUsd × usdToCurrency
    // produces a fresh list). Triggering the tween on either of those would
    // re-fit minY/maxY to the rescaled spots and visibly bump the chart on
    // every tick or fiat switch — most noticeably on 1D where the Y-range is
    // tight enough that the rescale-delta is a large fraction of the box.
    final shouldZoom = old.rangeKey != widget.rangeKey ||
        old.logScale != widget.logScale;
    if (shouldZoom) {
      // Capture the currently-displayed values (mid-tween or settled) as
      // the "from" so rapid re-taps pick up where we are, then restart the
      // controller to animate toward the new window.
      final t = _zoom.value;
      if (_animFromStartX != null && _animFromEndX != null) {
        _animFromStartX =
            _animFromStartX! + (_targetStartX - _animFromStartX!) * t;
        _animFromEndX = _animFromEndX! + (_targetEndX - _animFromEndX!) * t;
        _animFromMinY = _animFromMinY! + (_targetMinY - _animFromMinY!) * t;
        _animFromMaxY = _animFromMaxY! + (_targetMaxY - _animFromMaxY!) * t;
      } else {
        _animFromStartX = _targetStartX;
        _animFromEndX = _targetEndX;
        _animFromMinY = _targetMinY;
        _animFromMaxY = _targetMaxY;
      }
      _zoom.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!identical(_spotsForData, widget.data) ||
        _spotsForLogScale != widget.logScale) {
      _rebuildSpots();
    }
    final cs = Theme.of(context).colorScheme;
    final spots = _spots;
    final color = widget.color;
    final data = widget.data;
    final onHover = widget.onHover;

    final newTargetStart = widget.windowStartMs.toDouble();
    final newTargetEnd = widget.windowEndMs.toDouble();
    final (newTargetMinY, newTargetMaxY) =
        _windowYFit(newTargetStart, newTargetEnd);
    _targetStartX = newTargetStart;
    _targetEndX = newTargetEnd;
    _targetMinY = newTargetMinY;
    _targetMaxY = newTargetMaxY;

    final fromStart = _animFromStartX ?? newTargetStart;
    final fromEnd = _animFromEndX ?? newTargetEnd;
    final fromMinY = _animFromMinY ?? newTargetMinY;
    final fromMaxY = _animFromMaxY ?? newTargetMaxY;

    // The chart sits inside a vertical CustomScrollView and (on the hashrate
    // card) has a horizontal SingleChildScrollView sibling. fl_chart's
    // PanGestureRecognizer competes with the scroll's VerticalDragGestureRecognizer
    // in the gesture arena, and the first touch on the chart frequently loses
    // — the user sees the indicator from the tap-down notification but no
    // drag updates fire because the scroll claimed the gesture. Wrapping the
    // chart in a deeper Vertical+Horizontal drag recognizer pair keeps any
    // ancestor scrollable from claiming pointers that started on the chart;
    // fl_chart's own pan recognizer (deeper still, on the LineChart's
    // RenderObject) wins arena on motion and drives the scrub indicator.
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
          () => VerticalDragGestureRecognizer(),
          (instance) {
            // No callbacks: just an arena spoiler against ancestor vertical
            // scrolls that would otherwise grab pointers over the chart.
          },
        ),
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          () => HorizontalDragGestureRecognizer(),
          (instance) {
            // No callbacks: arena spoiler against any ancestor horizontal
            // scroll. fl_chart's pan recognizer is deeper in the tree, so it
            // still wins for actual drag updates on the chart.
          },
        ),
      },
      child: AnimatedBuilder(
      animation: _zoom,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_zoom.value);
        _transitioning = _zoom.isAnimating;
        final minX = fromStart + (newTargetStart - fromStart) * t;
        final maxX = fromEnd + (newTargetEnd - fromEnd) * t;
        final minY = fromMinY + (newTargetMinY - fromMinY) * t;
        final maxY = fromMaxY + (newTargetMaxY - fromMaxY) * t;
        return LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          getTouchLineStart: (_, _) => double.negativeInfinity,
          getTouchLineEnd: (_, _) => double.infinity,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 0,
            getTooltipItems: (spots) =>
                [for (final _ in spots) null],
          ),
          getTouchedSpotIndicator: (_, indicators) => [
            for (final _ in indicators)
              TouchedSpotIndicatorData(
                FlLine(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.onSurfaceVariant.withValues(alpha: 0),
                      cs.onSurfaceVariant,
                      cs.onSurfaceVariant,
                      cs.onSurfaceVariant.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.15, 0.85, 1.0],
                  ),
                  strokeWidth: 1,
                  dashArray: const [4, 4],
                ),
                FlDotData(
                  show: true,
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 5,
                    color: cs.onSurface,
                    strokeWidth: 0,
                  ),
                ),
              ),
          ],
          touchCallback: (event, response) {
            if (_transitioning) {
              onHover(null);
              return;
            }
            if (!event.isInterestedForInteractions ||
                response == null ||
                response.lineBarSpots == null ||
                response.lineBarSpots!.isEmpty) {
              onHover(null);
              return;
            }
            final spot = response.lineBarSpots!.first;
            final i = spot.spotIndex;
            if (i < 0 || i >= data.length) {
              onHover(null);
              return;
            }
            onHover(data[i]);
          },
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.18),
                  color.withValues(alpha: 0.12),
                  color.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
      },
    ),
    );
  }

}
