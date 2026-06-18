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
    with TickerProviderStateMixin {
  List<PricePoint>? _spotsForData;
  late List<FlSpot> _spots;
  List<FlSpot>? _linearSpots;
  List<FlSpot>? _logSpots;
  late final AnimationController _scaleFadeController;
  bool? _scaleDisplayLogScale = false;
  bool get _activeLogScale => _scaleDisplayLogScale ?? widget.logScale;

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

  // Drives the orange ripple that radiates out of the selected-point circle.
  // Repeats for as long as a point is touched; stopped (and reset) on release
  // so it isn't burning frames while idle.
  // Duration of one ring's full 0→1 expansion. Set on the controller in
  // _handleTouch (not only here) so hot reload picks up tweaks — a late final
  // field initializer runs once and won't re-read a changed constant.
  static const Duration _rippleDuration = Duration(milliseconds: 4200);

  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: _rippleDuration,
  );

  @override
  void initState() {
    super.initState();
    _scaleDisplayLogScale = widget.logScale;
    _scaleFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1.0,
    )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          if (!mounted) return;
          if (_activeLogScale != widget.logScale) {
            setState(() {
              _scaleDisplayLogScale = widget.logScale;
              _animFromStartX = null;
              _animFromEndX = null;
              _animFromMinY = null;
              _animFromMaxY = null;
              _prevSpots = null;
            });
          }
          Future.microtask(() {
            if (mounted) {
              _scaleFadeController.forward();
            }
          });
        }
      });
  }

  @override
  void dispose() {
    _zoom.dispose();
    _ripple.dispose();
    _scaleFadeController.dispose();
    super.dispose();
  }

  void _rebuildCache() {
    final data = widget.data;
    _linearSpots = [
      for (final p in data)
        FlSpot(p.t.toDouble(), p.price),
    ];
    _logSpots = [
      for (final p in data)
        FlSpot(
          p.t.toDouble(),
          p.price > 0 ? math.log(p.price) / math.ln10 : p.price,
        ),
    ];
    _spotsForData = data;
    _spots = _activeLogScale ? _logSpots! : _linearSpots!;
  }

  // Min/max y over spots whose x falls inside [startX, endX], with 5% padding.
  // Spots are sorted by x, so we can scan linearly; lists are small enough.
  (double, double) _windowYFit(List<FlSpot> spots, double startX, double endX) {
    double? minY, maxY;
    for (final s in spots) {
      if (s.x < startX) continue;
      if (s.x > endX) break;
      if (minY == null || s.y < minY) minY = s.y;
      if (maxY == null || s.y > maxY) maxY = s.y;
    }
    if (minY == null || maxY == null) {
      minY = spots.isNotEmpty ? spots.first.y : 0.0;
      maxY = spots.isNotEmpty ? spots.first.y : 1.0;
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
    if (_zoom.isAnimating || _scaleFadeController.value < 1.0) {
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
    if (!_ripple.isAnimating) {
      _ripple.duration = _rippleDuration;
      _ripple.repeat();
    }
    if (i == _touchedIndex) return;
    setState(() => _touchedIndex = i);
    if (i < widget.data.length) widget.onHover(widget.data[i]);
  }

  void _clearTouch() {
    _ripple.stop();
    _ripple.reset();
    if (_touchedIndex == null) return;
    setState(() => _touchedIndex = null);
    widget.onHover(null);
  }

  @override
  void didUpdateWidget(covariant AreaChart old) {
    super.didUpdateWidget(old);
    // The zoom tween should fire only on user-initiated transitions: changing
    // the range (1M → 3M animates the all-history camera). The raw window
    // endpoints drift forward by a few ms on every rebuild because windowEndMs
    // trails DateTime.now(), and the data list gets a new identity on every
    // currency switch (priceUsd × usdToCurrency produces a fresh list).
    // Triggering the tween on either of those would re-fit minY/maxY to the
    // rescaled spots and visibly bump the chart on every tick or fiat switch.
    if (old.logScale != widget.logScale) {
      _scaleFadeController.reverse();
    } else if (old.rangeKey != widget.rangeKey) {
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
    if (!identical(_spotsForData, widget.data) || _linearSpots == null || _logSpots == null) {
      _rebuildCache();
    }
    final cs = Theme.of(context).colorScheme;
    final color = widget.color;

    final targetSpots = _activeLogScale ? _logSpots! : _linearSpots!;

    final newTargetStart = widget.windowStartMs.toDouble();
    final newTargetEnd = widget.windowEndMs.toDouble();
    final (newTargetMinY, newTargetMaxY) =
        _windowYFit(targetSpots, newTargetStart, newTargetEnd);
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
          animation: Listenable.merge([_zoom, _scaleFadeController]),
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(_zoom.value);
            final minX = fromStart + (newTargetStart - fromStart) * t;
            final maxX = fromEnd + (newTargetEnd - fromEnd) * t;
            final minY = fromMinY + (newTargetMinY - fromMinY) * t;
            final maxY = fromMaxY + (newTargetMaxY - fromMaxY) * t;

            _spots = _activeLogScale ? _logSpots! : _linearSpots!;

            // Hold the outgoing (wider) curve while a zoom-in window is still
            // narrowing; once _prevSpots is cleared on completion we draw the new
            // curve. See _prevSpots. The scrub indicator is suppressed mid-zoom
            // (_handleTouch bails while animating), so indexing stays consistent.
            final spots =
                _prevSpots != null && _zoom.status != AnimationStatus.completed
                    ? _prevSpots!
                    : _spots;
            // Value-space coordinates of the dot fl_chart is painting for the
            // touched point, used to position the ripple overlay. Null when not
            // scrubbing or the index is out of range for the current curve.
            final touched = switch (_touchedIndex) {
              final i? when i < spots.length => spots[i],
              _ => null,
            };
            final chart = LineChart(
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
            // The ripple needs both the value→pixel mapping (this frame's
            // min/max, the box size) and a clock independent of the zoom tween,
            // so it rides on _ripple via its own AnimatedBuilder and paints on
            // top of the chart. RepaintBoundary keeps the pulsing repaints from
            // dirtying the chart layer.
            return Opacity(
              opacity: Curves.easeInOut.transform(_scaleFadeController.value),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  chart,
                  if (touched != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _ripple,
                            builder: (context, _) => CustomPaint(
                              painter: _RipplePainter(
                                spotX: touched.x,
                                spotY: touched.y,
                                minX: minX,
                                maxX: maxX,
                                minY: minY,
                                maxY: maxY,
                                progress: _ripple.value,
                                color: cs.primary,
                              ),
                            ),
                          ),
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

// Concentric orange rings expanding out of the selected point on the chart.
// progress is one 0→1 sweep of the repeating ripple controller; we stagger a
// few rings across that phase so there's always a wave mid-flight.
class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.spotX,
    required this.spotY,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.progress,
    required this.color,
  });

  // Value-space position of the dot and the visible value window, used to map
  // the spot to a pixel offset the same way fl_chart lays out the plot area
  // (the whole box, since all titles/borders are hidden).
  final double spotX;
  final double spotY;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double progress;
  final Color color;

  static const int _ringCount = 3;
  static const double _maxRadius = 26;
  // Matches the FlDotCirclePainter radius the chart paints for the selected
  // point. Rings are clipped outside this disc so none of the ripple shows on
  // top of the black dot.
  static const double _dotRadius = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final spanX = maxX - minX;
    final spanY = maxY - minY;
    if (spanX == 0 || spanY == 0) return;
    final dx = (spotX - minX) / spanX * size.width;
    // y is inverted: high value sits near the top of the box.
    final dy = (1 - (spotY - minY) / spanY) * size.height;
    final center = Offset(dx, dy);

    // Clip out the dot so the rings only ever appear around it, never over it.
    canvas.save();
    canvas.clipPath(
      Path()
        ..addRect(Offset.zero & size)
        ..addOval(Rect.fromCircle(center: center, radius: _dotRadius))
        ..fillType = PathFillType.evenOdd,
    );

    for (var i = 0; i < _ringCount; i++) {
      // Each ring is offset in phase so they trail one another; wrap into 0..1.
      final t = (progress + i / _ringCount) % 1.0;
      final radius = t * _maxRadius;
      // Fade out as the ring grows; ease the alpha so it lingers small and
      // dies off gently at the rim.
      final alpha = (1 - t) * (1 - t);
      if (alpha <= 0.01) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * (1 - t) + 0.5
        ..color = color.withValues(alpha: alpha * 0.55);
      canvas.drawCircle(center, radius, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.progress != progress ||
      old.spotX != spotX ||
      old.spotY != spotY ||
      old.minX != minX ||
      old.maxX != maxX ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.color != color;
}
