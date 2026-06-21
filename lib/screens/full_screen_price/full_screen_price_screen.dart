import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/app_enums.dart';
import '../../data/fiat.dart';
import '../../main.dart' show kDefaultOrientations, kLandscapeOrientations;
import '../../services/app_haptics.dart';
import '../../state/state.dart';
import '../../theme/theme.dart';
import '../../widgets/rolling_number.dart';

/// Full-screen, landscape live-price mode. Shows nothing but the live price
/// filling the screen; tapping anywhere pops back to the home screen.
/// Swiping left/right cycles the fiat currency with the same animation as the
/// home screen header.
///
/// The rest of the app may be portrait or landscape; this screen forces
/// landscape while it's on screen and restores the default set on exit — the
/// mirror image of the portrait-only [ConverterScreen]. It also hides the
/// system bars so the price truly owns the whole display.
class FullScreenPriceScreen extends StatefulWidget {
  const FullScreenPriceScreen({super.key, required this.currency});

  final Currency currency;

  @override
  State<FullScreenPriceScreen> createState() => _FullScreenPriceScreenState();
}

class _FullScreenPriceScreenState extends State<FullScreenPriceScreen> {
  // Direction the rolling digits should roll on the next tick: +1 = up (price
  // rose), -1 = down. Derived from successive USD rates via [_onPriceTick] —
  // mirroring the home header so the full-screen price rolls identically.
  LivePriceController? _priceController;
  double? _prevUsd;
  int _rollDirection = 1;

  // Active display currency (may change via swipe).
  late Currency _currency;

  // Direction the AnimatedSwitcher slides the incoming tile: +1 = enters from
  // the right (user swiped left / "next"), -1 = enters from the left.
  int _slideDir = 1;

  @override
  void initState() {
    super.initState();
    _currency = widget.currency;
    SystemChrome.setPreferredOrientations(kLandscapeOrientations);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<LivePriceController>();
    if (!identical(controller, _priceController)) {
      _priceController?.removeListener(_onPriceTick);
      _priceController = controller;
      _prevUsd = controller.rates.usd;
      controller.addListener(_onPriceTick);
    }
  }

  void _onPriceTick() {
    final usd = _priceController?.rates.usd;
    if (usd == null || usd <= 0) return;
    final prev = _prevUsd;
    _prevUsd = usd;
    if (prev == null || prev == usd) return;
    final direction = usd > prev ? 1 : -1;
    if (direction != _rollDirection && mounted) {
      setState(() => _rollDirection = direction);
    }
  }

  void _onSwipe(int dir) {
    final notifier = context.read<AppStateNotifier>();
    final selected = notifier.selectedCurrencies;
    // Record the swipe direction only when the cycle will actually advance.
    final pendingDir = selected.length >= 2 ? dir : null;
    if (notifier.cycleCurrency(dir)) {
      AppHaptics.selection();
      setState(() {
        _slideDir = pendingDir ?? dir;
        _currency = notifier.currency;
      });
    }
  }

  @override
  void dispose() {
    _priceController?.removeListener(_onPriceTick);
    // Leave the system UI mode alone — the home screen re-asserts the correct
    // mode for its orientation in didPopNext. Setting edgeToEdge here would
    // flash the system bars back on when returning to a landscape home screen.
    SystemChrome.setPreferredOrientations(kDefaultOrientations);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Colors.black;

    final currentPrice = context.select<LivePriceController, double?>(
      (c) => c.rates.forCurrency(_currency),
    );

    // SafeArea insets only the side with the camera cutout, which would shove
    // the centered price off true center. Mirror the larger inset onto both
    // sides (and top/bottom) so the safe box stays symmetric and the price
    // sits dead-center on the physical screen.
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final hInset =
        math.max(viewPadding.left, viewPadding.right) + AppSpacing.lg;
    final vInset = math.max(viewPadding.top, viewPadding.bottom);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hInset, vertical: vInset),
            // SizedBox.expand gives FittedBox a bounded box that fills the whole
            // (safe, symmetrically padded) screen. BoxFit.contain then scales the
            // price *up* to fill it — and re-fits on every tick, so the size
            // shrinks/grows automatically as digits come and go. Without the
            // expanding box, Center would hand FittedBox unbounded constraints
            // and the text would just render at its intrinsic size.
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: AnimatedSwitcher(
                  duration: AppSpacing.motionDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, anim) {
                    final isIncoming = child.key == ValueKey(_currency.code);
                    final begin = Offset(
                      (isIncoming ? 1.0 : -1.0) * _slideDir * 0.25,
                      0,
                    );
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: begin,
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: RollingNumber(
                    key: ValueKey(_currency.code),
                    text: currentPrice != null
                        ? formatFiat(currentPrice, _currency).tight
                        : '',
                    direction: _rollDirection,
                    style: AppTypography.display.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Gesture zone: centered 60×60% of the screen. No horizontal drag
          // handler so Android's back gesture is never intercepted. Tapping the
          // left half cycles backwards, right half cycles forwards; tapping dead
          // center (neither half resolves a cycle) pops back to the home screen.
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.6,
              heightFactor: 0.6,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final x = details.localPosition.dx;
                      final third = constraints.maxWidth / 3;
                      if (x < third) {
                        _onSwipe(-1);
                      } else if (x > third * 2) {
                        _onSwipe(1);
                      } else {
                        AppHaptics.selection();
                        Navigator.of(context).maybePop();
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
