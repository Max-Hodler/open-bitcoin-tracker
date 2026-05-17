import 'package:flutter/material.dart';

/// A standard text-input caret: a thin vertical bar that blinks at ~1Hz.
///
/// Pass [keystrokeSignal] (any value that changes on each user keystroke) so
/// the caret resets to fully visible on every input — matches `EditableText`'s
/// behavior so the caret never disappears in the middle of typing.
///
/// `TickerMode` still applies, so the animation auto-mutes when an enclosing
/// route is no longer current.
class BlinkingCaret extends StatefulWidget {
  const BlinkingCaret({
    super.key,
    required this.color,
    required this.height,
    this.width = 2,
    this.keystrokeSignal,
  });

  final Color color;
  final double height;
  final double width;
  final Object? keystrokeSignal;

  @override
  State<BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<BlinkingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    // 500ms half-period = 1Hz blink, matching Flutter's EditableText.
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(BlinkingCaret old) {
    super.didUpdateWidget(old);
    if (widget.keystrokeSignal != old.keystrokeSignal) {
      _blink.value = 1;
      _blink.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (_, _) => Opacity(
        opacity: _blink.value >= 0.5 ? 1 : 0,
        // Square ends + no border-radius to match Flutter's standard
        // EditableText caret rendering on Android.
        child: ColoredBox(
          color: widget.color,
          child: SizedBox(width: widget.width, height: widget.height),
        ),
      ),
    );
  }
}
