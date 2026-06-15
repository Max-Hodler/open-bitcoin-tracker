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
  // card). Compared via `!=` in
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

  // The curve that was on screen when the current zoom tween started. On a
  // zoom-IN (3D → 2D) the incoming dataset is shorter than the outgoing
  // window, so painting the new (short) curve while the window is still wide
  // shows an empty/cropped left edge until the window catches up. To match the
  // all-history ranges — which never swap the curve, only the window — we keep
  // painting this outgoing curve for the duration of a zoom-in and only adopt
  // the new spots when the tween settles. Null when no tween is mid-flight or
  // the transition is a zoom-out (the new curve already spans the window).
  List<FlSpot>? _prevSpots;
  bool _zoomingIn = false;

  // Animated window endpoints. When the parent changes windowStartMs/End,
  // we tween from the last-shown values to the new targets so the chart
  // feels like a camera zoom instead of a data morph.
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..addStatusListener((status) {
      // Once the zoom-in window has finished narrowing onto the new range,
      // drop the held outgoing curve so the new (shorter) curve takes over.
      // No setState needed: the controller already drives a rebuild via the
      // AnimatedBuilder on the completing frame, and this fires within it.
      if (status == AnimationStatus.completed && _prevSpots != null) {
        _prevSpots = null;
      }
    });
  double? _animFromStartX;
  double? _animFromEndX;
  double? _animFromMinY;
  double? _animFromMaxY;
  double _targetStartX = 0;
  double _targetEndX = 0;
  double _targetMinY = 0;
  double _targetMaxY = 0;

  // Index into _spots/data of the point under the user's finger, or null when
  // not touching. Drives both the visual indicator (showingIndicators) and
  // the onHover callback. Updated from raw pointer events, not fl_chart's
  // touch pipeline — see the comment in build().
  int? _touchedIndex;

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

  // Maps a touch position to the nearest data point and shows the indicator
  // there. Pixel→value mapping mirrors fl_chart's: linear over [minX, maxX]
  // across the full widget width (all titles/borders are hidden, so the plot
  // area is the whole box).
  void _handleTouch(Offset localPosition) {
    if (_zoom.isAnimating) {
      _clearTouch();
      return;
    }
    final width = context.size?.width ?? 0;
    if (width <= 0 || _spots.isEmpty) return;
    final x = _targetStartX +
        (localPosition.dx / width) * (_targetEndX - _targetStartX);
    // Binary search for the first spot at or right of x; spots are sorted.
    var lo = 0;
    var hi = _spots.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_spots[mid].x < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i = (lo > 0 && x - _spots[lo - 1].x < _spots[lo].x - x) ? lo - 1 : lo;
    if (i == _touchedIndex) return;
    setState(() => _touchedIndex = i);
    if (i < widget.data.length) widget.onHover(widget.data[i]);
  }

  void _clearTouch() {
    if (_touchedIndex == null) return;
    setState(() => _touchedIndex = null);
    widget.onHover(null);
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
      // A zoom-in is a narrowing window (new span < the window we're starting
      // from). Only then do we need to hold the outgoing curve: on a zoom-out
      // the incoming curve already covers the whole animating window, so the
      // normal path (paint the new spots immediately) shows no crop. _spots
      // still holds the outgoing curve here — build() rebuilds it for the new
      // data on the next frame — so snapshot it now.
      final newSpan = widget.windowEndMs - widget.windowStartMs;
      final fromSpan = (_animFromEndX! - _animFromStartX!).abs();
      _zoomingIn = newSpan < fromSpan;
      _prevSpots = _zoomingIn && !identical(_spotsForData, widget.data)
          ? _spots
          : null;
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
    final newSpots = _spots;
    final color = widget.color;

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

    // Scrubbing is deliberately NOT done through fl_chart's touch pipeline.
    // Its internal PanGestureRecognizer needs kPanSlop (~2× kTouchSlop) of
    // travel to claim the gesture, so any single-axis drag recognizer in the
    // arena — an ancestor scrollable, or our own spoilers below — beats it to
    // the claim and fl_chart gets a cancel: the indicator appeared on
    // touch-down and then vanished the moment the finger actually moved.
    //
    // Instead, the Listener reads raw pointer events (which bypass the
    // gesture arena entirely, so nobody can steal them), maps the finger to
    // the nearest data point, and drives the indicator via showingIndicators.
    // The no-op drag recognizer pair below stays purely as an arena spoiler:
    // it claims drags that start on the chart so ancestor scrollables (the
    // vertical CustomScrollView) don't scroll the page while the user scrubs.
    // fl_chart itself registers no recognizers here because lineTouchData
    // has enabled: false and no touchCallback.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handleTouch(e.localPosition),
      onPointerMove: (e) => _handleTouch(e.localPosition),
      onPointerUp: (_) => _clearTouch(),
      onPointerCancel: (_) => _clearTouch(),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          VerticalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  VerticalDragGestureRecognizer>(
            () => VerticalDragGestureRecognizer(),
            (instance) {
              // No callbacks: just an arena spoiler against ancestor vertical
              // scrolls that would otherwise grab pointers over the chart.
            },
          ),
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  HorizontalDragGestureRecognizer>(
            () => HorizontalDragGestureRecognizer(),
            (instance) {
              // No callbacks: arena spoiler against any ancestor horizontal
              // scroll.
            },
          ),
        },
        child: AnimatedBuilder(
      animation: _zoom,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_zoom.value);
        final minX = fromStart + (newTargetStart - fromStart) * t;
        final maxX = fromEnd + (newTargetEnd - fromEnd) * t;
        final minY = fromMinY + (newTargetMinY - fromMinY) * t;
        final maxY = fromMaxY + (newTargetMaxY - fromMaxY) * t;
        // Hold the outgoing (wider) curve while a zoom-in window is still
        // narrowing; once _prevSpots is cleared on completion we draw the new
        // curve. See _prevSpots. The scrub indicator is suppressed mid-zoom
        // (_handleTouch bails while animating), so indexing stays consistent.
        final spots =
            _prevSpots != null && _zoom.status != AnimationStatus.completed
                ? _prevSpots!
                : newSpots;
        return LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          // Touch handling is done by the Listener above; fl_chart only
          // paints the indicator for the showingIndicators we set on the bar.
          enabled: false,
          handleBuiltInTouches: false,
          getTouchLineStart: (_, _) => double.negativeInfinity,
          getTouchLineEnd: (_, _) => double.infinity,
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
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            showingIndicators: switch (_touchedIndex) {
              final i? when i < spots.length => [i],
              _ => const [],
            },
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
    ),
    );
  }

}
