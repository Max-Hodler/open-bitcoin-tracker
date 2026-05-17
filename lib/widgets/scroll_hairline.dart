import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 1px hairline that fades in by [strength] (0..1). Tone matches the static
/// `Divider(color: cs.outlineVariant)` used elsewhere — outlineVariant has a
/// baked-in alpha (~8% on the warm-brown surface), so we multiply that alpha
/// by `strength` for the fade-in instead of overwriting it; overwriting
/// would push the line to 100% opacity at full strength and read as a hard
/// black line.
///
/// Suppressed entirely in dark mode (returns an empty box) — the dark-mode
/// fade reads as a hard line against the near-black scaffold and was
/// intentionally hidden in commit c62d1ec.
///
/// Use this directly inside a `Positioned` (or wherever you can give it a
/// 1px-tall slot). For the common "scrollable body with a fade-in line at
/// its top edge" case, use [ScrollHairline] which wires the listener for you.
class ScrollHairlinePainter extends StatelessWidget {
  const ScrollHairlinePainter({super.key, required this.strength});

  final ValueListenable<double> strength;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: strength,
        builder: (context, t, _) {
          if (t == 0) return const SizedBox.shrink();
          final isDark = Theme.of(context).brightness == Brightness.dark;
          if (isDark) return const SizedBox.shrink();
          final base = Theme.of(context).colorScheme.outlineVariant;
          return ColoredBox(color: base.withValues(alpha: base.a * t));
        },
      ),
    );
  }
}

/// Wraps a scrollable body and paints a [ScrollHairlinePainter] along its
/// top edge that fades in over the first 24px of scroll. Mirrors the line
/// under the home screen's pinned header so every top bar in the app shares
/// one visual language for "content has scrolled under me."
///
/// Pass the original body (typically a `ListView` / `SingleChildScrollView`
/// inside a `Padding` / `SafeArea`) as [child]; the line is layered on top
/// inside an `IgnorePointer` so it never blocks gestures.
class ScrollHairline extends StatefulWidget {
  const ScrollHairline({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollHairline> createState() => _ScrollHairlineState();
}

class _ScrollHairlineState extends State<ScrollHairline> {
  final ValueNotifier<double> _t = ValueNotifier(0);

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final next = (n.metrics.pixels / 24.0).clamp(0.0, 1.0);
    if (next != _t.value) _t.value = next;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 1,
          child: ScrollHairlinePainter(strength: _t),
        ),
      ],
    );
  }
}
