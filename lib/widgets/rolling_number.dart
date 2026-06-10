import 'package:flutter/widgets.dart';

/// Measured cell metrics for the digit glyph '0' under a given style and
/// text scale. Laying out a TextPainter is a real shaping call into the
/// engine, and these widgets rebuild at price-tick cadence — so results are
/// memoized: they only change when the style or scale changes. The painter
/// used for measurement is disposed immediately.
class DigitCellMetrics {
  const DigitCellMetrics._(this.width, this.height, this.baseline);

  final double width;
  final double height;
  final double baseline;

  // TextStyle/TextScaler have value-based equality, so per-build copies of
  // the same style hit the cache. LRU-capped: distinct styles are few (price
  // header, converter…), but theme/color changes mint new keys over time.
  static final Map<(TextStyle, TextScaler), DigitCellMetrics> _cache = {};
  static const int _cacheCap = 8;

  static DigitCellMetrics of(TextStyle style, TextScaler textScaler) {
    final key = (style, textScaler);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // refresh LRU position
      return cached;
    }
    final tp = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final metrics = DigitCellMetrics._(
      tp.width,
      tp.height,
      tp.computeDistanceToActualBaseline(TextBaseline.alphabetic),
    );
    tp.dispose();
    if (_cache.length >= _cacheCap) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = metrics;
    return metrics;
  }
}

/// Renders a formatted numeric string where each digit lives on a vertical
/// strip. When the value changes, only the digits that actually change roll:
/// up if [direction] is positive, down if negative. Non-digit characters
/// (currency symbol, commas, decimal point) render statically.
class RollingNumber extends StatelessWidget {
  const RollingNumber({
    super.key,
    required this.text,
    required this.style,
    required this.direction,
    this.animate = true,
    this.duration = const Duration(milliseconds: 700),
    this.curve = Curves.easeOutCubic,
  });

  final String text;
  final TextStyle style;

  /// +1 = digits roll up (use when the underlying value increased).
  /// -1 = digits roll down (use when the underlying value decreased).
  ///  0 = no preferred direction; treated as up.
  final int direction;

  /// When false, digit changes snap instantly without rolling. Use this to
  /// suppress the roll for transient updates (e.g. chart-hover scrubbing)
  /// where animating every frame would be distracting.
  final bool animate;

  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final metrics =
        DigitCellMetrics.of(style, MediaQuery.textScalerOf(context));
    final cellHeight = metrics.height;
    final baseline = metrics.baseline;
    final capHeight = (style.fontSize ?? 14) * 0.52;
    final shiftY = cellHeight / 2 - (baseline - capHeight / 2);

    final children = <Widget>[];
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      final code = ch.codeUnitAt(0);
      final isDigit = code >= 0x30 && code <= 0x39;
      if (isDigit) {
        children.add(_RollingDigit(
          digit: code - 0x30,
          direction: direction >= 0 ? 1 : -1,
          animate: animate,
          style: style,
          duration: duration,
          curve: curve,
          // Position-based key so digit identity stays stable across rebuilds
          // (otherwise the comma shifting would re-key every digit and reset
          // the rolling state).
          key: ValueKey('digit-$i'),
        ));
      } else {
        children.add(SizedBox(
          height: cellHeight,
          child: Transform.translate(
            offset: Offset(0, shiftY),
            child: Text(ch, style: style),
          ),
        ));
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

class _RollingDigit extends StatefulWidget {
  const _RollingDigit({
    super.key,
    required this.digit,
    required this.direction,
    required this.animate,
    required this.style,
    required this.duration,
    required this.curve,
  });

  final int digit;
  final int direction;
  final bool animate;
  final TextStyle style;
  final Duration duration;
  final Curve curve;

  @override
  State<_RollingDigit> createState() => _RollingDigitState();
}

class _RollingDigitState extends State<_RollingDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  // Strip of digits rendered top-to-bottom this roll. For up-roll the strip
  // is [old, ..., new] and the window walks from index 0 → last (digits slide
  // upward, new digit enters from below). For down-roll the strip is reversed
  // to [new, ..., old] and the window walks from last → 0 (digits slide
  // downward, new digit enters from above).
  late List<int> _strip;
  // Index in _strip where the roll starts (0 for up, length-1 for down).
  late int _startIndex;
  // Index in _strip where the roll ends.
  late int _endIndex;

  @override
  void initState() {
    super.initState();
    _strip = [widget.digit];
    _startIndex = 0;
    _endIndex = 0;
  }

  @override
  void didUpdateWidget(covariant _RollingDigit old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (old.digit != widget.digit) {
      // Snap (no roll) when animate is off, OR when animate just turned on
      // this frame — the latter happens when the user lifts their finger off
      // the chart and the displayed price flips from hover to live; we don't
      // want the lift itself to trigger a roll back to the live price.
      final shouldRoll = widget.animate && old.animate;
      if (shouldRoll) {
        _runRoll(old.digit, widget.digit, widget.direction);
      } else {
        _controller.stop();
        setState(() {
          _strip = [widget.digit];
          _startIndex = 0;
          _endIndex = 0;
        });
      }
    }
  }

  void _runRoll(int oldDigit, int newDigit, int direction) {
    final seq = <int>[oldDigit];
    if (direction >= 0) {
      var d = oldDigit;
      while (d != newDigit) {
        d = (d + 1) % 10;
        seq.add(d);
      }
    } else {
      var d = oldDigit;
      while (d != newDigit) {
        d = (d + 9) % 10;
        seq.add(d);
      }
    }

    final List<int> strip;
    final int startIdx;
    final int endIdx;
    if (direction >= 0) {
      strip = seq;
      startIdx = 0;
      endIdx = seq.length - 1;
    } else {
      strip = seq.reversed.toList();
      startIdx = strip.length - 1;
      endIdx = 0;
    }

    setState(() {
      _strip = strip;
      _startIndex = startIdx;
      _endIndex = endIdx;
    });
    _controller
      ..stop()
      ..value = 0
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() {
          _strip = [newDigit];
          _startIndex = 0;
          _endIndex = 0;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics =
        DigitCellMetrics.of(widget.style, MediaQuery.textScalerOf(context));
    final cellHeight = metrics.height;
    final cellWidth = metrics.width;
    final baseline = metrics.baseline;
    final capHeight = (widget.style.fontSize ?? 14) * 0.52;
    final shiftY = cellHeight / 2 - (baseline - capHeight / 2);

    return SizedBox(
      width: cellWidth,
      height: cellHeight,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = widget.curve.transform(_controller.value);
            final pos = _startIndex + (_endIndex - _startIndex) * t;
            final strip = OverflowBox(
              minHeight: 0,
              maxHeight: double.infinity,
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: Offset(0, -pos * cellHeight + shiftY),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in _strip)
                      SizedBox(
                        height: cellHeight,
                        width: cellWidth,
                        child: Text('$d', style: widget.style),
                      ),
                  ],
                ),
              ),
            );
            // Only fade the cell edges while a roll is active — otherwise the
            // resting digit picks up the mask and looks dim at its top/bottom
            // (visible at large font sizes). The 18% band softens the slide
            // without ever touching an idle digit.
            if (!_controller.isAnimating) return strip;
            // dstIn alpha mask — only the alpha channel matters, RGB is discarded.
            return ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00000000),
                  Color(0xFF000000),
                  Color(0xFF000000),
                  Color(0x00000000),
                ],
                stops: [0.0, 0.18, 0.82, 1.0],
              ).createShader(bounds),
              child: strip,
            );
          },
        ),
      ),
    );
  }
}
