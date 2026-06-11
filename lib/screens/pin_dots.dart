import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/theme.dart';

class PinDots extends StatefulWidget {
  const PinDots({
    super.key,
    required this.filled,
    required this.total,
    required this.checking,
  });

  final int filled;
  final int total;

  /// While true (PIN submitted, KDF running) the dots pulse in a staggered
  /// wave to acknowledge the input — without claiming it's correct.
  final bool checking;

  @override
  State<PinDots> createState() => _PinDotsState();
}

class _PinDotsState extends State<PinDots> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.checking) _pulse.repeat();
  }

  @override
  void didUpdateWidget(PinDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checking && !oldWidget.checking) {
      _pulse.repeat();
    } else if (!widget.checking && oldWidget.checking) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  double _scaleFor(int i) {
    if (!widget.checking) return 1.0;
    final phase = (_pulse.value - i / widget.total) % 1.0;
    return 1.0 - 0.3 * sin(phase * pi);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.palette;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.total; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Transform.scale(
              scale: _scaleFor(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: i < widget.filled
                      ? p.bitcoinOrange
                      : Colors.transparent,
                  border: Border.all(
                    color: i < widget.filled
                        ? p.bitcoinOrange
                        : cs.onSurfaceVariant,
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
